#!/usr/bin/env python3
"""Checks for selectable frame preprocessing modes."""

import unittest

from PIL import Image

from cnn.image_preprocess import prepare_image


class PrepareImageTest(unittest.TestCase):
    def setUp(self):
        self.image = Image.new("RGB", (640, 480), (20, 80, 160))

    def test_fit_and_stretch_return_selected_color_at_target_size(self):
        for transform in ("fit", "stretch"):
            with self.subTest(transform=transform):
                gray = prepare_image(self.image, color="gray", transform=transform)
                rgb = prepare_image(self.image, color="rgb", transform=transform)
                self.assertEqual(gray.size, (320, 180))
                self.assertEqual(gray.mode, "L")
                self.assertEqual(rgb.size, (320, 180))
                self.assertEqual(rgb.mode, "RGB")

    def test_none_keeps_source_dimensions(self):
        gray = prepare_image(self.image, color="gray", transform="none")
        rgb = prepare_image(self.image, color="rgb", transform="none")
        self.assertEqual(gray.size, (640, 480))
        self.assertEqual(gray.mode, "L")
        self.assertEqual(rgb.size, (640, 480))
        self.assertEqual(rgb.mode, "RGB")

    def test_nearest_preserves_binary_values(self):
        binary = Image.new("L", (1920, 1080), 0)
        binary.putpixel((960, 540), 255)
        resized = prepare_image(binary, color="gray", transform="stretch", resample="nearest")
        self.assertEqual(resized.size, (320, 180))
        self.assertTrue({value for _, value in resized.getcolors(256)}.issubset({0, 255}))


if __name__ == "__main__":
    unittest.main()
