#!/usr/bin/env python3
"""Compose public MNIST digits into labeled 320x180 full-frame samples."""

import argparse
import gzip
import random
import struct
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


WIDTH, HEIGHT = 320, 180
DOWNSAMPLE = 6


def downsample_block_average(image: Image.Image, factor: int = DOWNSAMPLE) -> Image.Image:
    if factor <= 0 or image.width % factor or image.height % factor:
        raise ValueError("image dimensions must be divisible by a positive downsample factor")
    return image.resize(
        (image.width // factor, image.height // factor),
        Image.Resampling.BOX,
    )


def read_idx_images(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as stream:
        magic, count, rows, columns = struct.unpack(">IIII", stream.read(16))
        if magic != 2051 or rows != 28 or columns != 28:
            raise ValueError(f"unexpected MNIST image file: {path}")
        payload = stream.read(count * rows * columns)
    if len(payload) != count * rows * columns:
        raise ValueError(f"truncated MNIST image file: {path}")
    return [Image.frombytes("L", (28, 28), payload[i * 784 : (i + 1) * 784]) for i in range(count)]


def read_idx_labels(path: Path):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rb") as stream:
        magic, count = struct.unpack(">II", stream.read(8))
        if magic != 2049:
            raise ValueError(f"unexpected MNIST label file: {path}")
        labels = stream.read(count)
    if len(labels) != count:
        raise ValueError(f"truncated MNIST label file: {path}")
    return list(labels)


def tight_crop(image: Image.Image) -> Image.Image:
    bbox = image.getbbox()
    return image.crop(bbox) if bbox else image


def write_voc(path: Path, image_name: str, boxes):
    root = ET.Element("annotation")
    ET.SubElement(root, "filename").text = image_name
    size = ET.SubElement(root, "size")
    ET.SubElement(size, "width").text = str(WIDTH)
    ET.SubElement(size, "height").text = str(HEIGHT)
    ET.SubElement(size, "depth").text = "1"
    for label, (left, top, right, bottom) in boxes:
        obj = ET.SubElement(root, "object")
        ET.SubElement(obj, "name").text = str(label)
        bndbox = ET.SubElement(obj, "bndbox")
        # Pascal VOC coordinates are 1-based and inclusive.
        ET.SubElement(bndbox, "xmin").text = str(left + 1)
        ET.SubElement(bndbox, "ymin").text = str(top + 1)
        ET.SubElement(bndbox, "xmax").text = str(right)
        ET.SubElement(bndbox, "ymax").text = str(bottom)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mnist-root", type=Path, default=Path(__file__).parent / "data" / "mnist" / "MNIST" / "raw")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--count", type=int, default=20)
    parser.add_argument("--digits-per-frame", type=int, default=10)
    parser.add_argument("--seed", type=int, default=20261027)
    parser.add_argument(
        "--binary",
        action="store_true",
        help="threshold source digit strokes before 6x6 averaging; output may contain gray levels",
    )
    args = parser.parse_args()
    if args.count <= 0 or not 1 <= args.digits_per_frame <= 10:
        parser.error("count must be positive and digits-per-frame must be 1..10")

    root = args.mnist_root.expanduser().resolve()
    image_path = next((root / name for name in ("train-images-idx3-ubyte", "train-images-idx3-ubyte.gz") if (root / name).is_file()), None)
    label_path = next((root / name for name in ("train-labels-idx1-ubyte", "train-labels-idx1-ubyte.gz") if (root / name).is_file()), None)
    if image_path is None or label_path is None:
        raise FileNotFoundError(f"MNIST IDX files not found under {root}")
    images, labels = read_idx_images(image_path), read_idx_labels(label_path)
    if len(images) != len(labels):
        raise ValueError("MNIST image and label counts differ")

    rng = random.Random(args.seed)
    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    for frame_index in range(args.count):
        canvas = Image.new("L", (WIDTH * DOWNSAMPLE, HEIGHT * DOWNSAMPLE), 0)
        boxes = []
        attempts = 0
        while len(boxes) < args.digits_per_frame and attempts < 2000:
            attempts += 1
            source_index = rng.randrange(len(images))
            digit = tight_crop(images[source_index])
            if args.binary:
                digit = digit.point(lambda value: 255 if value >= 96 else 0)
                digit = tight_crop(digit)
            scale = rng.uniform(1.0, 1.7)
            width = max(8, round(digit.width * scale))
            height = max(8, round(digit.height * scale))
            digit = digit.resize(
                (width * DOWNSAMPLE, height * DOWNSAMPLE),
                Image.Resampling.NEAREST if args.binary else Image.Resampling.BILINEAR,
            )
            left = rng.randint(2, WIDTH - width - 2)
            top = rng.randint(2, HEIGHT - height - 2)
            right, bottom = left + width, top + height
            if any(left < old_right + 2 and right > old_left - 2 and top < old_bottom + 2 and bottom > old_top - 2 for _, (old_left, old_top, old_right, old_bottom) in boxes):
                continue
            canvas.paste(digit, (left * DOWNSAMPLE, top * DOWNSAMPLE))
            boxes.append((labels[source_index], (left, top, right, bottom)))
        if len(boxes) != args.digits_per_frame:
            raise RuntimeError(f"could not place enough digits in frame {frame_index}")
        image_name = f"frame_{frame_index:04d}.png"
        downsample_block_average(canvas).save(output_dir / image_name)
        write_voc(output_dir / f"frame_{frame_index:04d}.xml", image_name, boxes)
    print(
        f"generated={args.count} output={output_dir} size={WIDTH}x{HEIGHT} "
        f"source_size={WIDTH * DOWNSAMPLE}x{HEIGHT * DOWNSAMPLE} "
        f"downsample={DOWNSAMPLE}x{DOWNSAMPLE}_average "
        f"digits_per_frame={args.digits_per_frame} binary_source={args.binary}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
