#!/usr/bin/env python3
"""Train the EG4D20 320x180 grayscale binary CNN from class folders."""

import argparse
from pathlib import Path
import random

from PIL import Image
import torch
from torch import nn
from torch.utils.data import DataLoader, Dataset

if __package__:
    from .image_preprocess import prepare_grayscale_image
    from .model import CLASS_COUNT, INPUT_HEIGHT, INPUT_WIDTH, SmallBinaryCNN
else:
    from image_preprocess import prepare_grayscale_image
    from model import CLASS_COUNT, INPUT_HEIGHT, INPUT_WIDTH, SmallBinaryCNN


IMAGE_SUFFIXES = {".bmp", ".jpeg", ".jpg", ".png"}


class GrayImageFolder(Dataset):
    def __init__(self, root: Path, class_names=None) -> None:
        self.root = root
        if not root.is_dir():
            raise ValueError(f"dataset directory does not exist: {root}")

        discovered = sorted(path.name for path in root.iterdir() if path.is_dir())
        self.classes = discovered if class_names is None else list(class_names)
        if discovered != self.classes:
            raise ValueError(
                f"class directories in {root} are {discovered}, expected {self.classes}"
            )
        self.class_to_index = {name: index for index, name in enumerate(self.classes)}
        self.samples = []
        for class_name, label in self.class_to_index.items():
            class_root = root / class_name
            sample_start = len(self.samples)
            for path in sorted(class_root.rglob("*")):
                if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES:
                    self.samples.append((path, label))
            if len(self.samples) == sample_start:
                raise ValueError(f"no images found for class {class_name!r} under {root}")
        if not self.samples:
            raise ValueError(f"no JPG, PNG, or BMP images found under {root}")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        path, label = self.samples[index]
        with Image.open(path) as image:
            image = prepare_grayscale_image(image)
            pixels = torch.frombuffer(bytearray(image.tobytes()), dtype=torch.uint8)
        image_tensor = pixels.view(1, INPUT_HEIGHT, INPUT_WIDTH)
        image_tensor = image_tensor.to(dtype=torch.float32).div_(255.0)
        return image_tensor, label


def run_epoch(model, loader, criterion, device, optimizer=None):
    training = optimizer is not None
    model.train(training)
    total_loss = 0.0
    correct = 0
    sample_count = 0

    for images, labels in loader:
        images = images.to(device)
        labels = labels.to(device)
        if training:
            optimizer.zero_grad(set_to_none=True)

        with torch.set_grad_enabled(training):
            logits = model(images)
            loss = criterion(logits, labels)
            if training:
                loss.backward()
                optimizer.step()

        batch_size = labels.size(0)
        total_loss += loss.item() * batch_size
        correct += (logits.argmax(dim=1) == labels).sum().item()
        sample_count += batch_size

    if sample_count == 0:
        raise ValueError("dataset has no samples")
    return total_loss / sample_count, correct / sample_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", type=Path, default=Path(__file__).parent / "data")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parent / "checkpoints" / "binary_cnn_fp32.pt",
    )
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--seed", type=int, default=20261026)
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()

    if args.epochs <= 0 or args.batch_size <= 0 or args.learning_rate <= 0:
        parser.error("epochs, batch-size, and learning-rate must be positive")

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    if args.device == "auto":
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        device = torch.device(args.device)

    train_set = GrayImageFolder(args.data_root / "train")
    if len(train_set.classes) != CLASS_COUNT:
        raise ValueError(
            f"expected {CLASS_COUNT} class folders, found {train_set.classes}"
        )
    val_set = GrayImageFolder(args.data_root / "val", train_set.classes)
    train_loader = DataLoader(
        train_set, batch_size=args.batch_size, shuffle=True, num_workers=0
    )
    val_loader = DataLoader(
        val_set, batch_size=args.batch_size, shuffle=False, num_workers=0
    )

    model = SmallBinaryCNN().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate)
    best_key = (-1.0, float("inf"))
    args.output.parent.mkdir(parents=True, exist_ok=True)

    print(
        f"classes={train_set.classes} train={len(train_set)} val={len(val_set)} "
        f"device={device} input={INPUT_WIDTH}x{INPUT_HEIGHT} grayscale"
    )
    for epoch in range(1, args.epochs + 1):
        train_loss, train_accuracy = run_epoch(
            model, train_loader, criterion, device, optimizer
        )
        val_loss, val_accuracy = run_epoch(model, val_loader, criterion, device)
        print(
            f"epoch={epoch:03d}/{args.epochs:03d} "
            f"train_loss={train_loss:.5f} train_acc={train_accuracy:.4f} "
            f"val_loss={val_loss:.5f} val_acc={val_accuracy:.4f}"
        )

        key = (val_accuracy, -val_loss)
        if key > best_key:
            best_key = key
            torch.save(
                {
                    "format_version": 1,
                    "architecture": "small_binary_cnn_320x180_v2",
                    "input_width": INPUT_WIDTH,
                    "input_height": INPUT_HEIGHT,
                    "input_channels": 1,
                    "classes": train_set.classes,
                    "validation_accuracy": val_accuracy,
                    "model_state": {
                        name: tensor.detach().cpu().clone()
                        for name, tensor in model.state_dict().items()
                    },
                },
                args.output,
            )
            print(f"saved_best={args.output}")

    print(f"best_val_accuracy={best_key[0]:.4f} checkpoint={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
