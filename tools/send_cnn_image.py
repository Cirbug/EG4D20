#!/usr/bin/env python3
"""Preprocess and send one 320x180 grayscale image to the EG4D20 endpoint."""

import argparse
import secrets
import socket
import struct
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cnn.image_preprocess import (  # noqa: E402
    INPUT_HEIGHT,
    INPUT_WIDTH,
    prepare_grayscale_image,
)

IMAGE_WIDTH = INPUT_WIDTH
IMAGE_HEIGHT = INPUT_HEIGHT
IMAGE_BYTES = IMAGE_WIDTH * IMAGE_HEIGHT
CHUNK_BYTES = 1456
PACKET_COUNT = (IMAGE_BYTES + CHUNK_BYTES - 1) // CHUNK_BYTES
HEADER = struct.Struct("!4sBBHHH")
ACK = struct.Struct("!4sHHBB")
IMAGE_MAGIC = b"CNN1"
ACK_MAGIC = b"ACK1"


def payload_length(packet_index):
    if not 0 <= packet_index < PACKET_COUNT:
        raise ValueError("packet index is outside the frame")
    return min(CHUNK_BYTES, IMAGE_BYTES - packet_index * CHUNK_BYTES)


def build_datagram(frame_id, packet_index, payload):
    expected_length = payload_length(packet_index)
    if len(payload) != expected_length:
        raise ValueError(
            f"packet {packet_index} needs {expected_length} payload bytes, got {len(payload)}"
        )
    header = HEADER.pack(
        IMAGE_MAGIC, 1, 0, frame_id, packet_index, len(payload)
    )
    crc = zlib.crc32(header + payload) & 0xFFFFFFFF
    return header + payload + struct.pack("!I", crc)


def parse_ack(datagram):
    if len(datagram) != ACK.size:
        raise ValueError("ACK length must be 10 bytes")
    magic, frame_id, packet_index, status, reserved = ACK.unpack(datagram)
    if magic != ACK_MAGIC or reserved != 0 or status not in (0, 1, 2):
        raise ValueError("invalid ACK fields")
    return frame_id, packet_index, status


def load_grayscale_frame(path):
    path = Path(path)
    if path.suffix.lower() == ".raw":
        pixels = path.read_bytes()
    else:
        try:
            from PIL import Image
        except ImportError as exc:
            raise ValueError(
                "PNG/JPEG input requires Pillow; use a 57600-byte 320x180 .raw file otherwise"
            ) from exc
        with Image.open(path) as image:
            pixels = prepare_grayscale_image(image).tobytes()
    if len(pixels) != IMAGE_BYTES:
        raise ValueError(f"frame must contain exactly {IMAGE_BYTES} grayscale bytes, got {len(pixels)}")
    return pixels


def binarize_frame(pixels, mode="none"):
    if len(pixels) != IMAGE_BYTES:
        raise ValueError(f"frame must contain exactly {IMAGE_BYTES} grayscale bytes")
    if mode == "none":
        return pixels
    if mode != "adaptive":
        raise ValueError(f"unsupported binarization mode: {mode}")

    try:
        import cv2
        import numpy as np
    except ImportError as exc:
        raise ValueError("adaptive binarization requires OpenCV and NumPy") from exc

    frame = np.frombuffer(pixels, dtype=np.uint8).reshape(IMAGE_HEIGHT, IMAGE_WIDTH)
    smoothed = cv2.GaussianBlur(frame, (3, 3), 0)
    binary = cv2.adaptiveThreshold(
        smoothed,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        31,
        9,
    )
    return binary.tobytes()


def wait_for_ack(sock, board_ip, board_port, frame_id, packet_index, timeout):
    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise socket.timeout()
        sock.settimeout(remaining)
        datagram, source = sock.recvfrom(2048)
        if source != (board_ip, board_port):
            continue
        try:
            ack_frame, ack_index, status = parse_ack(datagram)
        except ValueError:
            continue
        if (ack_frame, ack_index) == (frame_id, packet_index):
            return status


def send_frame(
    sock,
    pixels,
    board_ip="192.168.50.2",
    board_port=6002,
    frame_id=0,
    timeout=1.0,
    retries=5,
    frame_restarts=2,
    on_ack=None,
):
    if len(pixels) != IMAGE_BYTES:
        raise ValueError(f"frame must contain exactly {IMAGE_BYTES} grayscale bytes")
    if not 0 <= frame_id <= 0xFFFF:
        raise ValueError("frame id must fit in 16 bits")
    if timeout <= 0 or retries < 0 or frame_restarts < 0:
        raise ValueError("timeout must be positive and retry counts cannot be negative")

    for frame_attempt in range(frame_restarts + 1):
        restart_frame = False
        for packet_index in range(PACKET_COUNT):
            start = packet_index * CHUNK_BYTES
            payload = pixels[start : start + payload_length(packet_index)]
            datagram = build_datagram(frame_id, packet_index, payload)
            for packet_attempt in range(retries + 1):
                sock.sendto(datagram, (board_ip, board_port))
                try:
                    status = wait_for_ack(
                        sock,
                        board_ip,
                        board_port,
                        frame_id,
                        packet_index,
                        timeout,
                    )
                    break
                except socket.timeout:
                    if packet_attempt == retries:
                        raise TimeoutError(
                            f"no ACK for frame {frame_id}, packet {packet_index} "
                            f"after {retries + 1} sends"
                        )
            if on_ack is not None:
                on_ack(frame_id, packet_index, status, frame_attempt)
            if status == 2:
                restart_frame = True
                break
            expected_status = 1 if packet_index == PACKET_COUNT - 1 else 0
            if status != expected_status:
                raise RuntimeError(
                    f"unexpected ACK status {status} for packet {packet_index}; "
                    f"expected {expected_status}"
                )
        if not restart_frame:
            return
        if frame_attempt == frame_restarts:
            raise RuntimeError(f"board rejected frame {frame_id} after {frame_attempt + 1} attempts")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "image",
        help="image file (center-cropped to 16:9 and resized to 320x180) or exactly 57600-byte .raw file",
    )
    parser.add_argument("--board-ip", default="192.168.50.2")
    parser.add_argument("--board-port", type=int, default=6002)
    parser.add_argument("--local-ip", default="192.168.50.1")
    parser.add_argument("--local-port", type=int, default=6001)
    parser.add_argument(
        "--binarize",
        choices=("none", "adaptive"),
        default="none",
        help="threshold locally before sending; adaptive keeps dark ink black on a light background",
    )
    parser.add_argument("--frame-id", type=lambda value: int(value, 0))
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--retries", type=int, default=5)
    parser.add_argument("--frame-restarts", type=int, default=2)
    args = parser.parse_args()

    try:
        pixels = binarize_frame(load_grayscale_frame(args.image), args.binarize)
        frame_id = secrets.randbits(16) if args.frame_id is None else args.frame_id

        def report_ack(ack_frame, packet_index, status, frame_attempt):
            if status == 2:
                print(f"REJECT frame={ack_frame} packet={packet_index}; restarting frame")
            elif packet_index % 5 == 0 or packet_index == PACKET_COUNT - 1:
                print(
                    f"ACK frame={ack_frame} packet={packet_index + 1}/{PACKET_COUNT} "
                    f"status={status}"
                )

        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.bind((args.local_ip, args.local_port))
            send_frame(
                sock,
                pixels,
                board_ip=args.board_ip,
                board_port=args.board_port,
                frame_id=frame_id,
                timeout=args.timeout,
                retries=args.retries,
                frame_restarts=args.frame_restarts,
                on_ack=report_ack,
            )
        print(
            f"FRAME VERIFIED frame={frame_id} bytes={IMAGE_BYTES} binarize={args.binarize}; "
            "UART should report detection results and DDR OK"
        )
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
