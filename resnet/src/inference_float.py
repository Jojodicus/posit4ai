"""Float-format inference sweep (FP16, BF16, TF32, FP32, FP64).

Loads a checkpoint, casts the model, runs inference, and appends to
results/<model>/logs/inference_results.csv.
"""
import argparse
import copy
import sys
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).parent))
from models.resnet18 import ResNet18
from models.cifarnet import CifarNet
from models.smallnet import SmallNet
from utils.data import cifar10_loaders, mnist_loaders
from utils.metrics import evaluate

FORMATS = {
    'fp16':     torch.float16,
    'bf16':     torch.bfloat16,
    'tf32':     torch.float32,      # TF32 is float32 storage; enabled via backend flag
    'fp32':     torch.float32,
    'fp64':     torch.float64,
    'fp8_e4m3': torch.float8_e4m3fn,   # 1s4e3m — better for weights/activations
    'fp8_e5m2': torch.float8_e5m2,     # 1s5e2m — wider range, noisier mantissa
}

# FP8 dtypes are storage-only in PyTorch: compute runs in FP16 with a
# quantize-dequantize round-trip on weights and activations.
_FP8_DTYPES = {torch.float8_e4m3fn, torch.float8_e5m2}

MODELS = {'resnet18': ResNet18, 'cifarnet': CifarNet, 'smallnet': SmallNet}

CIFAR_MODELS = {'resnet18', 'cifarnet'}
MNIST_MODELS  = {'smallnet'}


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--model', default='resnet18', choices=list(MODELS))
    p.add_argument('--ckpt', required=True, help='state_dict .pt file')
    p.add_argument('--source', required=True, help='label written to CSV (e.g. resnet18_fp32)')
    p.add_argument('--ckpt-dtype', default='float32', choices=['float32', 'float64'],
                   help='dtype the checkpoint was saved in')
    p.add_argument('--formats', nargs='+', default=['fp16', 'bf16', 'tf32', 'fp8_e4m3', 'fp8_e5m2'],
                   choices=list(FORMATS))
    p.add_argument('--data-dir', default=None,
                   help='dataset directory (default: dataset/mnist or dataset/cifar10)')
    p.add_argument('--out-dir', default=None,
                   help='output root (default: results/<model>)')
    p.add_argument('--workers', type=int, default=8)
    p.add_argument('--cpu', action='store_true')
    return p.parse_args()


def run_format(model, fmt, test_loader, device):
    torch.backends.cuda.matmul.allow_tf32 = fmt == 'tf32'
    torch.backends.cudnn.allow_tf32      = fmt == 'tf32'

    fp8_dtype  = FORMATS[fmt]
    quant_dtype = None

    if fp8_dtype in _FP8_DTYPES:
        # FP8 is storage-only: compute in FP16, quantize-dequantize weights
        eval_dtype  = torch.float16
        quant_dtype = fp8_dtype
        run_model = copy.deepcopy(model).to(device).to(eval_dtype)
        with torch.no_grad():
            for p in run_model.parameters():
                p.data = p.data.to(fp8_dtype).to(eval_dtype)
    else:
        eval_dtype = fp8_dtype if fmt != 'tf32' else torch.float32
        run_model  = model.to(device).to(eval_dtype)

    val_acc, val_nll = evaluate(run_model, test_loader, device,
                                dtype=eval_dtype, quant_dtype=quant_dtype)
    print(f'  {fmt:12s}  acc={val_acc:.4f}  nll={val_nll:.4f}')
    return val_acc, val_nll


def main():
    args = parse_args()
    device = torch.device('cuda' if not args.cpu and torch.cuda.is_available() else 'cpu')

    out = Path(args.out_dir) if args.out_dir else Path('results') / args.model

    data_dir = args.data_dir
    if data_dir is None:
        data_dir = 'dataset/mnist' if args.model in MNIST_MODELS else 'dataset/cifar10'

    ckpt_dtype = torch.float64 if args.ckpt_dtype == 'float64' else torch.float32
    model = MODELS[args.model]()
    sd = torch.load(args.ckpt, map_location='cpu')
    if ckpt_dtype == torch.float64:
        model = model.double()
    model.load_state_dict(sd)
    model.eval()

    if args.model in MNIST_MODELS:
        _, _, test_loader = mnist_loaders(data_dir, batch_size=512, num_workers=args.workers)
    else:
        _, _, test_loader = cifar10_loaders(data_dir, batch_size=512, num_workers=args.workers)

    out_csv = out / 'logs' / 'inference_results.csv'
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    write_header = not out_csv.exists()

    with open(out_csv, 'a') as f:
        if write_header:
            f.write('source,format,nbits,es,val_acc,val_nll\n')
        for fmt in args.formats:
            acc, nll = run_format(model, fmt, test_loader, device)
            bits = {'fp16': 16, 'bf16': 16, 'tf32': 19, 'fp32': 32, 'fp64': 64,
                    'fp8_e4m3': 8, 'fp8_e5m2': 8}.get(fmt, -1)
            f.write(f'{args.source},{fmt},{bits},,{acc:.6f},{nll:.6f}\n')
            f.flush()

    print(f'Results appended to {out_csv}')


if __name__ == '__main__':
    main()
