#!/usr/bin/env python3
"""Segment and classify handwritten digits from a frame using a PC checkpoint."""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
import torch

if __package__:
    from .digit_model import SmallDigitCNN
    from .segment_digits import (
        DEFAULT_ROI,
        make_bbox_preview,
        make_contact_sheet,
        parse_roi,
        segment_digits,
    )
else:
    from digit_model import SmallDigitCNN
    from segment_digits import DEFAULT_ROI, make_bbox_preview, make_contact_sheet, parse_roi, segment_digits


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--checkpoint", type=Path, default=Path(__file__).parent / "checkpoints" / "digit_cnn_mnist.pt")
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "outputs" / "digit_predictions")
    parser.add_argument("--expect", type=int, default=None)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--roi", type=parse_roi, default=DEFAULT_ROI, help="digit area as x,y,width,height")
    parser.add_argument("--min-height", type=int, default=13)
    parser.add_argument("--min-area", type=int, default=18)
    parser.add_argument("--adaptive-c", type=int, default=9)
    parser.add_argument("--close-kernel", type=int, default=2)
    args = parser.parse_args()

    if args.output.exists() and any(args.output.iterdir()):
        parser.error(f"output directory is not empty: {args.output}; choose a new --output path")
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=True)
    if checkpoint.get("architecture") != "small_digit_cnn_28x28_v1":
        raise ValueError("checkpoint architecture is not small_digit_cnn_28x28_v1")
    classes = checkpoint["classes"]
    if args.device == "auto":
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        device = torch.device(args.device)
    model = SmallDigitCNN().to(device)
    model.load_state_dict(checkpoint["model_state"])
    model.eval()

    with Image.open(args.image) as source:
        rgb = np.asarray(source.convert("RGB"), dtype=np.uint8)
        gray = np.asarray(source.convert("L"), dtype=np.uint8)
    mask, blobs, crops = segment_digits(
        gray,
        min_height=args.min_height,
        min_area=args.min_area,
        adaptive_c=args.adaptive_c,
        roi=args.roi,
        color_rgb=rgb,
        close_kernel=args.close_kernel,
    )
    batch = torch.from_numpy(np.stack(crops).copy()).unsqueeze(1).float().div_(255.0).to(device)
    with torch.inference_mode():
        probabilities = model(batch).softmax(dim=1)
    scores, indices = probabilities.max(dim=1)

    args.output.mkdir(parents=True, exist_ok=True)
    Image.fromarray(mask).save(args.output / "threshold_mask.png")
    make_bbox_preview(rgb, blobs).save(args.output / "bbox_preview.png")
    digit_dir = args.output / "digits"
    digit_dir.mkdir()
    annotated = make_contact_sheet(crops, blobs)
    draw = ImageDraw.Draw(annotated)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
    results = []
    for index, (blob, crop) in enumerate(zip(blobs, crops)):
        prediction = classes[int(indices[index])]
        confidence = float(scores[index])
        Image.fromarray(crop).save(digit_dir / f"digit_{index:02d}_{prediction}.png")
        x = (index % 6) * 88
        y = (index // 6) * 108 + 88
        draw.rectangle((x, y, x + 87, y + 19), fill="#ffffff")
        draw.text((x + 3, y + 2), f"-> {prediction} {confidence:.2f}", fill="#111111", font=font)
        results.append(
            {
                "index": index,
                "row": blob.row,
                "column": blob.column,
                "bbox": [blob.x, blob.y, blob.width, blob.height],
                "prediction": prediction,
                "confidence": confidence,
            }
        )
        print(
            f"index={index:02d} row={blob.row} col={blob.column} "
            f"bbox=({blob.x},{blob.y},{blob.width},{blob.height}) "
            f"prediction={prediction} confidence={confidence:.3f}"
        )
    annotated.save(args.output / "predictions.png")
    (args.output / "predictions.json").write_text(
        json.dumps(
            {
                "source": str(args.image.resolve()),
                "roi": list(args.roi),
                "checkpoint": str(args.checkpoint.resolve()),
                "checkpoint_mnist_test_accuracy": checkpoint.get("mnist_test_accuracy"),
                "results": results,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"device={device} checkpoint_mnist_test_accuracy={checkpoint.get('mnist_test_accuracy')}")
    print(f"output={args.output.resolve()}")
    if args.expect is not None and len(blobs) != args.expect:
        print(f"count_mismatch expected={args.expect} found={len(blobs)}; previews were saved")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
