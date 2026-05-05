"""Generate plots from experiment results.

Usage:
    python scripts/plot.py --results-dir results
"""
import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def load_csv(path):
    return pd.read_csv(path)


def plot_training_curves(results_dir: Path, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)

    runs = {
        'ResNet-18 FP32':    results_dir / 'logs' / 'train_resnet18_fp32.csv',
        'ResNet-18 FP64 ft': results_dir / 'logs' / 'finetune_resnet18_fp64.csv',
        'CifarNet FP32':     results_dir / 'logs' / 'train_cifarnet_fp32.csv',
    }

    fig, axes = plt.subplots(1, 2, figsize=(12, 4))

    for label, path in runs.items():
        if not path.exists():
            continue
        df = load_csv(path)
        axes[0].plot(df['epoch'], df['train_loss'], label=label)
        axes[1].plot(df['epoch'], df['val_acc'], label=label)

    axes[0].set(xlabel='Epoch', ylabel='Train Loss', title='Training Loss')
    axes[1].set(xlabel='Epoch', ylabel='Val Accuracy', title='Validation Accuracy')
    for ax in axes:
        ax.legend()
        ax.grid(True, alpha=0.3)

    fig.tight_layout()
    fig.savefig(out_dir / 'training_curves.png', dpi=150)
    print('Saved training_curves.png')
    plt.close(fig)


def plot_accuracy_frontier(results_dir: Path, out_dir: Path):
    """Accuracy vs bits for posit (es=1,2,3) with float format reference lines.

    Expects results/logs/inference_results.csv with columns:
        source, model, format, nbits, es, val_acc, val_nll
    """
    path = results_dir / 'logs' / 'inference_results.csv'
    if not path.exists():
        print(f'Inference results not found at {path}, skipping frontier plot.')
        return

    out_dir.mkdir(parents=True, exist_ok=True)
    df = pd.read_csv(path)

    for source in df['source'].unique():
        sub = df[df['source'] == source]
        fig, ax = plt.subplots(figsize=(8, 5))

        posit_df = sub[sub['format'] == 'posit']
        for es in sorted(posit_df['es'].unique()):
            pts = posit_df[posit_df['es'] == es].sort_values('nbits')
            ax.plot(pts['nbits'], pts['val_acc'], marker='o', label=f'posit es={es}')

        float_formats = sub[sub['format'] != 'posit']
        colors = {'fp16': 'C3', 'bf16': 'C4', 'tf32': 'C5', 'fp32': 'C6', 'fp64': 'C7'}
        for _, row in float_formats.iterrows():
            fmt = row['format']
            ax.axhline(row['val_acc'], linestyle='--', alpha=0.6,
                       label=fmt.upper(), color=colors.get(fmt, 'gray'))

        ax.set(xlabel='Bits', ylabel='Val Accuracy',
               title=f'Accuracy Frontier (source: {source})',
               xticks=[8, 16, 32])
        ax.legend()
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        fname = out_dir / f'frontier_{source}.png'
        fig.savefig(fname, dpi=150)
        print(f'Saved {fname}')
        plt.close(fig)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--results-dir', default='results')
    p.add_argument('--out-dir', default='results/plots')
    args = p.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = Path(args.out_dir)

    plot_training_curves(results_dir, out_dir)
    plot_accuracy_frontier(results_dir, out_dir)


if __name__ == '__main__':
    main()
