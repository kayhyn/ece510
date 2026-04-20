#!/usr/bin/env bash
# Profile gemm_naive and gemm_tiled with Nsight Compute.
# Produces ncu_{naive,tiled}.ncu-rep (binary) and ncu_{naive,tiled}.log (text).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/../cuda"

for k in naive tiled; do
  ncu --set full \
      --export  "$SCRIPT_DIR/ncu_${k}" \
      --force-overwrite \
      "$BIN_DIR/gemm_${k}" | tee "$SCRIPT_DIR/ncu_${k}.log"
done

echo "Open reports with: ncu-ui $SCRIPT_DIR/ncu_naive.ncu-rep"
