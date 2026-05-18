# FPGA SmallNet Inference Server & Client

Runs SmallNet digit recognition on the PAWN posit accelerator (Zedboard).
The server exposes an HTTP API; the client captures webcam frames and sends them for inference.

## Build

```sh
./build.sh
```

Requires:
- `arm-linux-gnueabihf-gcc` for the server (cross-compile)
- `g++` with C++20 support for `client/posit_convert.so`
- `uv` for the Python client venv

To build the server natively on the board: `make -C server CROSS=""`

The posit conversion library (`client/posit_convert.so`) is built against the
stillwater/universal headers in `../spike-xposit/universal/include` and must be
rebuilt whenever that path changes. Run `make -C client` to rebuild it manually.

## Server (FPGA)

Copy `server/server` to the Zedboard and run:

```sh
./server [port]          # default port 8080
```

The PAWN bitstream must already be loaded. Programs (GEMM + bias + ReLU kernels)
are compiled once at startup and reused across all inference calls.

## Client (host)

```sh
cd client
uv run client.py
```

1. Enter the server URL (default `http://10.42.0.2:8080`).
2. Click **Upload Weights** and select a checkpoint:
   - `.pt` - TorchScript or state-dict float32 (converted to posit32 on the fly)
   - `.dat` - posit-native checkpoint from positnn
3. Click **Start** to begin webcam capture and live inference.

The "What model sees" panel shows the 28×28 grayscale crop sent to the model.

## MNIST evaluation

Run the full test suite through the HTTP endpoint and report accuracy + latency:

```sh
cd client
uv run eval.py --checkpoint ../../resnet/results/smallnet/checkpoints/ckpt_smallnet.pt \
               --data-dir ../../resnet/dataset/mnist
```

Options:
- `--samples N` - limit to the first N images (quick sanity check)
- `--skip-upload` - skip weight upload if already loaded on the server
- `--server URL` - override server address
- `--log-csv FILE` - append per-sample latency, predicted and actual label to a CSV file

## HTTP API

| Method | Path       | Body                          | Response                          |
|--------|------------|-------------------------------|-----------------------------------|
| GET    | /health    | –                             | `{"status":"ok"}`                 |
| POST   | /weights   | uint32\[25450\] posit32 LE    | `{"status":"ok"}`                 |
| POST   | /infer     | uint32\[784\] posit32 LE      | `{"class":N,"time_us":T}`         |

Weight layout: `fc1_weight[32×784]`, `fc1_bias[32]`, `fc2_weight[10×32]`, `fc2_bias[10]`,
all row-major (output neuron first).
