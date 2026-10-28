#!/usr/bin/env python3
"""Run focused Icarus tests for the CNN image input path."""

from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "uisrc" / "01_rtl"
FIFO = ROOT / "uisrc" / "03_ip" / "al_softfifo" / "udp_pkg_buf.v"

CASES = (
    ("tb_cnn_udp_image_rx", (RTL / "cnn_udp_image_rx.v",)),
    ("tb_cnn_ddr_frame_writer", (RTL / "cnn_ddr_frame_writer.v", FIFO)),
    ("tb_cnn_ddr_frame_crc_check", (RTL / "cnn_ddr_frame_crc_check.v",)),
)


def run_case(top: str, sources: tuple[Path, ...], output_dir: Path) -> None:
    binary = output_dir / f"{top}.vvp"
    testbench = ROOT / "tests" / f"{top}.sv"
    compile_cmd = [
        "iverilog",
        "-g2012",
        "-s",
        top,
        "-o",
        str(binary),
        str(testbench),
        *(str(source) for source in sources),
    ]
    subprocess.run(compile_cmd, cwd=ROOT, check=True)
    result = subprocess.run(
        ["vvp", str(binary)], cwd=ROOT, check=True, text=True, capture_output=True
    )
    print(result.stdout, end="")


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="eg4d20_cnn_rtl_") as temp_dir:
        output_dir = Path(temp_dir)
        for top, sources in CASES:
            run_case(top, sources, output_dir)


if __name__ == "__main__":
    main()
