#!/usr/bin/env python3
"""Train the 28x28 EG4D20 handwritten digit CNN on MNIST."""

import argparse
from pathlib import Path
import random

import torch
from torch import nn
from torch.utils.data import DataLoader
from torchvision import datasets, transforms

if __package__:
    from .digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN
else:
    from digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN


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
    return total_loss / sample_count, correct / sample_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-root", type=Path, default=Path(__file__).parent / "data" / "mnist")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).parent / "checkpoints" / "digit_cnn_mnist.pt",
    )
    parser.add_argument("--epochs", type=int, default=5)
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--learning-rate", type=float, default=1e-3)
    parser.add_argument("--seed", type=int, default=20261026)
    parser.add_argument("--device", default="auto")
    parser.add_argument(
        "--mnist-mirror",
        default="https://storage.googleapis.com/cvdf-datasets/mnist",
        help="base URL for the four MNIST gzip files (original torchvision MD5 checks remain enabled)",
    )
    args = parser.parse_args()
    if args.epochs <= 0 or args.batch_size <= 0 or args.learning_rate <= 0:
        parser.error("epochs, batch-size, and learning-rate must be positive")

    random.seed(args.seed)
    torch.manual_seed(args.seed)
    if args.device == "auto":
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    else:
        device = torch.device(args.device)
    if device.type == "cuda":
        torch.cuda.manual_seed_all(args.seed)
        gpu_name = torch.cuda.get_device_name(device)
    else:
        gpu_name = "none"

    transform = transforms.ToTensor()
    datasets.MNIST.mirrors = [args.mnist_mirror.rstrip("/") + "/"]
    train_set = datasets.MNIST(args.data_root, train=True, download=True, transform=transform)
    test_set = datasets.MNIST(args.data_root, train=False, download=True, transform=transform)
    train_loader = DataLoader(train_set, batch_size=args.batch_size, shuffle=True, num_workers=0)
    test_loader = DataLoader(test_set, batch_size=args.batch_size, shuffle=False, num_workers=0)

    model = SmallDigitCNN().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate)
    best_accuracy = -1.0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(
        f"dataset=MNIST train={len(train_set)} test={len(test_set)} "
        f"classes={','.join(CLASSES)} input={INPUT_SIZE}x{INPUT_SIZE} "
        f"device={device} torch={torch.__version__} cuda_runtime={torch.version.cuda} gpu={gpu_name}"
    )
    for epoch in range(1, args.epochs + 1):
        train_loss, train_accuracy = run_epoch(
            model, train_loader, criterion, device, optimizer
        )
        test_loss, test_accuracy = run_epoch(model, test_loader, criterion, device)
        print(
            f"epoch={epoch:02d}/{args.epochs:02d} train_loss={train_loss:.5f} "
            f"train_acc={train_accuracy:.4f} mnist_test_loss={test_loss:.5f} "
            f"mnist_test_acc={test_accuracy:.4f}"
        )
        if test_accuracy > best_accuracy:
            best_accuracy = test_accuracy
            torch.save(
                {
                    "format_version": 1,
                    "architecture": "small_digit_cnn_28x28_v1",
                    "input_size": INPUT_SIZE,
                    "input_channels": 1,
                    "classes": list(CLASSES),
                    "mnist_test_accuracy": test_accuracy,
                    "model_state": {
                        name: tensor.detach().cpu().clone()
                        for name, tensor in model.state_dict().items()
                    },
                },
                args.output,
            )
            print(f"saved_best={args.output}")
    print(f"best_mnist_test_accuracy={best_accuracy:.4f} checkpoint={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
