#!/usr/bin/env python3
"""
MNIST test-suite evaluation via the FPGA HTTP inference endpoint.

Usage:
    uv run eval.py --checkpoint path/to/ckpt.dat --data-dir path/to/mnist/
    uv run eval.py --checkpoint ckpt.pt --server http://10.42.0.2:8080 --samples 1000

Accepts the same checkpoint formats as the GUI client (.pt or .dat).
Reads raw MNIST IDX files (the same directory used by the resnet project).
"""

import argparse
import csv
import struct
import sys
import time
from pathlib import Path

import numpy as np
import requests

# Reuse encoding and checkpoint loading from the GUI client
from client import float_to_posit32, load_dat, load_pt, weights_to_bytes

# -- MNIST normalization (must match training) ---------------------------------
MNIST_MEAN = 0.1307
MNIST_STD = 0.3081

# -- MNIST IDX loader ----------------------------------------------------------


def _read_idx_images(path: Path) -> np.ndarray:
    """Return (N, 784) float32 array, normalized to MNIST stats."""
    raw = path.read_bytes()
    magic, n, h, w = struct.unpack_from(">IIII", raw, 0)
    if magic != 0x00000803:
        raise ValueError(f"Bad MNIST image magic: {magic:#x}")
    imgs = np.frombuffer(raw, dtype=np.uint8, offset=16).reshape(n, h * w)
    return (imgs.astype(np.float32) / 255.0 - MNIST_MEAN) / MNIST_STD


def _read_idx_labels(path: Path) -> np.ndarray:
    """Return (N,) int32 array of ground-truth labels."""
    raw = path.read_bytes()
    magic, n = struct.unpack_from(">II", raw, 0)
    if magic != 0x00000801:
        raise ValueError(f"Bad MNIST label magic: {magic:#x}")
    return np.frombuffer(raw, dtype=np.uint8, offset=8).astype(np.int32)


def load_mnist_test(data_dir: str):
    """
    Load the MNIST test set from raw IDX files.
    Returns (images [N,784] float32 normalized, labels [N] int32).
    """
    d = Path(data_dir)
    # Support both plain and gzip-decompressed filenames
    img_names = ["t10k-images-idx3-ubyte", "t10k-images.idx3-ubyte"]
    lbl_names = ["t10k-labels-idx1-ubyte", "t10k-labels.idx1-ubyte"]

    img_path = next((d / n for n in img_names if (d / n).exists()), None)
    lbl_path = next((d / n for n in lbl_names if (d / n).exists()), None)

    if img_path is None or lbl_path is None:
        raise FileNotFoundError(
            f"MNIST test files not found in {data_dir}. "
            "Expected: t10k-images-idx3-ubyte, t10k-labels-idx1-ubyte"
        )
    return _read_idx_images(img_path), _read_idx_labels(lbl_path)


# -- evaluation loop -----------------------------------------------------------


def evaluate(
    server: str, images: np.ndarray, labels: np.ndarray, csv_path: str | None = None
) -> dict:
    """
    Run inference on every image and return a dict with accuracy and timing.
    If *csv_path* is given, append per-sample results to that CSV file.
    """
    n = len(labels)
    correct = 0
    latencies = []
    errors = 0

    csv_fh = None
    csv_writer = None
    if csv_path:
        needs_header = not Path(csv_path).exists()
        csv_fh = open(csv_path, "a", newline="")
        csv_writer = csv.writer(csv_fh)
        if needs_header:
            csv_writer.writerow(
                ["sample", "client_lat_ms", "server_lat_ms", "predicted", "actual", "correct"]
            )

    server_latencies = []  # hw time_us from server response

    for i, (img, label) in enumerate(zip(images, labels)):
        # Encode to posit32
        p32 = float_to_posit32(img).tobytes()

        t0 = time.monotonic()
        try:
            r = requests.post(f"{server}/infer", data=p32, timeout=10)
            lat = (time.monotonic() - t0) * 1000  # ms
            r.raise_for_status()
            resp = r.json()
            cls = resp["class"]
            hw_us = resp.get("time_us", None)
        except Exception as e:
            errors += 1
            print(f"\n  Error on sample {i}: {e}", file=sys.stderr)
            if errors > 10:
                print("Too many errors, aborting.", file=sys.stderr)
                break
            continue

        latencies.append(lat)
        if hw_us is not None:
            server_latencies.append(hw_us / 1000)  # convert to ms
        ok = cls == int(label)
        if ok:
            correct += 1

        if csv_writer is not None:
            csv_writer.writerow([i, f"{lat:.3f}",
                                 f"{hw_us / 1000:.3f}" if hw_us is not None else "",
                                 cls, int(label), int(ok)])

        # Progress
        done = len(latencies) + errors
        acc = correct / done if done else 0.0
        c_mean = np.mean(latencies) if latencies else 0.0
        s_mean = np.mean(server_latencies) if server_latencies else 0.0
        print(
            f"\r  [{done:5d}/{n}]  acc={acc:.4f}"
            f"  client={c_mean:.1f} ms  server={s_mean:.1f} ms",
            end="",
            flush=True,
        )

    if csv_fh is not None:
        csv_fh.close()
    print()  # newline after progress

    done = len(latencies) + errors
    lats = np.array(latencies) if latencies else np.array([0.0])
    slats = np.array(server_latencies) if server_latencies else np.array([0.0])
    return {
        "n_total": n,
        "n_done": done,
        "n_errors": errors,
        "correct": correct,
        "accuracy": correct / done if done else 0.0,
        "client_lat_mean": float(np.mean(lats)),
        "client_lat_std": float(np.std(lats)),
        "client_lat_min": float(np.min(lats)),
        "client_lat_max": float(np.max(lats)),
        "client_lat_p95": float(np.percentile(lats, 95)),
        "server_lat_mean": float(np.mean(slats)),
        "server_lat_std": float(np.std(slats)),
        "server_lat_min": float(np.min(slats)),
        "server_lat_max": float(np.max(slats)),
        "server_lat_p95": float(np.percentile(slats, 95)),
        "total_s": float(np.sum(lats) / 1000),
    }


# -- main ----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="Evaluate SmallNet on MNIST via the FPGA HTTP endpoint."
    )
    parser.add_argument(
        "--checkpoint",
        "-c",
        required=True,
        help="Path to .pt (TorchScript/state-dict) or .dat (positnn) checkpoint",
    )
    parser.add_argument(
        "--data-dir",
        "-d",
        required=True,
        help="Directory containing MNIST IDX test files",
    )
    parser.add_argument(
        "--server",
        "-s",
        default="http://10.42.0.2:8080",
        help="Inference server base URL (default: http://10.42.0.2:8080)",
    )
    parser.add_argument(
        "--samples",
        "-n",
        type=int,
        default=None,
        help="Limit evaluation to first N samples",
    )
    parser.add_argument(
        "--skip-upload",
        action="store_true",
        help="Skip weight upload (weights already loaded on server)",
    )
    parser.add_argument(
        "--log-csv",
        type=str,
        default=None,
        help="Append per-sample results (latency, predicted, actual) to CSV file",
    )
    args = parser.parse_args()

    server = args.server.rstrip("/")

    # -- health check ------------------------------------------------------
    print(f"Connecting to {server} ...")
    try:
        requests.get(f"{server}/health", timeout=5).raise_for_status()
    except Exception as e:
        print(f"Server unreachable: {e}", file=sys.stderr)
        sys.exit(1)
    print("Server OK.")

    # -- load and upload weights -------------------------------------------
    if not args.skip_upload:
        ckpt = args.checkpoint
        print(f"Loading checkpoint: {ckpt}")
        t0 = time.monotonic()
        if ckpt.endswith(".dat"):
            weights = load_dat(ckpt)
        else:
            weights = load_pt(ckpt)
        print(f"  Converted in {(time.monotonic() - t0) * 1000:.0f} ms")

        print("Uploading weights ...")
        t0 = time.monotonic()
        r = requests.post(
            f"{server}/weights", data=weights_to_bytes(*weights), timeout=30
        )
        r.raise_for_status()
        print(f"  Uploaded in {(time.monotonic() - t0) * 1000:.0f} ms")

    # -- load MNIST test set -----------------------------------------------
    print(f"Loading MNIST test set from: {args.data_dir}")
    images, labels = load_mnist_test(args.data_dir)
    if args.samples:
        images = images[: args.samples]
        labels = labels[: args.samples]
    print(f"  {len(labels)} samples.")

    # -- run evaluation ----------------------------------------------------
    print("\nRunning inference ...")
    t_wall = time.monotonic()
    stats = evaluate(server, images, labels, csv_path=args.log_csv)
    t_wall = time.monotonic() - t_wall

    # -- results -----------------------------------------------------------
    print()
    print("=" * 58)
    print(f"  Checkpoint : {args.checkpoint}")
    print(
        f"  Samples    : {stats['n_done']} / {stats['n_total']}"
        + (f"  ({stats['n_errors']} errors)" if stats["n_errors"] else "")
    )
    print(
        f"  Accuracy   : {stats['accuracy'] * 100:.2f}%  "
        f"({stats['correct']}/{stats['n_done']})"
    )
    print()
    print(
        f"  Client lat (ms) - mean {stats['client_lat_mean']:.1f} "
        f"+/- {stats['client_lat_std']:.1f}  "
        f"[min {stats['client_lat_min']:.1f}  p95 {stats['client_lat_p95']:.1f}  "
        f"max {stats['client_lat_max']:.1f}]"
    )
    print(
        f"  Server lat (ms) - mean {stats['server_lat_mean']:.1f} "
        f"+/- {stats['server_lat_std']:.1f}  "
        f"[min {stats['server_lat_min']:.1f}  p95 {stats['server_lat_p95']:.1f}  "
        f"max {stats['server_lat_max']:.1f}]"
    )
    print(f"  Total wall time : {t_wall:.1f} s")
    print("=" * 58)


if __name__ == "__main__":
    main()
