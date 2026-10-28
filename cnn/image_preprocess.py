"""Shared image preprocessing for PC training and FPGA input."""

from PIL import Image, ImageOps


INPUT_WIDTH = 320
INPUT_HEIGHT = 180


def prepare_image(
    image: Image.Image,
    color: str = "gray",
    transform: str = "fit",
    resample: str = "bilinear",
) -> Image.Image:
    """Normalize orientation, color mode, and optional 320x180 geometry."""
    if color not in {"gray", "rgb"}:
        raise ValueError("color must be gray or rgb")
    if transform not in {"fit", "stretch", "none"}:
        raise ValueError("transform must be fit, stretch, or none")
    if resample not in {"nearest", "bilinear"}:
        raise ValueError("resample must be nearest or bilinear")

    image = ImageOps.exif_transpose(image).convert("L" if color == "gray" else "RGB")
    method = Image.Resampling.NEAREST if resample == "nearest" else Image.Resampling.BILINEAR
    if transform == "fit":
        return ImageOps.fit(
            image,
            (INPUT_WIDTH, INPUT_HEIGHT),
            method=method,
            centering=(0.5, 0.5),
        )
    if transform == "stretch":
        return image.resize((INPUT_WIDTH, INPUT_HEIGHT), method)
    return image


def prepare_grayscale_image(image: Image.Image) -> Image.Image:
    """Backward-compatible 320x180 grayscale preprocessing."""
    return prepare_image(image, color="gray", transform="fit")
