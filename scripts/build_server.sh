#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Build the production Docker image for the headless HTTP server.
#   ./scripts/build_server.sh
#
# The server binary is compiled inside the build container, then
# packaged into a slim production image (ubuntu:24.04 + OpenCV libs).
# ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Usage ───────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
用法: ./scripts/build_server.sh [参数...]

参数说明:
  -x | verbose       输出 go build 的详细编译日志（-x）
  -h | --help        显示本帮助并退出

说明:
  直接构建生产 Docker 镜像 pdf2docx-server:latest（Server 始终集成 OCR）。
EOF
}

cd "$SCRIPT_DIR"

if [[ ! -f "go.mod" ]]; then
  echo "ERROR: run this script from the pdf2docx directory"
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found"
  exit 1
fi

GO_BUILD_X=""
for arg in "$@"; do
  case "$arg" in
    -x|verbose)      GO_BUILD_X="-x" ;;
    -h|--help|help)  usage; exit 0 ;;
    *)               echo "WARNING: 未知参数 '$arg'，已忽略（用 -h 查看用法）" ;;
  esac
done

if [[ -t 1 ]]; then
  usage
fi

# ── Build image must exist ──────────────────────────────────────
IMAGE="pdf2docx_build:latest"
if ! docker image inspect "$IMAGE" &>/dev/null; then
  echo "Building image $IMAGE ..."
  docker build -t "$IMAGE" -f scripts/Dockerfile .
  echo "Done."
fi

# ── Persistent Go caches ────────────────────────────────────────
GOCACHE_DIR="$SCRIPT_DIR/build/gocache_dev"
GOMODCACHE_DIR="$SCRIPT_DIR/build/gomodcache"
mkdir -p "$GOCACHE_DIR" "$GOMODCACHE_DIR" "$SCRIPT_DIR/dist"

ONNXRT_LIB="$SCRIPT_DIR/build/deps/onnxruntime"

# ── 1. Build binary in build container ─────────────────────────
echo ""
echo "=== Step 1/2: Building pdf2docx-server binary ==="
docker run --rm \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  -e GOFLAGS="-buildvcs=false" \
  -e GOCACHE=/tmp/gocache \
  -e GOMODCACHE=/go/pkg/mod \
  -e GOPROXY="https://goproxy.cn,direct" \
  -e CGO_ENABLED=1 \
  -e CGO_LDFLAGS="-L/workspace/build/deps/onnxruntime/lib -lonnxruntime" \
  -e CGO_CFLAGS="-I/workspace/build/deps/onnxruntime/include" \
  -e GOOS=linux \
  -e GOARCH=amd64 \
  "$IMAGE" \
  bash -c "
    rm -rf /workspace/dist/pdf2docx-server
    go build ${GO_BUILD_X} -mod=mod -ldflags='-s -w -r \$ORIGIN' -o dist/pdf2docx-server ./cmd/server/ && \
    echo 'Build complete.'
  "

echo "  dist/pdf2docx-server ($(du -h "$SCRIPT_DIR/dist/pdf2docx-server" | cut -f1))"

# ── 2. Bundle deps + package Docker image ───────────────────────
rm -rf "$SCRIPT_DIR/dist/libonnxruntime.so" "$SCRIPT_DIR/dist/models"

cp "$ONNXRT_LIB/lib/libonnxruntime.so" "$SCRIPT_DIR/dist/libonnxruntime.so"
cp -r "$SCRIPT_DIR/models" "$SCRIPT_DIR/dist/models"

echo ""
echo "=== Step 2/2: Building Docker image pdf2docx-server:latest ==="
docker build -t pdf2docx-server:latest -f scripts/Dockerfile.server "$SCRIPT_DIR"

# Clean up intermediate files from dist/.
rm -rf "$SCRIPT_DIR/dist/pdf2docx-server" "$SCRIPT_DIR/dist/libonnxruntime.so" "$SCRIPT_DIR/dist/models"

echo ""
echo "=== Done ==="
echo "  Docker image: pdf2docx-server:latest"
echo ""
echo "Run with:"
echo "  docker run -p 8080:8080 pdf2docx-server:latest"