#!/usr/bin/env python3
"""Compare the EG4D20 digit inference RTL with the exported fixed-point model."""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cnn.quantize_digit_model import (
    flat_weight_list,
    load_checkpoint,
    make_bias_codes,
    quantize_weights,
    quantized_forward,
)


EXPORT = ROOT / "cnn" / "exports" / "eg4d20_digit_int8_20261026_v2"
RTL = ROOT / "uisrc" / "01_rtl" / "cnn_digit_infer.v"
PARAMS = EXPORT / "cnn_digit_params.v"
TESTBENCH = ROOT / "tests" / "tb_cnn_digit_infer.sv"
SAMPLE_DIRS = (
    "Screenshot 2026-10-26 18-32-09_320x180_gray",
    "Screenshot 2026-10-26 18-33-03_320x180_gray",
    "Screenshot 2026-10-26 18-33-12_320x180_gray",
    "Screenshot 2026-10-26 18-33-58_320x180_gray",
    "Screenshot 2026-10-26 18-34-42_320x180_gray",
    "Screenshot 2026-10-26 18-35-18_320x180_gray",
    "Screenshot 2026-10-26 18-35-44_320x180_gray",
    "Screenshot 2026-10-26 18-36-25_320x180_gray_roi_tuned",
)


def validate_export(weights: dict, bias_codes: dict, shifts: list[int]) -> list[int]:
    exported_weights = [int(line, 16) for line in (EXPORT / "cnn_digit_weights.hex").read_text().splitlines()]
    expected_weights = [value & 0xFF for value in flat_weight_list(weights)]
    if exported_weights[: len(expected_weights)] != expected_weights:
        raise RuntimeError("weight HEX does not match the checkpoint quantization")
    if any(exported_weights[len(expected_weights) :]):
        raise RuntimeError("unused weight ROM entries must be zero")

    params_text = PARAMS.read_text(encoding="ascii")
    exported_bias = {
        int(key): int(value, 16)
        for key, value in re.findall(r"7'd(\d+): bias_value = 32'h([0-9A-Fa-f]{8});", params_text)
    }
    for layer_id, name in enumerate(("conv1", "conv2", "conv3", "classifier")):
        for channel, value in enumerate(bias_codes[name].tolist()):
            key = (layer_id << 5) | channel
            if exported_bias.get(key) != (int(value) & 0xFFFFFFFF):
                raise RuntimeError(f"bias parameter mismatch at {name}[{channel}]")

    exported_shifts = [
        int(value)
        for value in re.findall(r"assign conv[123]_shift = 4'd(\d+);", params_text)
    ]
    if exported_shifts != shifts:
        raise RuntimeError(f"activation shifts mismatch: {exported_shifts} != {shifts}")
    return expected_weights


def load_samples() -> tuple[torch.Tensor, torch.Tensor]:
    sample_root = ROOT / "cnn" / "outputs" / "photo_digits_320x180"
    pixels = []
    labels = []
    for directory in SAMPLE_DIRS:
        digit_dir = sample_root / directory / "digits"
        for label in range(10):
            path = digit_dir / f"digit_{label:02d}.png"
            if not path.is_file():
                raise FileNotFoundError(path)
            with Image.open(path) as image:
                gray = np.asarray(image.convert("L"), dtype=np.uint8)
            if gray.shape != (28, 28):
                raise RuntimeError(f"{path} has unexpected shape {gray.shape}")
            pixels.append(gray)
            labels.append(label)
    images = torch.from_numpy(np.stack(pixels)).unsqueeze(1).float() / 255.0
    return images, torch.tensor(labels, dtype=torch.long)


def run_simulation(
    images: torch.Tensor,
    reference_classes: torch.Tensor,
    start_index: int,
) -> str:
    vectors = images.mul(255.0).round().clamp(0, 255).to(torch.uint8).numpy()
    with tempfile.TemporaryDirectory(prefix="eg4d20_cnn_digit_") as temporary:
        temp = Path(temporary)
        stimulus_file = temp / "stimulus.hex"
        expected_file = temp / "expected.hex"
        binary = temp / "tb_cnn_digit_infer.vvp"

        with stimulus_file.open("w", encoding="ascii", newline="\n") as output:
            for image in vectors:
                output.writelines(f"{int(value):02x}\n" for value in image.reshape(-1))
        expected_file.write_text(
            "".join(f"{int(value):x}\n" for value in reference_classes.tolist()),
            encoding="ascii",
        )

        compile_command = [
            "iverilog",
            "-g2012",
            "-DCNN_SIM",
            f"-DSAMPLE_COUNT={len(reference_classes)}",
            "-s",
            "tb_cnn_digit_infer",
            "-o",
            str(binary),
            str(TESTBENCH),
            str(RTL),
            str(PARAMS),
        ]
        subprocess.run(compile_command, cwd=ROOT, check=True)
        result = subprocess.run(
            [
                "vvp",
                str(binary),
                f"+STIMULUS={stimulus_file}",
                f"+EXPECTED={expected_file}",
                f"+START_INDEX={start_index}",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if result.returncode:
            raise RuntimeError(f"Icarus simulation failed:\n{result.stdout}{result.stderr}")
        return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=int, default=0, help="first sample index (default: 0)")
    parser.add_argument("--limit", type=int, default=80, help="run the first N samples (default: 80)")
    args = parser.parse_args()
    if not 0 <= args.start < 80:
        parser.error("--start must be in [0, 79]")
    if not 1 <= args.limit <= 80 - args.start:
        parser.error("--limit must fit within the remaining sample range")

    metadata = json.loads((EXPORT / "metadata.json").read_text(encoding="utf-8"))
    checkpoint, model = load_checkpoint(Path(metadata["base_checkpoint"]))
    del checkpoint
    weights, scales = quantize_weights(model)
    shifts = [int(value) for value in metadata["activation_shifts"]]
    bias_codes = make_bias_codes(model, scales, shifts)
    validate_export(weights, bias_codes, shifts)

    images, labels = load_samples()
    images = images[args.start : args.start + args.limit]
    labels = labels[args.start : args.start + args.limit]
    scores = quantized_forward(images, model, weights, scales, shifts, bias_codes)
    reference_classes = scores.argmax(dim=1)
    correct = int((reference_classes == labels).sum().item())
    print(
        f"software_reference_camera_accuracy={correct}/{len(labels)} "
        f"sample_range={args.start}:{args.start + args.limit}",
        flush=True,
    )
    print(run_simulation(images, reference_classes, args.start), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
