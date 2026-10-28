#!/usr/bin/env python3
"""Evaluate exported INT8 arithmetic on the prepared camera patch dataset."""

import argparse
import json
from pathlib import Path

import torch
from PIL import Image
from torchvision import transforms

from digit_model import SmallDigitCNN
from quantize_digit_model import calibrate_shifts, make_bias_codes, quantize_weights, quantized_forward


def load_images(records):
    transform = transforms.ToTensor()
    images = []
    labels = []
    for record in records:
        with Image.open(record["patch"]) as source:
            images.append(transform(source.convert("L")))
        labels.append(record["label"])
    return torch.stack(images), torch.tensor(labels, dtype=torch.long)


def evaluate(checkpoint_path, train_records, test_records, calibration_limit, fixed_shifts=None):
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=True)
    model = SmallDigitCNN()
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    weights, scales = quantize_weights(model)
    if fixed_shifts is None:
        calibration_images, _ = load_images(train_records[:calibration_limit])
        shifts = calibrate_shifts(calibration_images, model, weights, scales, 128)
    else:
        shifts = list(fixed_shifts)
    bias_codes = make_bias_codes(model, scales, shifts)
    images, labels = load_images(test_records)
    with torch.inference_mode():
        float_predictions = model(images).argmax(1)
        quantized_predictions = quantized_forward(images, model, weights, scales, shifts, bias_codes).argmax(1)
    float_correct = int((float_predictions == labels).sum())
    quant_correct = int((quantized_predictions == labels).sum())
    disagreement = int((float_predictions != quantized_predictions).sum())
    return {
        "checkpoint": str(checkpoint_path.resolve()),
        "test_count": int(labels.numel()),
        "float_correct": float_correct,
        "float_accuracy": float_correct / labels.numel(),
        "quantized_correct": quant_correct,
        "quantized_accuracy": quant_correct / labels.numel(),
        "float_quantized_disagreements": disagreement,
        "activation_shifts": shifts,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", type=Path, default=Path(__file__).parent / "outputs" / "camera_cv_20261028" / "dataset.json")
    parser.add_argument("--fold-dir", type=Path, default=Path(__file__).parent / "outputs" / "camera_cv_20261028" / "cross_validation")
    parser.add_argument("--baseline-export", type=Path, default=Path(__file__).parent / "exports" / "eg4d20_digit_int8_20261026_v2")
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--calibration-limit", type=int, default=512)
    args = parser.parse_args()
    manifest = json.loads(args.dataset.read_text(encoding="utf-8"))
    records = manifest["records"]
    baseline_metadata = json.loads((args.baseline_export / "metadata.json").read_text(encoding="utf-8"))
    baseline_checkpoint = Path(baseline_metadata["base_checkpoint"])
    result = []
    for name, train_groups, test_group in (("xjp_huihua__ljc", ("xjp", "huihua"), "ljc"), ("xjp_ljc__huihua", ("xjp", "ljc"), "huihua")):
        train_records = [r for r in records if r["group"] in train_groups]
        test_records = [r for r in records if r["group"] == test_group]
        baseline = evaluate(baseline_checkpoint, train_records, test_records, args.calibration_limit, baseline_metadata["activation_shifts"])
        adapted = evaluate(args.fold_dir / f"fold_{name}" / "checkpoint.pt", train_records, test_records, args.calibration_limit)
        result.append({"fold": name, "train_groups": train_groups, "test_group": test_group, "current_r14_int8": baseline, "adapted_int8": adapted})
    output = {"results": result}
    if args.output is None:
        args.output = args.fold_dir / "quantized_camera_metrics.json"
    args.output.write_text(json.dumps(output, indent=2), encoding="utf-8")
    for item in result:
        print(
            f"QUANTIZED {item['fold']}: current_r14={item['current_r14_int8']['quantized_correct']}/{item['current_r14_int8']['test_count']} "
            f"({item['current_r14_int8']['quantized_accuracy']:.3f}) adapted_float={item['adapted_int8']['float_correct']}/"
            f"{item['adapted_int8']['test_count']} ({item['adapted_int8']['float_accuracy']:.3f}) adapted_int8="
            f"{item['adapted_int8']['quantized_correct']}/{item['adapted_int8']['test_count']} "
            f"({item['adapted_int8']['quantized_accuracy']:.3f}) q_disagreements={item['adapted_int8']['float_quantized_disagreements']} "
            f"shifts={item['adapted_int8']['activation_shifts']}"
        )
    print(f"OUTPUT={args.output.resolve()}")


if __name__ == "__main__":
    main()
