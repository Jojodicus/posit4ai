"""Train ResNet-18 in FP32 on CIFAR-10."""
import argparse
import random
import sys
from pathlib import Path

import torch
import torch.nn as nn

sys.path.insert(0, str(Path(__file__).parent))
from models.resnet18 import ResNet18
from utils.data import cifar10_loaders
from utils.fusion import export_fused_jit
from utils.metrics import evaluate, EpochLogger, save_meta

SEED = 42
EPOCHS = 100
BATCH_SIZE = 128
LR = 0.1
MOMENTUM = 0.9
WEIGHT_DECAY = 5e-4


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--data-dir', default='dataset/cifar10')
    p.add_argument('--out-dir', default='results/resnet')
    p.add_argument('--epochs', type=int, default=EPOCHS)
    p.add_argument('--workers', type=int, default=4)
    return p.parse_args()


def set_seed(seed):
    random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


def main():
    args = parse_args()
    set_seed(SEED)

    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    out = Path(args.out_dir)
    (out / 'checkpoints').mkdir(parents=True, exist_ok=True)

    train_loader, val_loader, _ = cifar10_loaders(args.data_dir, BATCH_SIZE, args.workers)

    model = ResNet18().to(device)
    optimizer = torch.optim.SGD(
        model.parameters(), lr=LR, momentum=MOMENTUM, weight_decay=WEIGHT_DECAY
    )
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
    criterion = nn.CrossEntropyLoss()

    logger = EpochLogger(out / 'logs' / 'train_resnet18_fp32.csv')
    best_acc = 0.0

    for epoch in range(1, args.epochs + 1):
        model.train()
        train_loss = 0.0
        train_correct = 0
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            optimizer.zero_grad()
            logits = model(x)
            loss = criterion(logits, y)
            loss.backward()
            optimizer.step()
            train_loss += loss.item() * x.size(0)
            train_correct += logits.argmax(1).eq(y).sum().item()
        scheduler.step()

        train_loss /= len(train_loader.dataset)
        train_acc = train_correct / len(train_loader.dataset)
        val_acc, val_nll = evaluate(model, val_loader, device)
        lr = scheduler.get_last_lr()[0]

        logger.log({
            'epoch': epoch,
            'train_loss': round(train_loss, 6),
            'train_acc': round(train_acc, 6),
            'val_acc': round(val_acc, 6),
            'val_nll': round(val_nll, 6),
            'lr': round(lr, 8),
        })
        print(f'[{epoch:3d}/{args.epochs}] loss={train_loss:.4f}  train_acc={train_acc:.4f}  val_acc={val_acc:.4f}  nll={val_nll:.4f}')

        if val_acc > best_acc:
            best_acc = val_acc
            torch.save(model.state_dict(), out / 'checkpoints' / 'ckpt_resnet18_best.pt')

    torch.save(model.state_dict(), out / 'checkpoints' / 'ckpt_resnet18.pt')
    export_fused_jit(model, out / 'checkpoints' / 'ckpt_resnet18_fused.pt')
    logger.close()

    save_meta(out / 'logs' / 'train_resnet18_fp32_meta.json', {
        'run': 'resnet18_fp32', 'model': 'resnet18', 'format': 'fp32',
        'epochs': args.epochs,
        'best_val_acc': best_acc,
        'final_train_acc': train_acc,
        'final_val_acc': val_acc,
        'final_val_nll': val_nll,
        'config': {
            'lr': LR, 'momentum': MOMENTUM, 'weight_decay': WEIGHT_DECAY,
            'batch_size': BATCH_SIZE, 'seed': SEED, 'scheduler': 'cosine',
        },
    })
    print(f'Done. Best val acc: {best_acc:.4f}')


if __name__ == '__main__':
    main()
