#!/usr/bin/env python3
"""Find handwritten digit blobs in a grayscale frame and normalize to 28x28."""

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


DEFAULT_ROI = (24, 38, 296, 112)


@dataclass(frozen=True)
class DigitBlob:
    index: int
    row: int
    column: int
    x: int
    y: int
    width: int
    height: int


def _group_rows(boxes, median_height):
    tolerance = max(10.0, median_height * 0.7)
    rows = []
    for box in sorted(boxes, key=lambda item: item[1] + item[3] / 2):
        center_y = box[1] + box[3] / 2
        matching = [row for row in rows if abs(row["center"] - center_y) <= tolerance]
        if matching:
            row = min(matching, key=lambda item: abs(item["center"] - center_y))
            row["boxes"].append(box)
            row["center"] = sum(b[1] + b[3] / 2 for b in row["boxes"]) / len(row["boxes"])
        else:
            rows.append({"center": center_y, "boxes": [box]})
    rows.sort(key=lambda row: row["center"])
    return [sorted(row["boxes"], key=lambda item: item[0]) for row in rows]


def normalize_blob(gray, mask, box, output_size=28, ink_size=20):
    x, y, width, height = box
    gray_crop = gray[y : y + height, x : x + width]
    mask_crop = mask[y : y + height, x : x + width]
    ink = cv2.bitwise_and(255 - gray_crop, mask_crop)

    scale = ink_size / max(width, height)
    scaled_width = max(1, round(width * scale))
    scaled_height = max(1, round(height * scale))
    resized = cv2.resize(ink, (scaled_width, scaled_height), interpolation=cv2.INTER_AREA)
    canvas = np.zeros((output_size, output_size), dtype=np.uint8)
    left = (output_size - scaled_width) // 2
    top = (output_size - scaled_height) // 2
    canvas[top : top + scaled_height, left : left + scaled_width] = resized
    return canvas


def parse_roi(value):
    try:
        roi = tuple(int(part.strip()) for part in value.split(","))
    except ValueError as error:
        raise argparse.ArgumentTypeError("ROI must be four comma-separated integers: x,y,width,height") from error
    if len(roi) != 4:
        raise argparse.ArgumentTypeError("ROI must be four comma-separated integers: x,y,width,height")
    return roi


def segment_digits(
    gray,
    min_height=13,
    min_area=18,
    adaptive_c=9,
    roi=DEFAULT_ROI,
    color_rgb=None,
    close_kernel=2,
):
    if gray.ndim != 2:
        raise ValueError("expected a single-channel grayscale image")
    if min(gray.shape) < 3:
        raise ValueError("image is too small to segment")
    if close_kernel <= 0:
        raise ValueError("close_kernel must be positive")
    if color_rgb is not None and (
        color_rgb.ndim != 3 or color_rgb.shape[:2] != gray.shape or color_rgb.shape[2] != 3
    ):
        raise ValueError("color_rgb must be an RGB image with the same dimensions as gray")
    roi_x, roi_y, roi_width, roi_height = roi
    if (
        roi_x < 0
        or roi_y < 0
        or roi_width <= 0
        or roi_height <= 0
        or roi_x + roi_width > gray.shape[1]
        or roi_y + roi_height > gray.shape[0]
    ):
        raise ValueError(f"ROI {roi} is outside image dimensions {gray.shape[1]}x{gray.shape[0]}")
    gray = gray[roi_y : roi_y + roi_height, roi_x : roi_x + roi_width]
    green_overlay = None
    if color_rgb is not None:
        color_roi = color_rgb[roi_y : roi_y + roi_height, roi_x : roi_x + roi_width]
        hsv = cv2.cvtColor(color_roi, cv2.COLOR_RGB2HSV)
        green_overlay = cv2.inRange(hsv, np.array([35, 60, 40]), np.array([90, 255, 255]))
        gray = gray.copy()
        gray[green_overlay > 0] = 255

    blurred = cv2.GaussianBlur(gray, (3, 3), 0)
    block_size = min(31, min(gray.shape))
    if block_size % 2 == 0:
        block_size -= 1
    block_size = max(3, block_size)
    mask = cv2.adaptiveThreshold(
        blurred,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY_INV,
        block_size,
        adaptive_c,
    )
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (close_kernel, close_kernel))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel)
    if green_overlay is not None:
        green_exclusion = cv2.dilate(
            green_overlay,
            cv2.getStructuringElement(cv2.MORPH_RECT, (21, 21)),
        )
        overlay_contours, _ = cv2.findContours(
            green_exclusion,
            cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE,
        )
        for contour in overlay_contours:
            x, y, width, height = cv2.boundingRect(contour)
            if width >= 40 and height >= 40:
                cv2.drawContours(green_exclusion, [contour], -1, 255, cv2.FILLED)
        mask[green_exclusion > 0] = 0

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    boxes = []
    for contour in contours:
        x, y, width, height = cv2.boundingRect(contour)
        if height < min_height or cv2.contourArea(contour) < min_area:
            continue
        if width < 3 or width > height * 1.8:
            continue
        boxes.append((x, y, width, height))

    if not boxes:
        raise ValueError("no digit-like blobs found; adjust threshold or ROI")

    median_height = float(np.median([box[3] for box in boxes]))
    rows = _group_rows(boxes, median_height)
    ordered = [box for row in rows for box in row]
    blobs = []
    crops = []
    index = 0
    for row_index, row in enumerate(rows):
        for column_index, box in enumerate(row):
            x, y, width, height = box
            blobs.append(
                DigitBlob(index, row_index, column_index, x + roi_x, y + roi_y, width, height)
            )
            crops.append(normalize_blob(gray, mask, box))
            index += 1
    return mask, blobs, crops


def make_contact_sheet(crops, blobs, columns=6):
    tile_size = 88
    rows = (len(crops) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * tile_size, rows * (tile_size + 20)), "#d9d9d9")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
    for index, (crop, blob) in enumerate(zip(crops, blobs)):
        x = (index % columns) * tile_size
        y = (index // columns) * (tile_size + 20)
        tile = Image.fromarray(crop).resize((tile_size, tile_size), Image.Resampling.NEAREST)
        sheet.paste(tile.convert("RGB"), (x, y))
        draw.text((x + 3, y + tile_size + 2), f"#{index} [{blob.x},{blob.y}]", fill="black", font=font)
    return sheet


def make_bbox_preview(rgb, blobs):
    preview = Image.fromarray(rgb).convert("RGB")
    draw = ImageDraw.Draw(preview)
    try:
        font = ImageFont.truetype("arial.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for blob in blobs:
        x2 = blob.x + blob.width - 1
        y2 = blob.y + blob.height - 1
        draw.rectangle((blob.x, blob.y, x2, y2), outline="#ff3030", width=3)
        draw.rectangle((blob.x, max(0, blob.y - 22), blob.x + 40, blob.y), fill="#ff3030")
        draw.text((blob.x + 2, max(0, blob.y - 21)), str(blob.index), fill="white", font=font)
    return preview


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path, help="input image or 320x180 OBS frame")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parent / "outputs" / "digit_segmentation",
    )
    parser.add_argument("--min-height", type=int, default=13)
    parser.add_argument("--min-area", type=int, default=18)
    parser.add_argument("--adaptive-c", type=int, default=9)
    parser.add_argument("--close-kernel", type=int, default=2)
    parser.add_argument("--roi", type=parse_roi, default=DEFAULT_ROI, help="digit area as x,y,width,height")
    parser.add_argument("--expect", type=int, default=None, help="fail unless this many blobs are found")
    args = parser.parse_args()

    if args.output.exists() and any(args.output.iterdir()):
        parser.error(f"output directory is not empty: {args.output}; choose a new --output path")
    args.output.mkdir(parents=True, exist_ok=True)
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

    Image.fromarray(mask).save(args.output / "threshold_mask.png")
    digit_dir = args.output / "digits"
    digit_dir.mkdir()
    for index, crop in enumerate(crops):
        Image.fromarray(crop).save(digit_dir / f"digit_{index:02d}.png")
    make_contact_sheet(crops, blobs).save(args.output / "contact_sheet.png")
    make_bbox_preview(rgb, blobs).save(args.output / "bbox_preview.png")
    with (args.output / "manifest.json").open("w", encoding="utf-8") as manifest:
        json.dump(
            {
                "source": str(args.image.resolve()),
                "source_size": [int(gray.shape[1]), int(gray.shape[0])],
                "roi": list(args.roi),
                "crop_size": [28, 28],
                "count": len(blobs),
                "expected_count": args.expect,
                "blobs": [asdict(blob) for blob in blobs],
            },
            manifest,
            indent=2,
        )
    print(f"found={len(blobs)} output={args.output.resolve()}")
    for blob in blobs:
        print(
            f"index={blob.index:02d} row={blob.row} col={blob.column} "
            f"bbox=({blob.x},{blob.y},{blob.width},{blob.height})"
        )
    if args.expect is not None and len(blobs) != args.expect:
        print(f"count_mismatch expected={args.expect} found={len(blobs)}; previews were saved")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
