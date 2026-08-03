#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MNN_VERSION="3.5.0"
WORK_DIR="$(mktemp -d /tmp/aicamera-mnn-convert-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

git clone --depth 1 --branch "$MNN_VERSION" \
  https://github.com/alibaba/MNN.git "$WORK_DIR/MNN"
cmake -S "$WORK_DIR/MNN" -B "$WORK_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DMNN_BUILD_SHARED_LIBS=OFF \
  -DMNN_BUILD_CONVERTER=ON \
  -DMNN_BUILD_TOOLS=OFF \
  -DMNN_BUILD_TEST=OFF \
  -DMNN_BUILD_BENCHMARK=OFF
cmake --build "$WORK_DIR/build" --target MNNConvert -j2
"$WORK_DIR/build/MNNConvert" \
  -f TFLITE \
  --modelFile "$PROJECT_DIR/assets/models/yolov8n_320.tflite" \
  --MNNModel "$PROJECT_DIR/assets/models/yolov8n_320.mnn" \
  --bizCode AICAMERA

sha256sum "$PROJECT_DIR/assets/models/yolov8n_320.mnn"
