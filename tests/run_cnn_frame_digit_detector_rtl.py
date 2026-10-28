#!/usr/bin/env python3
"""Run the full-frame detector RTL on the labeled 320x180 grayscale BMP."""

from pathlib import Path
import argparse
import struct
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / "cnn" / "outputs" / "verify_frames_osd_light" / "Screenshot_13-27-15.bmp"


def load_gray_bmp(path: Path) -> bytes:
    data = path.read_bytes()
    if data[:2] != b"BM":
        raise ValueError(f"not a BMP file: {path}")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    dib_size = struct.unpack_from("<I", data, 14)[0]
    if dib_size < 40:
        raise ValueError("unsupported BMP header")
    width, signed_height = struct.unpack_from("<ii", data, 18)
    planes, bits_per_pixel = struct.unpack_from("<HH", data, 26)
    compression = struct.unpack_from("<I", data, 30)[0]
    if (width, abs(signed_height), planes, bits_per_pixel, compression) not in (
        (320, 180, 1, 8, 0),
        (320, 180, 1, 24, 0),
        (320, 180, 1, 32, 0),
    ):
        raise ValueError("expected an uncompressed 320x180 8-bit or RGB BMP")

    palette = []
    if bits_per_pixel == 8:
        colors_used = struct.unpack_from("<I", data, 46)[0]
        palette_count = colors_used or 256
        palette_offset = 14 + dib_size
        for index in range(palette_count):
            blue, green, red, _reserved = struct.unpack_from("<BBBB", data, palette_offset + index * 4)
            palette.append((red + green + blue) // 3)

    bytes_per_pixel = bits_per_pixel // 8
    row_stride = (width * bytes_per_pixel + 3) & ~3
    pixels = bytearray(width * 180)
    for file_row in range(180):
        y = file_row if signed_height < 0 else 179 - file_row
        row_offset = pixel_offset + file_row * row_stride
        for x in range(width):
            if bits_per_pixel == 8:
                pixels[y * width + x] = palette[data[row_offset + x]]
            else:
                offset = row_offset + x * bytes_per_pixel
                blue, green, red = data[offset : offset + 3]
                pixels[y * width + x] = (299 * red + 587 * green + 114 * blue + 500) // 1000
    return bytes(pixels)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", nargs="?", type=Path, default=SAMPLE)
    parser.add_argument(
        "--clear-top-rows",
        type=int,
        default=None,
        help="set a captured status-bar strip to white before simulation",
    )
    parser.add_argument(
        "--real-cnn",
        action="store_true",
        help="simulate one candidate through the real quantized CNN RTL",
    )
    parser.add_argument(
        "--all-digits",
        action="store_true",
        help="with --real-cnn, classify all ten annotated digits in the frame",
    )
    parser.add_argument(
        "--binarize",
        choices=("none", "adaptive"),
        default="none",
        help="apply the sender's preprocessing before simulation",
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="report every detection without checking against this testbench's fixed labels",
    )
    parser.add_argument(
        "--banked-mask",
        action="store_true",
        help="model the FPGA's 32K plus four 9K mask RAM banks",
    )
    parser.add_argument(
        "--max-detections",
        type=int,
        default=16,
        help="candidate capacity for the simulation, from 1 to 16",
    )
    parser.add_argument(
        "--dump-first-patch",
        type=Path,
        help="write the first candidate's 28x28 CNN input to this hex file",
    )
    args = parser.parse_args()
    if args.all_digits and not args.real_cnn:
        parser.error("--all-digits requires --real-cnn")
    if not 1 <= args.max_detections <= 16:
        parser.error("--max-detections must be between 1 and 16")
    image_path = args.image
    pixels = bytearray(load_gray_bmp(image_path))
    if args.binarize != "none":
        sys.path.insert(0, str(ROOT / "tools"))
        from send_cnn_image import binarize_frame

        pixels = bytearray(binarize_frame(bytes(pixels), args.binarize))
    clear_top_rows = args.clear_top_rows
    if clear_top_rows is None:
        clear_top_rows = 19 if image_path.resolve() == SAMPLE.resolve() else 0
    if not 0 <= clear_top_rows <= 180:
        parser.error("--clear-top-rows must be between 0 and 180")
    for y in range(clear_top_rows):
        pixels[y * 320 : (y + 1) * 320] = b"\xff" * 320
    rtl = ROOT / "uisrc" / "01_rtl"
    with tempfile.TemporaryDirectory(prefix="eg4d20_frame_detector_") as temporary:
        temp = Path(temporary)
        stimulus = temp / "frame.hex"
        binary = temp / "tb_cnn_frame_digit_detector.vvp"
        with stimulus.open("w", encoding="ascii", newline="\n") as output:
            output.writelines(f"{pixel:02x}\n" for pixel in pixels)

        sim_define = "-DSIM_BRAM_MODEL" if args.banked_mask else "-DCNN_SIM"
        compile_command = [
                "iverilog", "-g2012", sim_define, "-s", "tb_cnn_frame_digit_detector",
                "-P", f"tb_cnn_frame_digit_detector.MAX_DETECTIONS={args.max_detections}",
                "-o", str(binary),
                str(ROOT / "tests" / "tb_cnn_frame_digit_detector.sv"),
                str(rtl / "cnn_frame_digit_detector.v"),
            ]
        if args.real_cnn:
            defines = ["-DREAL_CNN"]
            if args.all_digits:
                defines.append("-DREAL_CNN_ALL")
            if args.report_only:
                defines.append("-DREPORT_ONLY")
            compile_command[3:3] = defines
            compile_command.extend(
                [
                    str(rtl / "cnn_digit_infer.v"),
                    str(ROOT / "cnn" / "exports" / "eg4d20_digit_int8_20261026_v2" / "cnn_digit_params.v"),
                ]
            )
        elif args.report_only:
            compile_command[3:3] = ["-DREPORT_ONLY"]
        subprocess.run(compile_command, cwd=ROOT, check=True)
        simulation_args = ["vvp", str(binary), f"+IMAGE={stimulus}"]
        if args.dump_first_patch is not None:
            simulation_args.append(f"+DUMP_PATCH={args.dump_first_patch.resolve()}")
        result = subprocess.run(
            simulation_args,
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        print(
            f"source={image_path} clear_top_rows={clear_top_rows} "
            f"binarize={args.binarize} real_cnn={int(args.real_cnn)}"
        )
        print(result.stdout, end="")
        if result.returncode or "FATAL:" in result.stdout or "ERROR:" in result.stdout:
            print(result.stderr, file=sys.stderr, end="")
            return result.returncode or 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
