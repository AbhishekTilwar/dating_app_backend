#!/usr/bin/env python3
"""Load weights.pt (if any) and classify one image path. Prints one JSON line to stdout."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import torch
import torch.nn as nn
from PIL import Image
from torchvision import models, transforms


def build_model(num_classes: int) -> nn.Module:
    m = models.mobilenet_v3_small(weights=None)
    m.classifier[3] = nn.Linear(m.classifier[3].in_features, num_classes)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image_path", type=Path)
    ap.add_argument("--weights", type=Path, default=Path(__file__).parent / "weights.pt")
    args = ap.parse_args()

    if not args.weights.is_file():
        print(json.dumps({"ok": False, "error": "weights.pt not found; train the model first."}))
        sys.exit(0)

    try:
        ckpt = torch.load(args.weights, map_location="cpu", weights_only=False)
    except TypeError:
        ckpt = torch.load(args.weights, map_location="cpu")
    meta = ckpt.get("meta") or {}
    labels = meta.get("labels") or ["Male", "Female"]
    n = len(labels)
    model = build_model(n)
    model.load_state_dict(ckpt["state"])
    model.eval()

    tfm = transforms.Compose(
        [
            transforms.Resize((224, 224)),
            transforms.ToTensor(),
            transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
        ]
    )
    img = Image.open(args.image_path).convert("RGB")
    x = tfm(img).unsqueeze(0)
    with torch.no_grad():
        logits = model(x)
        prob = torch.softmax(logits, dim=1)[0]
        idx = int(prob.argmax().item())
        conf = float(prob[idx].item())
    print(json.dumps({"ok": True, "gender": labels[idx], "confidence": conf, "labels": labels}))


if __name__ == "__main__":
    main()
