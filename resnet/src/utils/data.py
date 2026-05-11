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


def cifar10_loaders(data_dir, batch_size=128, num_workers=4, val_split=0.1, seed=42):
    train_tf = transforms.Compose([
        transforms.RandomCrop(32, padding=4),
        transforms.RandomHorizontalFlip(),
        transforms.Normalize(MEAN, STD),
    ])
    val_tf   = transforms.Normalize(MEAN, STD)
    test_tf  = transforms.Normalize(MEAN, STD)

    full_train_ds = Cifar10Binary(data_dir, train=True,  transform=train_tf)
    test_ds       = Cifar10Binary(data_dir, train=False, transform=test_tf)

    n_val   = int(len(full_train_ds) * val_split)
    n_train = len(full_train_ds) - n_val
    generator = torch.Generator().manual_seed(seed)
    train_ds, val_ds = torch.utils.data.random_split(
        full_train_ds, [n_train, n_val], generator=generator)
    # val subset uses the same augmenting transform; override with val_tf
    val_ds.dataset = Cifar10Binary(data_dir, train=True, transform=val_tf)

    train_loader = DataLoader(
        train_ds, batch_size=batch_size, shuffle=True,
        num_workers=num_workers, pin_memory=True,
    )
    val_loader = DataLoader(
        val_ds, batch_size=512, shuffle=False,
        num_workers=num_workers, pin_memory=True,
    )
    test_loader = DataLoader(
        test_ds, batch_size=512, shuffle=False,
        num_workers=num_workers, pin_memory=True,
    )
    return train_loader, val_loader, test_loader


MNIST_MEAN = (0.1307,)
MNIST_STD  = (0.3081,)

_MNIST_TRAIN_IMAGES = 'train-images-idx3-ubyte'
_MNIST_TRAIN_LABELS = 'train-labels-idx1-ubyte'
_MNIST_TEST_IMAGES  = 't10k-images-idx3-ubyte'
_MNIST_TEST_LABELS  = 't10k-labels-idx1-ubyte'


def _load_mnist_images(path):
    raw = np.frombuffer(Path(path).read_bytes(), dtype=np.uint8)
    # 16-byte header: magic(4) + n_images(4) + rows(4) + cols(4)
    return raw[16:].reshape(-1, 1, 28, 28)


def _load_mnist_labels(path):
    raw = np.frombuffer(Path(path).read_bytes(), dtype=np.uint8)
    # 8-byte header: magic(4) + n_labels(4)
    return raw[8:].astype(np.int64)


class MnistBinary(Dataset):
    """Reads MNIST from raw IDX files (same format as C++ loader)."""

    def __init__(self, data_dir, train: bool, transform=None):
        data_dir = Path(data_dir).expanduser()
        img_file = _MNIST_TRAIN_IMAGES if train else _MNIST_TEST_IMAGES
        lbl_file = _MNIST_TRAIN_LABELS if train else _MNIST_TEST_LABELS
        self.images = torch.from_numpy(_load_mnist_images(data_dir / img_file))
        self.labels = torch.from_numpy(_load_mnist_labels(data_dir / lbl_file))
        self.transform = transform

    def __len__(self):
        return len(self.labels)

    def __getitem__(self, idx):
        img = self.images[idx].float() / 255.0
        if self.transform:
            img = self.transform(img)
        return img, self.labels[idx]


def mnist_loaders(data_dir, batch_size=128, num_workers=4, val_split=0.1, seed=42):
    tf = transforms.Normalize(MNIST_MEAN, MNIST_STD)
    full_train_ds = MnistBinary(data_dir, train=True,  transform=tf)
    test_ds       = MnistBinary(data_dir, train=False, transform=tf)

    n_val   = int(len(full_train_ds) * val_split)
    n_train = len(full_train_ds) - n_val
    generator = torch.Generator().manual_seed(seed)
    train_ds, val_ds = torch.utils.data.random_split(
        full_train_ds, [n_train, n_val], generator=generator)

    train_loader = DataLoader(
        train_ds, batch_size=batch_size, shuffle=True,
        num_workers=num_workers, pin_memory=True,
    )
    val_loader = DataLoader(
        val_ds, batch_size=512, shuffle=False,
        num_workers=num_workers, pin_memory=True,
    )
    test_loader = DataLoader(
        test_ds, batch_size=512, shuffle=False,
        num_workers=num_workers, pin_memory=True,
    )
    return train_loader, val_loader, test_loader
