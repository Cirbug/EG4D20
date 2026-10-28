#!/usr/bin/env python3
"""Fine-tune the digit CNN on labeled camera crops from segmented frames."""

import argparse
import json
from pathlib import Path
import random

import torch
from PIL import Image
from torch import nn
from torch.utils.data import DataLoader, Dataset
from torchvision import datasets, transforms

if __package__:
    from .digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN
else:
    from digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN


class CameraDigitDataset(Dataset):
    def __init__(self, directories, augment=False):
        self.samples = []
        self.sources = set()
        self.transform = transforms.Compose(
            [
                transforms.RandomAffine(
                    degrees=7,
                    translate=(0.06, 0.06),
                    scale=(0.90, 1.10),
                    fill=0,
                ),
                transforms.ColorJitter(brightness=0.15, contrast=0.15),
                transforms.ToTensor(),
            ]
            if augment
            else [transforms.ToTensor()]
        )

        for directory in directories:
            manifest_path = directory / "manifest.json"
            if not manifest_path.is_file():
                raise FileNotFoundError(f"missing segmentation manifest: {manifest_path}")
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest.get("count") != 10:
                raise ValueError(f"expected 10 crops in {directory}, found {manifest.get('count')}")
            source = str(Path(manifest["source"]).resolve()).casefold()
            self.sources.add(source)
            digit_dir = directory / "digits"
            for label in range(10):
                crop = digit_dir / f"digit_{label:02d}.png"
                if not crop.is_file():
                    raise FileNotFoundError(f"missing labeled crop: {crop}")
                self.samples.append((crop, label))

        if not self.samples:
            raise ValueError("at least one segmented frame directory is required")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, index):
        path, label = self.samples[index]
        with Image.open(path) as image:
            tensor = self.transform(image.convert("L"))
        return tensor, label


def evaluate(model, loader, criterion, device):
    model.eval()
    loss_sum = 0.0
    correct = 0
    count = 0
    with torch.inference_mode():
        for images, labels in loader:
            images = images.to(device)
            labels = labels.to(device)
            logits = model(images)
            loss_sum += criterion(logits, labels).item() * labels.size(0)
            correct += (logits.argmax(dim=1) == labels).sum().item()
            count += labels.size(0)
    return loss_sum / count, correct / count, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train-dirs", type=Path, nargs="+", required=True)
    parser.add_argument("--eval-dirs", type=Path, nargs="+", required=True)
    parser.add_argument(
        "--base-checkpoint",
        type=Path,
        default=Path(__file__).parent / "checkpoints" / "digit_cnn_mnist_cuda.pt",
    )
    parser.add_argument(
        "--mnist-data-root",
        type=Path,
        default=Path(__file__).parent / "data" / "mnist",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parent / "checkpoints" / "digit_cnn_camera_adapt.pt",
    )
    parser.add_argument("--epochs", type=int, default=8)
    parser.add_argument("--batch-size", type=int, default=20)
    parser.add_argument("--learning-rate", type=float, default=5e-5)
    parser.add_argument("--seed", type=int, default=20261026)
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()
    if args.epochs <= 0 or args.batch_size <= 0 or args.learning_rate <= 0:
        parser.error("epochs, batch-size, and learning-rate must be positive")
    if args.output.exists():
        parser.error(f"output already exists: {args.output}; choose a new --output path")

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    if args.device == "auto":
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        device = torch.device(args.device)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(args.seed)

    train_set = CameraDigitDataset(args.train_dirs, augment=True)
    eval_set = CameraDigitDataset(args.eval_dirs)
    overlap = train_set.sources & eval_set.sources
    if overlap:
        parser.error("training and evaluation directories contain the same source image")
    train_loader = DataLoader(
        train_set,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=0,
    )
    eval_loader = DataLoader(eval_set, batch_size=args.batch_size, shuffle=False, num_workers=0)

    mnist_test = datasets.MNIST(
        args.mnist_data_root,
        train=False,
        download=False,
        transform=transforms.ToTensor(),
    )
    mnist_loader = DataLoader(mnist_test, batch_size=256, shuffle=False, num_workers=0)
    checkpoint = torch.load(args.base_checkpoint, map_location="cpu", weights_only=True)
    if checkpoint.get("architecture") != "small_digit_cnn_28x28_v1":
        raise ValueError("base checkpoint architecture is not small_digit_cnn_28x28_v1")
    if checkpoint.get("input_size") != INPUT_SIZE or tuple(checkpoint.get("classes", ())) != CLASSES:
        raise ValueError("base checkpoint input size or class order does not match this model")

    model = SmallDigitCNN().to(device)
    model.load_state_dict(checkpoint["model_state"])
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=1e-4)
    _, camera_before, eval_count = evaluate(model, eval_loader, criterion, device)
    _, mnist_before, mnist_count = evaluate(model, mnist_loader, criterion, device)
    print(
        f"device={device} train_crops={len(train_set)} eval_crops={eval_count} "
        f"base_camera_eval={camera_before:.4f} base_mnist_test={mnist_before:.4f} "
        f"base_checkpoint={args.base_checkpoint}"
    )

    for epoch in range(1, args.epochs + 1):
        model.train()
        train_loss = 0.0
        train_correct = 0
        train_count = 0
        for images, labels in train_loader:
            images = images.to(device)
            labels = labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(images)
            loss = criterion(logits, labels)
            loss.backward()
            optimizer.step()
            batch_count = labels.size(0)
            train_loss += loss.item() * batch_count
            train_correct += (logits.argmax(dim=1) == labels).sum().item()
            train_count += batch_count

        _, camera_accuracy, _ = evaluate(model, eval_loader, criterion, device)
        _, mnist_accuracy, _ = evaluate(model, mnist_loader, criterion, device)
        print(
            f"epoch={epoch:02d}/{args.epochs:02d} "
            f"train_loss={train_loss / train_count:.5f} "
            f"train_acc={train_correct / train_count:.4f} "
            f"camera_eval_acc={camera_accuracy:.4f} "
            f"mnist_test_acc={mnist_accuracy:.4f}"
        )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    torch.save(
        {
            "format_version": 1,
            "architecture": "small_digit_cnn_28x28_v1",
            "input_size": INPUT_SIZE,
            "input_channels": 1,
            "classes": list(CLASSES),
            "mnist_test_accuracy": mnist_accuracy,
            "camera_eval_accuracy": camera_accuracy,
            "camera_train_samples": len(train_set),
            "camera_eval_samples": eval_count,
            "base_checkpoint": str(args.base_checkpoint.resolve()),
            "model_state": {
                name: tensor.detach().cpu().clone()
                for name, tensor in model.state_dict().items()
            },
        },
        args.output,
    )
    print(
        f"saved={args.output.resolve()} camera_eval={camera_accuracy:.4f} "
        f"mnist_test={mnist_accuracy:.4f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
