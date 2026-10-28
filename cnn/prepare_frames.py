#!/usr/bin/env python3
"""Batch-convert images with selectable color, geometry, and output format."""

import argparse
from pathlib import Path

from PIL import Image

if __package__:
    from .image_preprocess import INPUT_HEIGHT, INPUT_WIDTH, prepare_image
else:
    from image_preprocess import INPUT_HEIGHT, INPUT_WIDTH, prepare_image


IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png", ".tif", ".tiff", ".webp"}


def _target_path(
    image_path: Path,
    input_path: Path,
    output_dir: Path,
    color: str,
    transform: str,
    fmt: str,
) -> Path:
    relative_path = Path(image_path.name) if input_path.is_file() else image_path.relative_to(input_path)
    geometry = "original" if transform == "none" else "320x180"
    return output_dir / relative_path.parent / f"{relative_path.stem}_{geometry}_{color}.{fmt}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="an image file or a directory of images")
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--overwrite", action="store_true", help="replace existing output images")
    parser.add_argument("--color", choices=("gray", "rgb"), default="gray", help="output color mode")
    parser.add_argument(
        "--transform",
        choices=("fit", "stretch", "none"),
        default="fit",
        help="fit center-crops to 320x180; stretch resizes; none keeps source size",
    )
    parser.add_argument(
        "--format",
        choices=("png", "jpg", "bmp"),
        default="png",
        dest="format_name",
        help="output image format",
    )
    parser.add_argument(
        "--resample",
        choices=("nearest", "bilinear"),
        default="bilinear",
        help="resize filter; use nearest to preserve binary pixels",
    )
    args = parser.parse_args()

    input_path = args.input.expanduser().resolve()
    geometry = "original" if args.transform == "none" else "320x180"
    requested_output = args.output_dir or (
        Path(__file__).parent / "outputs" / f"frames_{geometry}_{args.color}"
    )
    output_dir = requested_output.expanduser().resolve()
    if not input_path.exists():
        parser.error(f"input does not exist: {input_path}")

    if input_path.is_file():
        if input_path.suffix.lower() not in IMAGE_SUFFIXES:
            parser.error(f"unsupported image format: {input_path.suffix}")
        image_paths = [input_path]
    elif input_path.is_dir():
        image_paths = sorted(
            path
            for path in input_path.rglob("*")
            if path.is_file()
            and path.suffix.lower() in IMAGE_SUFFIXES
            and not path.resolve().is_relative_to(output_dir)
        )
    else:
        parser.error(f"input is not a file or directory: {input_path}")

    if not image_paths:
        parser.error(f"no supported images found in: {input_path}")

    converted = 0
    skipped = 0
    failed = 0
    for image_path in image_paths:
        target_path = _target_path(
            image_path,
            input_path,
            output_dir,
            args.color,
            args.transform,
            args.format_name,
        )
        if target_path.exists() and not args.overwrite:
            print(f"skip exists: {target_path}")
            skipped += 1
            continue
        try:
            with Image.open(image_path) as source:
                source_size = source.size
                prepared = prepare_image(
                    source,
                    color=args.color,
                    transform=args.transform,
                    resample=args.resample,
                )
            expected_size = (INPUT_WIDTH, INPUT_HEIGHT) if args.transform != "none" else source_size
            expected_mode = "L" if args.color == "gray" else "RGB"
            if prepared.size != expected_size or prepared.mode != expected_mode:
                raise RuntimeError("preprocessor returned an unexpected image format")
            target_path.parent.mkdir(parents=True, exist_ok=True)
            save_kwargs = {"format": args.format_name.upper()}
            if args.format_name == "jpg":
                save_kwargs["quality"] = 95
            prepared.save(target_path, **save_kwargs)
            print(
                f"converted {image_path} {source_size} -> {target_path} "
                f"{prepared.size} mode={prepared.mode}"
            )
            converted += 1
        except (OSError, ValueError, RuntimeError) as error:
            print(f"failed {image_path}: {error}")
            failed += 1

    print(f"converted={converted} skipped={skipped} failed={failed} output_dir={output_dir}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
