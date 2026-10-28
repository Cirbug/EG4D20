#!/usr/bin/env python3
"""Quantize the digit CNN to signed INT8 weights and byte activations."""

import argparse
import json
import math
from pathlib import Path

import torch
from PIL import Image
from torch.nn import functional as F
from torchvision import datasets, transforms

if __package__:
    from .digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN
else:
    from digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN


WEIGHT_ORDER = ("conv1", "conv2", "conv3", "classifier")
LAYER_NAMES = ("conv1", "conv2", "conv3")
WEIGHT_DEPTH = 4096


def load_checkpoint(path):
    checkpoint = torch.load(path, map_location="cpu", weights_only=True)
    if checkpoint.get("architecture") != "small_digit_cnn_28x28_v1":
        raise ValueError("checkpoint architecture is not small_digit_cnn_28x28_v1")
    model = SmallDigitCNN()
    model.load_state_dict(checkpoint["model_state"])
    model.eval()
    return checkpoint, model


def quantize_weights(model):
    quantized = {}
    scales = {}
    for name in WEIGHT_ORDER:
        weight = getattr(model, name).weight.detach().cpu()
        scale = float(weight.abs().max()) / 127.0
        if scale == 0.0:
            scale = 1.0
        quantized[name] = torch.round(weight / scale).clamp(-127, 127).to(torch.int32)
        scales[name] = scale
    return quantized, scales


def choose_shift(raw_values):
    maximum = int(raw_values.clamp_min(0).max().item())
    if maximum <= 255:
        return 0
    return max(0, math.ceil(math.log2(maximum / 255.0)))


def requantize(raw, shift):
    positive = raw.clamp_min(0)
    if shift:
        positive = (positive + (1 << (shift - 1))) >> shift
    return positive.clamp_max(255).to(torch.uint8)


def quantized_forward(images, model, weights, scales, shifts, bias_codes=None):
    image = torch.round(images * 255.0).clamp(0, 255).to(torch.uint8)
    input_scale = 1.0 / 255.0
    for index, name in enumerate(LAYER_NAMES):
        layer = getattr(model, name)
        weight_scale = scales[name]
        if bias_codes is None:
            bias = layer.bias.detach().cpu()
        else:
            bias = bias_codes[name]
        raw = F.conv2d(
            image.to(torch.int32),
            weights[name],
            padding=1,
        )
        if bias_codes is None:
            raw_bias = torch.round(bias / (input_scale * weight_scale)).to(torch.int32)
        else:
            raw_bias = bias.to(torch.int32)
        raw = raw + raw_bias.view(1, -1, 1, 1)
        image = requantize(raw, shifts[index])
        image = F.max_pool2d(image.to(torch.float32), 2).to(torch.uint8)
        input_scale *= weight_scale * (2**shifts[index])

    features = image.to(torch.int32).sum(dim=(2, 3)).to(torch.int32)
    classifier = model.classifier
    scores = features @ weights["classifier"].to(torch.int32).t()
    if bias_codes is None:
        fc_bias = torch.round(
            classifier.bias.detach().cpu() * 9.0 / (input_scale * scales["classifier"])
        ).to(torch.int32)
    else:
        fc_bias = bias_codes["classifier"].to(torch.int32)
    return scores + fc_bias.view(1, -1)


def calibration_images(data_root, train_dirs, per_frame_limit):
    images = []
    if train_dirs:
        transform = transforms.ToTensor()
        for directory in train_dirs:
            manifest_path = directory / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest.get("count") != 10:
                raise ValueError(f"expected 10 crops in {directory}")
            for index in range(10):
                path = directory / "digits" / f"digit_{index:02d}.png"
                with Image.open(path) as source:
                    images.append(transform(source.convert("L")))
    else:
        mnist = datasets.MNIST(
            data_root,
            train=True,
            download=False,
            transform=transforms.ToTensor(),
        )
        images.extend(mnist[index][0] for index in range(min(per_frame_limit, len(mnist))))
    if not images:
        raise ValueError("calibration set is empty")
    return torch.stack(images)


def calibrate_shifts(images, model, quantized_weights, scales, batch_size):
    shifts = []
    input_scale = 1.0 / 255.0
    current = torch.round(images * 255.0).clamp(0, 255).to(torch.uint8)
    for name in LAYER_NAMES:
        layer = getattr(model, name)
        weight_scale = scales[name]
        bias = torch.round(layer.bias.detach().cpu() / (input_scale * weight_scale)).to(torch.int32)
        raw_batches = []
        for batch in current.split(batch_size):
            raw = F.conv2d(batch.to(torch.int32), quantized_weights[name], padding=1)
            raw += bias.view(1, -1, 1, 1)
            raw_batches.append(raw)
        raw_all = torch.cat(raw_batches, dim=0)
        shift = choose_shift(raw_all)
        output = requantize(raw_all, shift)
        current = F.max_pool2d(output.to(torch.float32), 2).to(torch.uint8)
        saturation = float((raw_all.clamp_min(0) >= (256 << shift)).float().mean().item())
        shifts.append(shift)
        input_scale *= weight_scale * (2**shift)
        print(
            f"calibration layer={name} shift={shift} max_raw={int(raw_all.max())} "
            f"activation_scale={input_scale:.9g} saturation_fraction={saturation:.6f}"
        )
    return shifts


def make_bias_codes(model, scales, shifts):
    result = {}
    input_scale = 1.0 / 255.0
    for name, shift in zip(LAYER_NAMES, shifts):
        layer = getattr(model, name)
        weight_scale = scales[name]
        result[name] = torch.round(layer.bias.detach().cpu() / (input_scale * weight_scale)).to(torch.int32)
        input_scale *= weight_scale * (2**shift)
    result["classifier"] = torch.round(
        model.classifier.bias.detach().cpu() * 9.0 / (input_scale * scales["classifier"])
    ).to(torch.int32)
    return result


def flat_weight_list(weights):
    flat = []
    for name in WEIGHT_ORDER:
        flat.extend(int(value) for value in weights[name].reshape(-1).tolist())
    return flat


def write_mem(path, values, depth):
    with path.open("w", encoding="ascii", newline="\n") as output:
        output.writelines(f"{value & 0xFF:02x}\n" for value in values)
        output.writelines("00\n" for _ in range(depth - len(values)))


def write_mif(path, values, depth):
    with path.open("w", encoding="ascii", newline="\n") as output:
        output.write(f"DEPTH={depth};\nWIDTH=8;\nADDRESS_RADIX=DEC;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n")
        for address, value in enumerate(values):
            output.write(f"{address} : {value & 0xFF:02X};\n")
        if len(values) < depth:
            output.write(f"[{len(values)}..{depth - 1}] : 00;\n")
        output.write("END;\n")


def write_params_module(path, bias_codes, shifts):
    lines = [
        "module cnn_digit_params(",
        "    input wire [1:0] layer,",
        "    input wire [4:0] channel,",
        "    output reg signed [31:0] bias_value,",
        "    output wire [3:0] conv1_shift,",
        "    output wire [3:0] conv2_shift,",
        "    output wire [3:0] conv3_shift",
        ");",
        f"    assign conv1_shift = 4'd{shifts[0]};",
        f"    assign conv2_shift = 4'd{shifts[1]};",
        f"    assign conv3_shift = 4'd{shifts[2]};",
        "    always @* begin",
        "        case ({layer, channel})",
    ]
    layer_ids = (("conv1", 0), ("conv2", 1), ("conv3", 2), ("classifier", 3))
    for name, layer_id in layer_ids:
        for channel, value in enumerate(bias_codes[name].tolist()):
            key = (layer_id << 5) | channel
            lines.append(f"            7'd{key}: bias_value = 32'h{int(value) & 0xFFFFFFFF:08X};")
    lines.extend(
        [
            "            default: bias_value = 32'sd0;",
            "        endcase",
            "    end",
            "endmodule",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="ascii", newline="\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--checkpoint",
        type=Path,
        default=Path(__file__).parent / "checkpoints" / "digit_cnn_camera_adapt_20261026.pt",
    )
    parser.add_argument("--calibration-dirs", type=Path, nargs="*", default=[])
    parser.add_argument(
        "--data-root",
        type=Path,
        default=Path(__file__).parent / "data" / "mnist",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).parent / "exports" / "eg4d20_digit_int8_20261026",
    )
    parser.add_argument("--calibration-mnist-count", type=int, default=2048)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()
    if args.calibration_mnist_count <= 0 or args.batch_size <= 0:
        parser.error("calibration count and batch size must be positive")
    if args.output_dir.exists() and any(args.output_dir.iterdir()):
        parser.error(f"output directory is not empty: {args.output_dir}")
    args.output_dir.mkdir(parents=True, exist_ok=True)

    checkpoint, model = load_checkpoint(args.checkpoint)
    weights, scales = quantize_weights(model)
    calibration = calibration_images(args.data_root, args.calibration_dirs, args.calibration_mnist_count)
    shifts = calibrate_shifts(calibration, model, weights, scales, args.batch_size)
    bias_codes = make_bias_codes(model, scales, shifts)

    model_scores = []
    quant_scores = []
    device = torch.device("cuda" if args.device == "auto" and torch.cuda.is_available() else ("cpu" if args.device == "auto" else args.device))
    float_model = model.to(device)
    test_set = datasets.MNIST(
        args.data_root,
        train=False,
        download=False,
        transform=transforms.ToTensor(),
    )
    test_loader = torch.utils.data.DataLoader(test_set, batch_size=args.batch_size, shuffle=False, num_workers=0)
    mnist_correct = 0
    mnist_count = 0
    with torch.inference_mode():
        for images, labels in test_loader:
            model_scores.append(float_model(images.to(device)).cpu())
            q_scores = quantized_forward(images, model, weights, scales, shifts, bias_codes)
            quant_scores.append(q_scores)
            mnist_correct += (q_scores.argmax(1) == labels).sum().item()
            mnist_count += labels.size(0)
    quant_accuracy = mnist_correct / mnist_count
    float_scores = torch.cat(model_scores)
    q_scores = torch.cat(quant_scores)
    disagreement = float((float_scores.argmax(1) != q_scores.argmax(1)).float().mean().item())

    flat = flat_weight_list(weights)
    if len(flat) > WEIGHT_DEPTH:
        raise ValueError(f"weight count {len(flat)} exceeds ROM depth {WEIGHT_DEPTH}")
    write_mem(args.output_dir / "cnn_digit_weights.hex", flat, WEIGHT_DEPTH)
    write_mif(args.output_dir / "cnn_digit_weights.mif", flat, WEIGHT_DEPTH)
    write_params_module(args.output_dir / "cnn_digit_params.v", bias_codes, shifts)
    metadata = {
        "format": "eg4d20_digit_int8_v1",
        "architecture": "small_digit_cnn_28x28_v1",
        "input_size": INPUT_SIZE,
        "classes": list(CLASSES),
        "weight_count": len(flat),
        "weight_depth": WEIGHT_DEPTH,
        "weight_order": list(WEIGHT_ORDER),
        "weight_scales": scales,
        "activation_shifts": shifts,
        "mnist_test_accuracy": quant_accuracy,
        "float_quant_disagreement": disagreement,
        "base_checkpoint": str(args.checkpoint.resolve()),
        "base_camera_eval_accuracy": checkpoint.get("camera_eval_accuracy"),
        "base_mnist_test_accuracy": checkpoint.get("mnist_test_accuracy"),
    }
    (args.output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(
        f"quantized_mnist_test={quant_accuracy:.4f} float_quant_disagreement={disagreement:.4f} "
        f"weight_count={len(flat)} shifts={shifts} output={args.output_dir.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
