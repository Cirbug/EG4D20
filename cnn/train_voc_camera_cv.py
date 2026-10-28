#!/usr/bin/env python3
"""Prepare RTL-equivalent digit patches and run grouped camera cross-validation."""

import argparse
import json
import random
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFont
from torch import nn
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler
from torchvision import transforms

from digit_model import CLASSES, INPUT_SIZE, SmallDigitCNN


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASE = ROOT / "cnn" / "checkpoints" / "digit_cnn_camera_adapt_20261026.pt"


def read_annotations(xml_path):
    root = ET.parse(xml_path).getroot()
    size = root.find("size")
    if size is None:
        raise ValueError(f"missing image size in {xml_path}")
    width, height = int(size.findtext("width")), int(size.findtext("height"))
    boxes = []
    for index, obj in enumerate(root.findall("object")):
        label = obj.findtext("name", "").strip()
        if label not in CLASSES:
            raise ValueError(f"unknown label {label!r} in {xml_path}")
        node = obj.find("bndbox")
        if node is None:
            raise ValueError(f"missing bndbox in {xml_path}")
        xmin, ymin, xmax, ymax = (int(float(node.findtext(key))) for key in ("xmin", "ymin", "xmax", "ymax"))
        if xmin < 1 or ymin < 1 or xmax < xmin or ymax < ymin or xmax > width or ymax > height:
            raise ValueError(f"invalid VOC box in {xml_path}: {(xmin, ymin, xmax, ymax)}")
        boxes.append({"index": index, "label": int(label), "box": (xmin - 1, ymin - 1, xmax, ymax)})
    return width, height, boxes


def hardware_candidates(gray):
    """Mirror cnn_frame_digit_detector's threshold, bands, columns, and limits."""
    mask = gray < 128
    active_rows = np.flatnonzero(mask.sum(axis=1) >= 2)
    bands = []
    if active_rows.size:
        start = last = int(active_rows[0])
        for y in active_rows[1:]:
            y = int(y)
            if y - last > 1:
                bands.append((start, last))
                start = y
            last = y
        bands.append((start, last))

    candidates = []
    for band_top, band_bottom in bands[:8]:
        band = mask[band_top : band_bottom + 1]
        active_cols = np.flatnonzero(band.any(axis=0))
        if not active_cols.size:
            continue
        segments = []
        start = last = int(active_cols[0])
        for x in active_cols[1:]:
            x = int(x)
            if x - last > 1:
                segments.append((start, last))
                start = x
            last = x
        segments.append((start, last))

        for x0, x1 in segments:
            component = mask[band_top : band_bottom + 1, x0 : x1 + 1]
            ys, _ = np.nonzero(component)
            if not ys.size:
                continue
            y0 = band_top + int(ys.min())
            y1 = band_top + int(ys.max())
            width, height = x1 - x0 + 1, y1 - y0 + 1
            area = int(component.sum())
            if not (3 <= width <= 96 and 18 <= height <= 96 and area >= 18):
                continue
            if width * 10 > height * 18:
                continue
            candidates.append({"box": (x0, y0, width, height), "area": area})
            if len(candidates) == 16:
                return candidates
    return candidates


def make_hardware_patch(gray, box):
    x, y, width, height = box
    active_size = max(width, height)
    scaled_w = max(1, (width * 20 + active_size // 2) // active_size)
    scaled_h = max(1, (height * 20 + active_size // 2) // active_size)
    source_x = (np.arange(scaled_w, dtype=np.int32) * width) // scaled_w
    source_y = (np.arange(scaled_h, dtype=np.int32) * height) // scaled_h
    ink = (gray[y + source_y[:, None], x + source_x[None, :]] < 128).astype(np.uint8) * 255
    patch = np.zeros((28, 28), dtype=np.uint8)
    left = 4 + ((20 - scaled_w) >> 1)
    top = 4 + ((20 - scaled_h) >> 1)
    patch[top : top + scaled_h, left : left + scaled_w] = ink
    return patch


def box_iou(a, b):
    ax, ay, aw, ah = a
    bx0, by0, bx1, by1 = b
    ax1, ay1 = ax + aw, ay + ah
    iw = max(0, min(ax1, bx1) - max(ax, bx0))
    ih = max(0, min(ay1, by1) - max(ay, by0))
    inter = iw * ih
    union = aw * ah + (bx1 - bx0) * (by1 - by0) - inter
    return inter / union if union else 0.0


def match_candidates(candidates, annotations):
    pairs = []
    for ci, candidate in enumerate(candidates):
        x, y, width, height = candidate["box"]
        cx, cy = x + width / 2, y + height / 2
        for ai, annotation in enumerate(annotations):
            bx0, by0, bx1, by1 = annotation["box"]
            inside = bx0 <= cx < bx1 and by0 <= cy < by1
            overlap = box_iou(candidate["box"], annotation["box"])
            if inside or overlap >= 0.20:
                pairs.append((overlap, ci, ai))
    pairs.sort(reverse=True)
    matched_candidates, matched_annotations, matches = set(), set(), {}
    for overlap, ci, ai in pairs:
        if ci not in matched_candidates and ai not in matched_annotations:
            matched_candidates.add(ci)
            matched_annotations.add(ai)
            matches[ci] = (ai, overlap)
    return matches, matched_annotations


def save_contact_sheet(records, path):
    if not records:
        return
    columns, tile, label_h = 10, 56, 18
    rows = (len(records) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * tile, rows * (tile + label_h)), "#b8b8b8")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for index, record in enumerate(records):
        image = Image.open(record["patch"]).convert("L").resize((tile, tile), Image.Resampling.NEAREST)
        x, y = (index % columns) * tile, (index // columns) * (tile + label_h)
        sheet.paste(image.convert("RGB"), (x, y))
        draw.text((x + 2, y + tile), f"{record['label']} {record['group']}", fill="black", font=font)
    sheet.save(path)


def prepare_dataset(groups, output_dir):
    patch_root = output_dir / "patches"
    patch_root.mkdir(parents=True)
    records, summaries = [], {}
    for group, directory in groups.items():
        xml_paths = sorted(directory.glob("*.xml"))
        if not xml_paths:
            raise ValueError(f"no XML annotations found in {directory}")
        group_records = []
        total_annotations = total_candidates = matched_count = false_positive = 0
        missed = Counter()
        for xml_path in xml_paths:
            image_path = xml_path.with_suffix(".png")
            if not image_path.is_file():
                raise FileNotFoundError(f"missing image for {xml_path}")
            width, height, annotations = read_annotations(xml_path)
            with Image.open(image_path) as source:
                image = source.convert("L")
                if image.size != (320, 180) or image.size != (width, height):
                    raise ValueError(f"image/XML size mismatch: {image_path} image={image.size} xml={(width, height)}")
                gray = np.asarray(image, dtype=np.uint8)
            candidates = hardware_candidates(gray)
            matches, matched_annotations = match_candidates(candidates, annotations)
            total_annotations += len(annotations)
            total_candidates += len(candidates)
            matched_count += len(matches)
            false_positive += len(candidates) - len(matches)
            for ai, annotation in enumerate(annotations):
                if ai not in matched_annotations:
                    missed[annotation["label"]] += 1
            frame_key = f"{group}/{xml_path.stem}"
            for ci, candidate in enumerate(candidates):
                if ci not in matches:
                    continue
                ai, overlap = matches[ci]
                annotation = annotations[ai]
                patch = make_hardware_patch(gray, candidate["box"])
                patch_path = patch_root / group / str(annotation["label"]) / f"{xml_path.stem}_{ci:02d}.png"
                patch_path.parent.mkdir(parents=True, exist_ok=True)
                Image.fromarray(patch).save(patch_path)
                record = {
                    "group": group,
                    "frame": frame_key,
                    "label": annotation["label"],
                    "annotation_index": annotation["index"],
                    "candidate_index": ci,
                    "candidate_box": candidate["box"],
                    "annotation_box": annotation["box"],
                    "iou": overlap,
                    "patch": str(patch_path.resolve()),
                }
                records.append(record)
                group_records.append(record)
        summaries[group] = {
            "frames": len(xml_paths),
            "annotations": total_annotations,
            "hardware_candidates": total_candidates,
            "matched": matched_count,
            "false_positive_candidates": false_positive,
            "missed_annotations_by_class": {str(key): value for key, value in sorted(missed.items())},
            "class_counts_matched": {str(key): value for key, value in sorted(Counter(r["label"] for r in group_records).items())},
        }
        save_contact_sheet(group_records, output_dir / f"contact_{group}.png")
    manifest = {"groups": summaries, "records": records}
    (output_dir / "dataset.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


class PatchSet(Dataset):
    def __init__(self, records, augment=False):
        self.records = records
        self.transform = transforms.Compose(
            [
                transforms.RandomAffine(degrees=7, translate=(0.06, 0.06), scale=(0.92, 1.08), fill=0),
                transforms.ToTensor(),
            ]
            if augment
            else [transforms.ToTensor()]
        )

    def __len__(self):
        return len(self.records)

    def __getitem__(self, index):
        record = self.records[index]
        with Image.open(record["patch"]) as image:
            tensor = self.transform(image.convert("L"))
        return tensor, record["label"]


def evaluate(model, records, device):
    loader = DataLoader(PatchSet(records), batch_size=64, shuffle=False, num_workers=0)
    confusion = torch.zeros((10, 10), dtype=torch.int64)
    loss_sum, count = 0.0, 0
    criterion = nn.CrossEntropyLoss(reduction="sum")
    model.eval()
    with torch.inference_mode():
        offset = 0
        for images, labels in loader:
            logits = model(images.to(device))
            labels = labels.to(device)
            loss_sum += criterion(logits, labels).item()
            predictions = logits.argmax(1)
            for truth, prediction in zip(labels.cpu().tolist(), predictions.cpu().tolist()):
                confusion[truth, prediction] += 1
            count += labels.numel()
            offset += labels.numel()
    correct = int(confusion.diag().sum())
    per_class = {}
    for label in range(10):
        support = int(confusion[label].sum())
        per_class[str(label)] = {
            "correct": int(confusion[label, label]),
            "total": support,
            "accuracy": float(confusion[label, label] / support) if support else None,
        }
    return {
        "count": count,
        "correct": correct,
        "accuracy": correct / count if count else 0.0,
        "loss": loss_sum / count if count else None,
        "per_class": per_class,
        "confusion_matrix_rows_truth_cols_prediction": confusion.tolist(),
    }


def split_train_validation(records, groups, seed, fraction=0.2):
    frames_by_group = {group: sorted({record["frame"] for record in records if record["group"] == group}) for group in groups}
    validation_frames = set()
    for group_index, group in enumerate(groups):
        frames = frames_by_group[group]
        random.Random(seed + group_index).shuffle(frames)
        val_count = min(max(1, round(len(frames) * fraction)), max(1, len(frames) - 1))
        validation_frames.update(frames[:val_count])
    train_records = [r for r in records if r["group"] in groups and r["frame"] not in validation_frames]
    val_records = [r for r in records if r["group"] in groups and r["frame"] in validation_frames]
    return train_records, val_records, sorted(validation_frames)


def train_fold(name, train_groups, test_group, records, base_checkpoint, output_dir, epochs, seed, device):
    fold_dir = output_dir / f"fold_{name}"
    fold_dir.mkdir(parents=True, exist_ok=False)
    train_records, val_records, val_frames = split_train_validation(records, train_groups, seed)
    test_records = [r for r in records if r["group"] == test_group]
    if not train_records or not val_records or not test_records:
        raise ValueError(f"empty train/validation/test split in {name}")

    checkpoint = torch.load(base_checkpoint, map_location="cpu", weights_only=True)
    if checkpoint.get("architecture") != "small_digit_cnn_28x28_v1":
        raise ValueError(f"unsupported checkpoint architecture: {checkpoint.get('architecture')}")
    model = SmallDigitCNN().to(device)
    model.load_state_dict(checkpoint["model_state"])
    baseline = evaluate(model, test_records, device)

    counts = Counter(record["label"] for record in train_records)
    sample_weights = [1.0 / counts[record["label"]] for record in train_records]
    sampler = WeightedRandomSampler(sample_weights, len(train_records), replacement=True)
    train_loader = DataLoader(PatchSet(train_records, augment=True), batch_size=32, sampler=sampler, num_workers=0)
    val_loader = DataLoader(PatchSet(val_records), batch_size=64, shuffle=False, num_workers=0)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=7.5e-5, weight_decay=1e-4)

    best_key, best_state, best_epoch, stale = (-1.0, float("inf")), None, 0, 0
    history = []
    for epoch in range(1, epochs + 1):
        model.train()
        total_loss, correct, count = 0.0, 0, 0
        for images, labels in train_loader:
            images, labels = images.to(device), labels.to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(images)
            loss = criterion(logits, labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * labels.size(0)
            correct += (logits.argmax(1) == labels).sum().item()
            count += labels.size(0)
        val_result = evaluate(model, val_records, device)
        train_result = {"loss": total_loss / count, "accuracy": correct / count, "count": count}
        history.append({"epoch": epoch, "train": train_result, "validation": val_result})
        print(
            f"fold={name} epoch={epoch:02d} train_acc={train_result['accuracy']:.3f} "
            f"val_acc={val_result['accuracy']:.3f} val_loss={val_result['loss']:.4f}",
            flush=True,
        )
        key = (val_result["accuracy"], -val_result["loss"])
        if key > best_key:
            best_key = key
            best_epoch = epoch
            best_state = {key: value.detach().cpu().clone() for key, value in model.state_dict().items()}
            stale = 0
        else:
            stale += 1
            if stale >= 7:
                break

    if best_state is None:
        raise RuntimeError(f"no checkpoint selected for {name}")
    model.load_state_dict(best_state)
    tuned = evaluate(model, test_records, device)
    result = {
        "fold": name,
        "train_groups": train_groups,
        "test_group": test_group,
        "train_patch_count": len(train_records),
        "validation_patch_count": len(val_records),
        "test_patch_count": len(test_records),
        "validation_frames": val_frames,
        "best_epoch": best_epoch,
        "baseline_test": baseline,
        "tuned_test": tuned,
        "history": history,
    }
    torch.save(
        {
            "format_version": 1,
            "architecture": "small_digit_cnn_28x28_v1",
            "input_size": INPUT_SIZE,
            "input_channels": 1,
            "classes": list(CLASSES),
            "camera_eval_accuracy": tuned["accuracy"],
            "train_groups": train_groups,
            "held_out_group": test_group,
            "best_epoch": best_epoch,
            "base_checkpoint": str(base_checkpoint.resolve()),
            "model_state": best_state,
        },
        fold_dir / "checkpoint.pt",
    )
    (fold_dir / "metrics.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xjp", type=Path, default=ROOT / "photo" / "xjp")
    parser.add_argument("--huihua", type=Path, default=ROOT / "photo" / "huihua")
    parser.add_argument("--ljc", type=Path, default=ROOT / "photo" / "ljc")
    parser.add_argument("--base-checkpoint", type=Path, default=DEFAULT_BASE)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "cnn" / "outputs" / "camera_cv_20261028")
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20261028)
    parser.add_argument("--device", default="auto")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--train-only", action="store_true", help="reuse the prepared dataset.json")
    args = parser.parse_args()
    if args.epochs <= 0 or (args.prepare_only and args.train_only):
        parser.error("epochs must be positive and prepare-only/train-only are mutually exclusive")
    if not args.base_checkpoint.is_file():
        parser.error(f"base checkpoint does not exist: {args.base_checkpoint}")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = args.output_dir / "dataset.json"
    if args.train_only:
        if not manifest_path.is_file():
            parser.error(f"prepared dataset is missing: {manifest_path}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    else:
        if manifest_path.exists():
            parser.error(f"prepared dataset already exists: {manifest_path}; choose a new --output-dir")
        groups = {"xjp": args.xjp.resolve(), "huihua": args.huihua.resolve(), "ljc": args.ljc.resolve()}
        manifest = prepare_dataset(groups, args.output_dir)
        print("PREPARATION SUMMARY", json.dumps(manifest["groups"], ensure_ascii=False), flush=True)
        print(f"prepared_patches={len(manifest['records'])} output={args.output_dir.resolve()}", flush=True)
        if args.prepare_only:
            return

    records = manifest["records"]
    result_dir = args.output_dir / "cross_validation"
    result_dir.mkdir(exist_ok=True)
    device = torch.device("cuda" if args.device == "auto" and torch.cuda.is_available() else ("cpu" if args.device == "auto" else args.device))
    print(f"device={device} base_checkpoint={args.base_checkpoint}", flush=True)
    results = []
    folds = (("xjp_huihua__ljc", ["xjp", "huihua"], "ljc"), ("xjp_ljc__huihua", ["xjp", "ljc"], "huihua"))
    for name, train_groups, test_group in folds:
        results.append(train_fold(name, train_groups, test_group, records, args.base_checkpoint, result_dir, args.epochs, args.seed, device))
    summary = {
        "base_checkpoint": str(args.base_checkpoint.resolve()),
        "preprocessing": "RTL threshold <128, row bands/column components, RTL 20x20 nearest-neighbor sampling into 28x28",
        "folds": results,
    }
    summary_path = result_dir / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(f"SUMMARY={summary_path.resolve()}", flush=True)
    for fold in results:
        before, after = fold["baseline_test"], fold["tuned_test"]
        print(
            f"RESULT {fold['fold']}: baseline={before['correct']}/{before['count']} ({before['accuracy']:.3f}) "
            f"tuned={after['correct']}/{after['count']} ({after['accuracy']:.3f}) best_epoch={fold['best_epoch']}",
            flush=True,
        )


if __name__ == "__main__":
    main()
