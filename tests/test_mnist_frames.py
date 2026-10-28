#!/usr/bin/env python3
import unittest

from PIL import Image

from cnn.make_mnist_frames import downsample_block_average


class MnistFramePreprocessTest(unittest.TestCase):
    def test_downsample_uses_block_average(self):
        source = Image.new("L", (12, 6), 0)
        for y in range(6):
            for x in range(6, 12):
                source.putpixel((x, y), 255)
        result = downsample_block_average(source)
        self.assertEqual(result.size, (2, 1))
        self.assertEqual(list(result.getdata()), [0, 255])

    def test_downsample_keeps_partial_block_coverage_as_gray(self):
        source = Image.new("L", (6, 6), 0)
        for y in range(6):
            for x in range(3):
                source.putpixel((x, y), 255)
        result = downsample_block_average(source)
        self.assertEqual(result.getpixel((0, 0)), 128)


if __name__ == "__main__":
    unittest.main()
