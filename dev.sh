#!/usr/bin/env bash
# Launch a dev container for OCR development.
# Maps the project directory into /workspace, same as build_cli.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
IMAGE="pdf2docx_dev:latest"

# Build dev image if not present
if ! docker image inspect "$IMAGE" &>/dev/null; then
  echo "Building dev image $IMAGE ..."
  docker build -t "$IMAGE" -f Dockerfile.dev .
  echo "Done."
fi

GOCACHE_DIR="$SCRIPT_DIR/build/gocache_dev"
GOMODCACHE_DIR="$SCRIPT_DIR/build/gomodcache"
mkdir -p "$GOCACHE_DIR" "$GOMODCACHE_DIR"

echo "Starting dev container. Use 'go build' or 'go test' inside."
echo "  CGO LDFLAGS:  -L/workspace/build/deps/onnxruntime/lib -lonnxruntime"
echo "  CGO CFLAGS:   -I/workspace/build/deps/onnxruntime/include"
echo "  OpenCV:       pkg-config --cflags --libs opencv4"
echo ""

docker run --rm -it \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  -e GOCACHE=/tmp/gocache \
  -e GOMODCACHE=/go/pkg/mod \
  -e GOPROXY=https://goproxy.cn,direct \
  "$IMAGE" \
  bash