#!/usr/bin/env python3
"""Crop labeled digit boxes from Pascal VOC XML annotations."""

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageOps


IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}


def find_image(xml_path: Path, root: ET.Element, image_arg: Path | None) -> Path:
    if image_arg is not None:
        return image_arg
    filename = root.findtext("filename")
    candidates = [xml_path.with_name(filename)] if filename else []
    candidates.append(xml_path.with_suffix(".png"))
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"cannot find image for {xml_path}")


def parse_boxes(xml_path: Path):
    root = ET.parse(xml_path).getroot()
    boxes = []
    for index, obj in enumerate(root.findall("object")):
        label = obj.findtext("name", "unknown").strip()
        box = obj.find("bndbox")
        if box is None:
            raise ValueError(f"object {index} has no bndbox")
        values = {name: int(float(box.findtext(name))) for name in ("xmin", "ymin", "xmax", "ymax")}
        if values["xmax"] < values["xmin"] or values["ymax"] < values["ymin"]:
            raise ValueError(f"invalid box in {xml_path}: {values}")
        boxes.append((index, label, values))
    if not boxes:
        raise ValueError(f"no objects in {xml_path}")
    return boxes


def crop_box(image: Image.Image, box: dict[str, int], margin: int) -> Image.Image:
    width, height = image.size
    left = max(0, box["xmin"] - 1 - margin)
    top = max(0, box["ymin"] - 1 - margin)
    right = min(width, box["xmax"] + margin)
    bottom = min(height, box["ymax"] + margin)
    return image.crop((left, top, right, bottom))


def normalize_crop(crop: Image.Image, output_size: int, ink_size: int = 20) -> Image.Image:
    """Convert a dark-on-light crop to centered, light-on-dark CNN input."""
    gray = ImageOps.autocontrast(crop.convert("L"))
    ink = ImageOps.invert(gray)
    # Ignore the annotation margin and fit only the visible dark strokes.
    bbox = ink.point(lambda value: 255 if value >= 32 else 0).getbbox()
    if bbox is None:
        raise ValueError("crop contains no visible dark strokes")
    ink = ink.crop(bbox)
    fitted = ImageOps.contain(ink, (ink_size, ink_size), Image.Resampling.BILINEAR)
    canvas = Image.new("L", (output_size, output_size), 0)
    canvas.paste(fitted, ((output_size - fitted.width) // 2, (output_size - fitted.height) // 2))
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", type=Path, help="Pascal VOC XML file or directory")
    parser.add_argument("--image", type=Path, default=None, help="image when XML filename is not beside the XML")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--margin", type=int, default=8, help="extra source pixels around each box")
    parser.add_argument("--size", type=int, default=None, help="also save a square normalized crop, e.g. 28")
    args = parser.parse_args()
    if args.margin < 0 or (args.size is not None and args.size <= 0):
        parser.error("margin must be nonnegative and size must be positive")

    xml_input = args.xml.expanduser().resolve()
    xml_paths = [xml_input] if xml_input.is_file() else sorted(xml_input.rglob("*.xml"))
    if not xml_paths:
        parser.error(f"no XML annotations found: {xml_input}")
    output_dir = args.output_dir.expanduser().resolve()
    manifest = []
    for xml_path in xml_paths:
        root = ET.parse(xml_path).getroot()
        image_path = find_image(xml_path, root, args.image)
        with Image.open(image_path) as source:
            image = ImageOps.exif_transpose(source).convert("L")
            boxes = parse_boxes(xml_path)
            stem = xml_path.stem
            for index, label, box in boxes:
                crop = crop_box(image, box, args.margin)
                label_dir = output_dir / str(label)
                label_dir.mkdir(parents=True, exist_ok=True)
                raw_path = label_dir / f"{stem}_{index:02d}_raw.png"
                crop.save(raw_path)
                normalized_path = None
                if args.size is not None:
                    canvas = normalize_crop(crop, args.size)
                    normalized_path = label_dir / f"{stem}_{index:02d}_{args.size}x{args.size}.png"
                    canvas.save(normalized_path)
                manifest.append({
                    "source": str(image_path),
                    "annotation": str(xml_path),
                    "label": label,
                    "index": index,
                    "bbox": box,
                    "raw_crop": str(raw_path),
                    "normalized_crop": str(normalized_path) if normalized_path else None,
                })
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"cropped={len(manifest)} output={output_dir}")
    for item in manifest:
        print(f"index={item['index']:02d} label={item['label']} bbox={item['bbox']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
