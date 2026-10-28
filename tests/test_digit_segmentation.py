#!/usr/bin/env python3
"""Regression check for the supplied OBS handwritten-digit reference frame."""

from pathlib import Path
import sys
import unittest

PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import cv2
import numpy as np
from PIL import Image

from cnn.segment_digits import segment_digits


REFERENCE_FRAME = PROJECT_ROOT / "xuniji" / "ph1p35_obs_frame_320x180_gray.png"


class DigitSegmentationTest(unittest.TestCase):
    def test_reference_frame_has_two_ordered_rows_of_digits(self):
        with Image.open(REFERENCE_FRAME) as source:
            gray = np.asarray(source.convert("L"), dtype=np.uint8)
        _, blobs, crops = segment_digits(gray)

        self.assertEqual(len(blobs), 10)
        self.assertEqual(len(crops), 10)
        self.assertEqual([blob.row for blob in blobs], [0] * 6 + [1] * 4)
        self.assertEqual([blob.column for blob in blobs], [0, 1, 2, 3, 4, 5, 0, 1, 2, 3])
        self.assertTrue(all(crop.shape == (28, 28) for crop in crops))
        self.assertTrue(all(int(crop.max()) > 0 for crop in crops))

    def test_color_input_masks_green_overlay(self):
        rgb = np.full((120, 220, 3), 190, dtype=np.uint8)
        cv2.line(rgb, (35, 20), (35, 100), (10, 10, 10), 7)
        cv2.rectangle(rgb, (120, 20), (190, 100), (0, 255, 80), 3)
        gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)

        _, blobs, crops = segment_digits(
            gray,
            min_height=20,
            min_area=40,
            adaptive_c=5,
            roi=(0, 0, 220, 120),
            color_rgb=rgb,
            close_kernel=7,
        )

        self.assertEqual(len(blobs), 1)
        self.assertLess(blobs[0].x, 60)
        self.assertEqual(len(crops), 1)


if __name__ == "__main__":
    unittest.main()
