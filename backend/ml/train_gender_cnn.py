#!/usr/bin/env python3
"""
Train a small gender classifier on a directory of images:
  data_dir/Male/*.jpg
  data_dir/Female/*.jpg
  data_dir/Transgender/*.jpg  (optional)

Download a licensed dataset from Kaggle (e.g. UTKFace), map folders to these labels, then run:
  python train_gender_cnn.py --data-dir ./data --epochs 20 --out weights.pt
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch
import torch.nn as nn
from PIL import Image
from torch.utils.data import DataLoader, Dataset
from torchvision import models, transforms


LABELS = ["Male", "Female", "Transgender"]


class FolderGenderDataset(Dataset):
    def __init__(self, root: Path, tfm):
        self.samples: list[tuple[Path, int]] = []
        self.tfm = tfm
        for i, lab in enumerate(LABELS):
            d = root / lab
            if not d.is_dir():
                continue
            for p in d.rglob("*"):
                if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}:
                    self.samples.append((p, i))
        if not self.samples:
            raise SystemExit(f"No images found under {root} for labels {LABELS}")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, y = self.samples[idx]
        img = Image.open(path).convert("RGB")
        return self.tfm(img), y


def build_model(num_classes: int) -> nn.Module:
    m = models.mobilenet_v3_small(weights=models.MobileNet_V3_Small_Weights.IMAGENET1K_V1)
    m.classifier[3] = nn.Linear(m.classifier[3].in_features, num_classes)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", type=Path, required=True)
    ap.add_argument("--epochs", type=int, default=12)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--out", type=Path, default=Path("weights.pt"))
    args = ap.parse_args()

    tfm = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.RandomHorizontalFlip(),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ]
    )
    ds = FolderGenderDataset(args.data_dir, tfm)
    n_classes = max(y for _, y in ds.samples) + 1
    if n_classes < 2:
        raise SystemExit("Need at least two classes with images.")

    dl = DataLoader(ds, batch_size=args.batch, shuffle=True, num_workers=0)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = build_model(n_classes).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=args.lr)
    loss_fn = nn.CrossEntropyLoss()

    model.train()
    for epoch in range(args.epochs):
        total, correct = 0, 0
        for x, y in dl:
            x, y = x.to(device), y.to(device)
            opt.zero_grad()
            logits = model(x)
            loss = loss_fn(logits, y)
            loss.backward()
            opt.step()
            total += y.size(0)
            correct += (logits.argmax(1) == y).sum().item()
        acc = 100.0 * correct / max(total, 1)
        print(json.dumps({"epoch": epoch + 1, "loss": float(loss.item()), "acc": acc}))

    meta = {"labels": LABELS[:n_classes], "arch": "mobilenet_v3_small"}
    torch.save({"state": model.state_dict(), "meta": meta}, args.out)
    print(json.dumps({"saved": str(args.out.resolve()), "classes": n_classes}))


if __name__ == "__main__":
    main()
