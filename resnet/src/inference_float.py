"""Float-format inference sweep (FP16, BF16, TF32).

Loads a checkpoint, casts the model, runs inference, and appends to
results/logs/inference_results.csv.
"""
import argparse
import sys
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).parent))
from models.resnet18 import ResNet18
from models.cifarnet import CifarNet
from utils.data import cifar10_loaders
from utils.metrics import evaluate

FORMATS = {
    'fp16': torch.float16,
    'bf16': torch.bfloat16,
    'tf32': torch.float32,   # TF32 is float32 storage; enabled via backend flag
    'fp32': torch.float32,
    'fp64': torch.float64,
}

MODELS = {'resnet18': ResNet18, 'cifarnet': CifarNet}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--model', default='resnet18', choices=list(MODELS))
    p.add_argument('--ckpt', required=True, help='state_dict .pt file')
    p.add_argument('--source', required=True, help='label written to CSV (e.g. resnet18_fp32)')
    p.add_argument('--ckpt-dtype', default='float32', choices=['float32', 'float64'],
                   help='dtype the checkpoint was saved in')
    p.add_argument('--formats', nargs='+', default=['fp16', 'bf16', 'tf32'],
                   choices=list(FORMATS))
    p.add_argument('--data-dir', default='dataset/cifar10')
    p.add_argument('--out-dir', default='results')
    p.add_argument('--workers', type=int, default=8)
    p.add_argument('--cpu', action='store_true')
    return p.parse_args()


def run_format(model, fmt, test_loader, device):
    if fmt == 'tf32':
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        eval_dtype = torch.float32
    else:
        torch.backends.cuda.matmul.allow_tf32 = False
        torch.backends.cudnn.allow_tf32 = False
        eval_dtype = FORMATS[fmt]

    cast_model = model.to(device).to(eval_dtype)
    val_acc, val_nll = evaluate(cast_model, test_loader, device, dtype=eval_dtype)
    print(f'  {fmt:5s}  acc={val_acc:.4f}  nll={val_nll:.4f}')
    return val_acc, val_nll


def main():
    args = parse_args()
    device = torch.device('cuda' if not args.cpu and torch.cuda.is_available() else 'cpu')
    out = Path(args.out_dir)

    ckpt_dtype = torch.float64 if args.ckpt_dtype == 'float64' else torch.float32
    model = MODELS[args.model]()
    sd = torch.load(args.ckpt, map_location='cpu')
    if ckpt_dtype == torch.float64:
        model = model.double()
    model.load_state_dict(sd)
    model.eval()

    _, test_loader = cifar10_loaders(args.data_dir, batch_size=512, num_workers=args.workers)

    out_csv = out / 'logs' / 'inference_results.csv'
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    write_header = not out_csv.exists()

    with open(out_csv, 'a') as f:
        if write_header:
            f.write('source,model,format,nbits,es,val_acc,val_nll\n')
        for fmt in args.formats:
            acc, nll = run_format(model, fmt, test_loader, device)
            bits = {'fp16': 16, 'bf16': 16, 'tf32': 19, 'fp32': 32, 'fp64': 64}.get(fmt, -1)
            f.write(f'{args.source},{args.model},{fmt},{bits},,{acc:.6f},{nll:.6f}\n')
            f.flush()

    print(f'Results appended to {out_csv}')


if __name__ == '__main__':
    main()
