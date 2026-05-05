import csv
import json
from pathlib import Path

import torch
import torch.nn.functional as F


def evaluate(model, loader, device, dtype=torch.float32):
    """Returns (accuracy, mean NLL). Logits are cast to fp32 before metric computation."""
    model.eval()
    correct = total = 0
    total_nll = 0.0
    with torch.no_grad():
        for x, y in loader:
            x = x.to(device=device, dtype=dtype)
            y = y.to(device)
            log_probs = F.log_softmax(model(x).float(), dim=1)
            total_nll += F.nll_loss(log_probs, y, reduction='sum').item()
            correct += log_probs.argmax(1).eq(y).sum().item()
            total += y.size(0)
    return correct / total, total_nll / total


class EpochLogger:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = open(self.path, 'w', newline='')
        self._writer = None

    def log(self, row: dict):
        if self._writer is None:
            self._writer = csv.DictWriter(self._file, fieldnames=list(row.keys()))
            self._writer.writeheader()
        self._writer.writerow(row)
        self._file.flush()

    def close(self):
        self._file.close()


def save_meta(path, meta: dict):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(p, 'w') as f:
        json.dump(meta, f, indent=2)
