import numpy as np
import torch
from pathlib import Path
from torch.utils.data import Dataset, DataLoader
from torchvision import transforms

MEAN = (0.4914, 0.4822, 0.4465)
STD  = (0.2023, 0.1994, 0.2010)

# CIFAR-10 binary format: each record = 1 byte label + 3072 bytes RGB (3x32x32)
_TRAIN_FILES = [f'data_batch_{i}.bin' for i in range(1, 6)]
_TEST_FILES  = ['test_batch.bin']


def _load_bin(paths):
    records = []
    for p in paths:
        raw = np.frombuffer(Path(p).read_bytes(), dtype=np.uint8)
        raw = raw.reshape(-1, 3073)
        records.append(raw)
    raw = np.concatenate(records, axis=0)
    labels = raw[:, 0].astype(np.int64)
    images = raw[:, 1:].reshape(-1, 3, 32, 32)
    return images, labels


class Cifar10Binary(Dataset):
    """Reads CIFAR-10 from the original binary files (same format as C++ loader)."""

    def __init__(self, data_dir, train: bool, transform=None):
        data_dir = Path(data_dir).expanduser()
        files = _TRAIN_FILES if train else _TEST_FILES
        images, labels = _load_bin([data_dir / f for f in files])
        self.images = torch.from_numpy(images)
        self.labels = torch.from_numpy(labels)
        self.transform = transform

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        img = self.images[idx].float() / 255.0
        if self.transform:
            img = self.transform(img)
        return img, self.labels[idx]


def cifar10_loaders(data_dir, batch_size=128, num_workers=4):
    train_tf = transforms.Compose([
        transforms.RandomCrop(32, padding=4),
        transforms.RandomHorizontalFlip(),
        transforms.Normalize(MEAN, STD),
    ])
    test_tf = transforms.Normalize(MEAN, STD)

    train_ds = Cifar10Binary(data_dir, train=True,  transform=train_tf)
    test_ds  = Cifar10Binary(data_dir, train=False, transform=test_tf)

    train_loader = DataLoader(
        train_ds, batch_size=batch_size, shuffle=True,
        num_workers=num_workers, pin_memory=True,
    )
    test_loader = DataLoader(
        test_ds, batch_size=512, shuffle=False,
        num_workers=num_workers, pin_memory=True,
    )
    return train_loader, test_loader
