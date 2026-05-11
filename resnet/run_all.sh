#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

bash scripts/run_resnet.sh
bash scripts/run_cifarnet.sh
bash scripts/run_smallnet.sh
