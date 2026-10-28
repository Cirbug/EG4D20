#!/usr/bin/env python3
"""Unit tests for the EG4D20 CNN UDP image sender."""

from pathlib import Path
import socket
import struct
import sys
import tempfile
import unittest
import zlib
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import send_cnn_image as sender


class FakeSocket:
    def __init__(self, drop_first_ack=False, reject_index_once=None):
        self.drop_first_ack = drop_first_ack
        self.reject_index_once = reject_index_once
        self.first_ack_dropped = False
        self.rejection_sent = False
        self.sent = []
        self.pending = []

    def settimeout(self, _timeout):
        pass

    def sendto(self, datagram, destination):
        self.sent.append((datagram, destination))
        magic, version, flags, frame_id, packet_index, payload_len = sender.HEADER.unpack_from(datagram)
        self.assert_packet(datagram, magic, version, flags, payload_len)
        if self.drop_first_ack and packet_index == 0 and not self.first_ack_dropped:
            self.first_ack_dropped = True
            return len(datagram)

        status = 1 if packet_index == sender.PACKET_COUNT - 1 else 0
        if self.reject_index_once == packet_index and not self.rejection_sent:
            status = 2
            self.rejection_sent = True
        ack = sender.ACK.pack(sender.ACK_MAGIC, frame_id, packet_index, status, 0)
        self.pending.append((ack, ("192.168.50.2", 6002)))
        return len(datagram)

    def recvfrom(self, _size):
        if not self.pending:
            raise socket.timeout()
        return self.pending.pop(0)

    @staticmethod
    def assert_packet(datagram, magic, version, flags, payload_len):
        if magic != sender.IMAGE_MAGIC or version != 1 or flags != 0:
            raise AssertionError("bad CNN header")
        if len(datagram) != sender.HEADER.size + payload_len + 4:
            raise AssertionError("bad CNN datagram length")


class CnnUdpSenderTests(unittest.TestCase):
    def test_packet_header_payload_and_crc(self):
        payload = bytes((index & 0xFF) for index in range(sender.CHUNK_BYTES))
        datagram = sender.build_datagram(0x1234, 0, payload)
        header = datagram[: sender.HEADER.size]
        self.assertEqual(
            sender.HEADER.unpack(header),
            (b"CNN1", 1, 0, 0x1234, 0, sender.CHUNK_BYTES),
        )
        self.assertEqual(datagram[sender.HEADER.size : -4], payload)
        self.assertEqual(
            struct.unpack("!I", datagram[-4:])[0], zlib.crc32(header + payload) & 0xFFFFFFFF
        )
        self.assertEqual(sender.IMAGE_BYTES, 57600)
        self.assertEqual(sender.PACKET_COUNT, 40)
        self.assertEqual(sender.payload_length(sender.PACKET_COUNT - 1), 816)

    def test_1920x1080_is_scaled_to_16_9_without_crop_or_padding(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frame.png"
            Image.new("L", (1920, 1080), 117).save(path)

            pixels = sender.load_grayscale_frame(path)

        self.assertEqual(len(pixels), 320 * 180)
        self.assertEqual(set(pixels), {117})

    def test_other_aspect_ratios_are_center_cropped_without_bars(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frame.png"
            image = Image.new("L", (640, 480), 255)
            draw = ImageDraw.Draw(image)
            draw.rectangle((0, 0, 639, 59), fill=0)
            draw.rectangle((0, 420, 639, 479), fill=0)
            image.save(path)

            pixels = sender.load_grayscale_frame(path)

        self.assertEqual(len(pixels), 320 * 180)
        self.assertGreater(min(pixels), 200)
        self.assertEqual(max(pixels), 255)

    def test_adaptive_binarization_keeps_black_ink_on_white_background(self):
        image = Image.new("L", (320, 180), 170)
        draw = ImageDraw.Draw(image)
        draw.line((120, 50, 120, 130), fill=25, width=5)
        pixels = sender.binarize_frame(image.tobytes(), "adaptive")

        self.assertEqual(len(pixels), sender.IMAGE_BYTES)
        self.assertEqual(set(pixels), {0, 255})
        self.assertEqual(pixels[90 * 320 + 120], 0)
        self.assertEqual(pixels[90 * 320 + 20], 255)
        self.assertIs(sender.binarize_frame(pixels, "none"), pixels)

    def test_ack_validation(self):
        datagram = sender.ACK.pack(b"ACK1", 7, 11, 1, 0)
        self.assertEqual(sender.parse_ack(datagram), (7, 11, 1))
        with self.assertRaises(ValueError):
            sender.parse_ack(datagram[:-1])
        with self.assertRaises(ValueError):
            sender.parse_ack(sender.ACK.pack(b"ACK1", 7, 11, 1, 1))

    def test_sender_waits_for_each_ack_and_retries_lost_ack(self):
        pixels = bytes((index * 17) & 0xFF for index in range(sender.IMAGE_BYTES))
        sock = FakeSocket(drop_first_ack=True)
        sender.send_frame(sock, pixels, frame_id=0x3344, timeout=0.01, retries=1)
        packet_indices = [sender.HEADER.unpack_from(data)[4] for data, _ in sock.sent]
        self.assertEqual(packet_indices[:3], [0, 0, 1])
        self.assertEqual(packet_indices[2:], list(range(1, sender.PACKET_COUNT)))
        self.assertTrue(all(dest == ("192.168.50.2", 6002) for _, dest in sock.sent))

    def test_rejected_packet_restarts_the_frame(self):
        pixels = bytes(sender.IMAGE_BYTES)
        sock = FakeSocket(reject_index_once=3)
        sender.send_frame(sock, pixels, frame_id=0x55AA, timeout=0.01, retries=0, frame_restarts=1)
        packet_indices = [sender.HEADER.unpack_from(data)[4] for data, _ in sock.sent]
        self.assertEqual(packet_indices[:5], [0, 1, 2, 3, 0])
        self.assertEqual(packet_indices[4:], list(range(sender.PACKET_COUNT)))


if __name__ == "__main__":
    unittest.main()
