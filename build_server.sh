#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Build the headless HTTP server binary (Linux, with OCR).
#   ./build_server.sh                 # build server binary + bundle deps
#   ./build_server.sh --docker        # build a production Docker image
#
# The server binary is dynamically linked and requires:
#   - libopencv_core + libopencv_imgproc (from libopencv-dev)
#   - libonnxruntime.so (vendored in build/deps/onnxruntime/lib/)
# ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Usage ───────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
用法: ./build_server.sh [参数...]

参数说明:
  --docker           构建生产 Docker 镜像（推荐部署方式）
  --no-obfuscate     关闭 garble 代码混淆（默认开启）
  -x | verbose       输出 go build 的详细编译日志（-x）
  -h | --help        显示本帮助并退出

示例:
  ./build_server.sh                  # 构建二进制 + 依赖到 dist/
  ./build_server.sh --docker         # 构建 Docker 镜像 pdf2docx-server:latest
  ./build_server.sh --docker -x      # 详细日志 + Docker 镜像

说明:
  Server 始终以 CGO 编译，集成 OCR 支持（PaddleOCR + MuPDF）。
  Docker 镜像是推荐部署方式，开箱即用。
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
OBFUSCATE=true
BUILD_DOCKER=false
for arg in "$@"; do
  case "$arg" in
    -x|verbose)      GO_BUILD_X="-x" ;;
    --no-obfuscate)  OBFUSCATE=false ;;
    --docker)        BUILD_DOCKER=true ;;
    -h|--help|help)  usage; exit 0 ;;
    *)               echo "WARNING: 未知参数 '$arg'，已忽略（用 -h 查看用法）" ;;
  esac
done

# Print usage on interactive terminal.
if [[ -t 1 ]]; then
  usage
fi

echo ""
echo "────────────────────────────────────────────────────────"
echo "  构建参数:"
echo "    BUILD_DOCKER  = $BUILD_DOCKER"
echo "    OBFUSCATE     = $OBFUSCATE"
echo "    GO_BUILD_X    = ${GO_BUILD_X:-(未设置)}"
echo "────────────────────────────────────────────────────────"
echo ""

# ── Build image must exist ──────────────────────────────────────
IMAGE="pdf2docx_dev:latest"
if ! docker image inspect "$IMAGE" &>/dev/null; then
  echo "Building dev image $IMAGE ..."
  docker build -t "$IMAGE" -f Dockerfile.dev .
  echo "Done."
fi

# ── Persistent Go caches (like voice_note pattern) ──────────────
GOCACHE_DIR="$SCRIPT_DIR/build/gocache_dev"
GOMODCACHE_DIR="$SCRIPT_DIR/build/gomodcache"
mkdir -p "$GOCACHE_DIR" "$GOMODCACHE_DIR" "$SCRIPT_DIR/dist"

ONNXRT_LIB="$SCRIPT_DIR/build/deps/onnxruntime"

COMMON_ENV=(
  -e GOFLAGS="-buildvcs=false"
  -e GOCACHE=/tmp/gocache
  -e GOMODCACHE=/go/pkg/mod
  -e GOPROXY="https://goproxy.cn,direct"
  -e CGO_ENABLED=1
  -e CGO_LDFLAGS="-L/workspace/build/deps/onnxruntime/lib -lonnxruntime"
  -e CGO_CFLAGS="-I/workspace/build/deps/onnxruntime/include"
)

# ── Build binary ─────────────────────────────────────────────────
echo ""
echo "=== Building pdf2docx-server ==="
docker run --rm \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  "${COMMON_ENV[@]}" \
  -e GOOS=linux \
  -e GOARCH=amd64 \
  "$IMAGE" \
  bash -c "
    rm -rf /workspace/dist/pdf2docx-server
    go build ${GO_BUILD_X} -mod=mod -ldflags='-s -w -r \$ORIGIN' -o dist/pdf2docx-server ./cmd/server/ && \
    echo 'Build complete.'
  "

echo "  dist/pdf2docx-server ($(du -h "$SCRIPT_DIR/dist/pdf2docx-server" | cut -f1))"

# ── Bundle runtime deps ──────────────────────────────────────────
rm -rf "$SCRIPT_DIR/dist/libonnxruntime.so" "$SCRIPT_DIR/dist/models"

cp "$ONNXRT_LIB/lib/libonnxruntime.so" "$SCRIPT_DIR/dist/libonnxruntime.so"
echo "  bundled: dist/libonnxruntime.so"

cp -r "$SCRIPT_DIR/models" "$SCRIPT_DIR/dist/models"
echo "  bundled: dist/models/"

# ── Docker image (if requested) ──────────────────────────────────
if $BUILD_DOCKER; then
  # Dockerfile.server COPYs from dist/ — make sure the binary is present
  # (built above). Guard against someone running `docker build` directly
  # with an empty dist/.
  if [[ ! -f "$SCRIPT_DIR/dist/pdf2docx-server" ]]; then
    echo "ERROR: dist/pdf2docx-server not found." >&2
    echo "       Run './build_server.sh' first to build the binary." >&2
    exit 1
  fi

  echo ""
  echo "=== Building Docker image pdf2docx-server:latest ==="
  docker build -t pdf2docx-server:latest -f Dockerfile.server "$SCRIPT_DIR"
  echo ""
  echo "=== Docker image built ==="
  echo "  pdf2docx-server:latest"
  echo ""
  echo "Run with:"
  echo "  docker run -p 8080:8080 pdf2docx-server:latest"
  exit 0
fi

# ── Package tar ──────────────────────────────────────────────────
echo ""
echo "--- Packaging ---"
ARCHIVE="pdf2docx-server-linux-amd64.tar"
rm -f "$SCRIPT_DIR/dist/$ARCHIVE"
cd "$SCRIPT_DIR/dist"
tar -cf "$ARCHIVE" --transform='s,^,pdf2docx-server-linux-amd64/,' pdf2docx-server libonnxruntime.so models/
cd "$SCRIPT_DIR"
echo "  $ARCHIVE  ($(du -h "$SCRIPT_DIR/dist/$ARCHIVE" | cut -f1))"

# Clean up loose files.
rm -rf "$SCRIPT_DIR/dist/pdf2docx-server" "$SCRIPT_DIR/dist/libonnxruntime.so" "$SCRIPT_DIR/dist/models"

echo ""
echo "分发文件:"
echo "  dist/$ARCHIVE"
echo ""
echo "部署: 解包后进入 pdf2docx-server-linux-amd64/，运行 ./pdf2docx-server"
echo "目标主机需安装: libopencv_core + libopencv_imgproc (libopencv-dev)"