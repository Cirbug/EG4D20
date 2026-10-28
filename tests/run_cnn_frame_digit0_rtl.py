#!/usr/bin/env python3
"""RTL-check the fixed-ROI FPGA digit path against the quantized model."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile

import numpy as np
import torch
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "cnn" / "exports" / "eg4d20_digit_int8_20261026_v2"
RTL_DIR = ROOT / "uisrc" / "01_rtl"

sys.path.insert(0, str(ROOT))
from cnn.quantize_digit_model import load_checkpoint, make_bias_codes, quantize_weights, quantized_forward  # noqa: E402


def main() -> int:
    parser_args = sys.argv[1:]
    if len(parser_args) > 1:
        raise SystemExit("usage: run_cnn_frame_digit0_rtl.py [320x180_image.png]")
    image_path = Path(parser_args[0]) if parser_args else ROOT / "photo" / "2026.10.17" / "Screenshot 2026-10-27 13-27-15_320x180_gray.png"
    with Image.open(image_path) as source:
        gray = np.asarray(source.convert("L"), dtype=np.uint8)
    if gray.shape != (180, 320):
        raise ValueError(f"expected a 320x180 image, got {gray.shape[1]}x{gray.shape[0]}")

    roi = gray[10:66:2, 24:80:2].copy()
    invert = int((roi >= 128).sum()) > int((roi < 128).sum())
    if invert:
        roi = 255 - roi

    metadata = json.loads((EXPORT / "metadata.json").read_text(encoding="utf-8"))
    checkpoint_path = Path(metadata["base_checkpoint"])
    if not checkpoint_path.is_absolute():
        checkpoint_path = ROOT / checkpoint_path
    _, model = load_checkpoint(checkpoint_path)
    weights, scales = quantize_weights(model)
    shifts = metadata["activation_shifts"]
    bias_codes = make_bias_codes(model, scales, shifts)
    tensor = torch.from_numpy(roi.copy()).view(1, 1, 28, 28).float() / 255.0
    expected = int(quantized_forward(tensor, model, weights, scales, shifts, bias_codes).argmax(1).item())
    if expected != 0:
        raise RuntimeError(f"fixed ROI software prediction is {expected}, expected labeled digit 0")

    with tempfile.TemporaryDirectory(prefix="eg4d20_digit0_rtl_") as temp_dir:
        temp = Path(temp_dir)
        stimulus = temp / "image.hex"
        with stimulus.open("w", encoding="ascii", newline="\n") as output:
            output.writelines(f"{int(pixel):02x}\n" for pixel in gray.reshape(-1))
        binary = temp / "tb_cnn_frame_digit0_pipe.vvp"
        subprocess.run(
            [
                "iverilog", "-g2012", "-DCNN_SIM", "-s", "tb_cnn_frame_digit0_pipe",
                "-o", str(binary),
                str(ROOT / "tests" / "tb_cnn_frame_digit0_pipe.sv"),
                str(RTL_DIR / "cnn_frame_digit0_pipe.v"),
                str(RTL_DIR / "cnn_digit_infer.v"),
                str(EXPORT / "cnn_digit_params.v"),
            ],
            cwd=ROOT,
            check=True,
        )
        result = subprocess.run(
            ["vvp", str(binary), f"+IMAGE={stimulus}", f"+EXPECTED={expected}"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        print(f"source={image_path} roi=24,10,56,56 invert={int(invert)} expected={expected}")
        print(result.stdout, end="")
        if result.returncode:
            print(result.stderr, file=sys.stderr, end="")
            raise SystemExit(result.returncode)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
