#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from cnn.crop_annotated_digits import crop_box


class CropAnnotatedDigitsTest(unittest.TestCase):
    def test_crop_box_clamps_margin(self):
        image = Image.new("L", (20, 10), 255)
        crop = crop_box(image, {"xmin": 1, "ymin": 2, "xmax": 4, "ymax": 5}, 8)
        self.assertEqual(crop.size, (12, 10))


if __name__ == "__main__":
    unittest.main()
