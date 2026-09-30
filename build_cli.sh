#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Build the GUI client binaries (Linux + Windows).
#   ./build_cli.sh                 # no OCR (original behavior)
#   ./build_cli.sh --with-ocr      # Linux GUI with OCR (needs OpenCV + onnxruntime)
#
# Windows OCR requires Windows onnxruntime/OpenCV libs (not yet vendored),
# so the Windows build always uses -tags noocr (OCR checkbox disabled).
# ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="pdf2docx_build:1.0"

# ── Usage ───────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
用法: ./build_cli.sh [参数...]

参数说明:
  --with-ocr              构建带 OCR 支持的 Linux GUI（需要 OpenCV + onnxruntime，
                          使用 Dockerfile.dev 镜像）
  --no-obfuscate          关闭 garble 代码混淆（默认开启）
  -x | verbose            输出 go build 的详细编译日志（-x）
  -h | --help             显示本帮助并退出

代理参数（可选，均不带 = 时也会继承环境变量）:
  http_proxy=<url>        设置 HTTP 代理
  https_proxy=<url>       设置 HTTPS 代理
  no_proxy=<url>          设置不走代理的地址列表

示例:
  ./build_cli.sh                  # 默认构建（无 OCR，开启混淆）
  ./build_cli.sh --with-ocr       # 构建带 OCR 的 Linux GUI
  ./build_cli.sh --with-ocr -x    # 带 OCR 且输出详细编译日志
  ./build_cli.sh --no-obfuscate   # 不混淆构建

说明:
  Windows 构建始终使用 -tags noocr（尚未内置 Windows 的 onnxruntime/OpenCV 库），
  因此 --with-ocr 只影响 Linux GUI，Windows 版 OCR 复选框始终禁用。
EOF
}

# ── Optional proxy ──────────────────────────────────────────────
HTTP_PROXY_VAL=""
HTTPS_PROXY_VAL=""
NO_PROXY_VAL=""
GO_BUILD_X=""   # set to "-x" when verbose is requested
OBFUSCATE=true
WITH_OCR=false
for arg in "$@"; do
  case "$arg" in
    http_proxy=*|HTTP_PROXY=*)   HTTP_PROXY_VAL="${arg#*=}" ;;
    https_proxy=*|HTTPS_PROXY=*) HTTPS_PROXY_VAL="${arg#*=}" ;;
    no_proxy=*|NO_PROXY=*)       NO_PROXY_VAL="${arg#*=}" ;;
    -x|verbose)                  GO_BUILD_X="-x" ;;
    --no-obfuscate)              OBFUSCATE=false ;;
    --with-ocr)                  WITH_OCR=true ;;
    -h|--help|help)              usage; exit 0 ;;
    *)                           echo "WARNING: 未知参数 '$arg'，已忽略（用 -h 查看用法）" ;;
  esac
done

# 打印参数用法说明，便于在日志里看到各参数含义
if [[ -t 1 ]]; then
  usage
fi

# ── 总是输出当前构建参数（日志中可见） ────────────────────────────
echo ""
echo "────────────────────────────────────────────────────────"
echo "  构建参数说明:"
echo "    --with-ocr         构建带 OCR 支持的 Linux GUI"
echo "                       需要 OpenCV + onnxruntime (Dockerfile.dev)"
echo "    --no-obfuscate     关闭 garble 代码混淆（默认开启混淆）"
echo "    -x | verbose       输出 go build 详细编译日志"
echo "    -h | --help        显示帮助并退出"
echo "    http_proxy=<url>   设置 HTTP 代理"
echo "    https_proxy=<url>  设置 HTTPS 代理"
echo "    no_proxy=<url>     设置不走代理的地址列表"
echo "────────────────────────────────────────────────────────"
echo "  当前参数:"
echo "    WITH_OCR       = $WITH_OCR"
echo "    OBFUSCATE      = $OBFUSCATE"
echo "    GO_BUILD_X     = ${GO_BUILD_X:-(未设置)}"
echo "    HTTP_PROXY     = ${HTTP_PROXY_VAL:-(未设置)}"
echo "    HTTPS_PROXY    = ${HTTPS_PROXY_VAL:-(未设置)}"
echo "────────────────────────────────────────────────────────"
echo ""
HTTP_PROXY_VAL="${HTTP_PROXY_VAL:-${HTTP_PROXY:-${http_proxy:-}}}"
HTTPS_PROXY_VAL="${HTTPS_PROXY_VAL:-${HTTPS_PROXY:-${https_proxy:-}}}"
NO_PROXY_VAL="${NO_PROXY_VAL:-${NO_PROXY:-${no_proxy:-}}}"

add_scheme() { local v="$1"; [[ -z "$v" || "$v" == *"://"* ]] && { printf '%s' "$v"; return; }; printf 'http://%s' "$v"; }
HTTP_PROXY_VAL="$(add_scheme "$HTTP_PROXY_VAL")"
HTTPS_PROXY_VAL="$(add_scheme "$HTTPS_PROXY_VAL")"

DOCKER_BUILD_ARGS=()
DOCKER_RUN_ENV=()
if [[ -n "$HTTP_PROXY_VAL" || -n "$HTTPS_PROXY_VAL" ]]; then
  export HTTP_PROXY="$HTTP_PROXY_VAL" HTTPS_PROXY="$HTTPS_PROXY_VAL"
  export http_proxy="$HTTP_PROXY_VAL" https_proxy="$HTTPS_PROXY_VAL"
  export NO_PROXY="$NO_PROXY_VAL"     no_proxy="$NO_PROXY_VAL"
  DOCKER_BUILD_ARGS=(--build-arg "HTTP_PROXY=$HTTP_PROXY_VAL" --build-arg "HTTPS_PROXY=$HTTPS_PROXY_VAL" --build-arg "NO_PROXY=$NO_PROXY_VAL")
  DOCKER_RUN_ENV=(-e "HTTP_PROXY=$HTTP_PROXY_VAL" -e "HTTPS_PROXY=$HTTPS_PROXY_VAL" -e "NO_PROXY=$NO_PROXY_VAL" -e "http_proxy=$HTTP_PROXY_VAL" -e "https_proxy=$HTTPS_PROXY_VAL" -e "no_proxy=$NO_PROXY_VAL")
fi

cd "$SCRIPT_DIR"

if [[ ! -f "main.go" ]] || [[ ! -f "go.mod" ]]; then
  echo "ERROR: run this script from the pdf2docx directory"
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "ERROR: docker not found"
  exit 1
fi

# ── Cache directories (mapped as volumes for speed) ──────────────
GOCACHE_DIR="$SCRIPT_DIR/build/gocache"
GOMODCACHE_DIR="$SCRIPT_DIR/build/gomodcache"
mkdir -p "$GOCACHE_DIR" "$GOMODCACHE_DIR" "$SCRIPT_DIR/dist"

# ── Go toolchain tarball (download if missing) ───────────────────
GO_VERSION="1.24.13"
GO_TARBALL="$SCRIPT_DIR/build/deps/go${GO_VERSION}.linux-amd64.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"

if [[ ! -f "$GO_TARBALL" ]]; then
  mkdir -p "$(dirname "$GO_TARBALL")"
  echo "Downloading Go ${GO_VERSION} toolchain ..."
  if command -v curl &>/dev/null; then
    curl -fL --retry 3 -o "$GO_TARBALL" "$GO_DOWNLOAD_URL"
  elif command -v wget &>/dev/null; then
    wget -O "$GO_TARBALL" "$GO_DOWNLOAD_URL"
  else
    echo "ERROR: neither curl nor wget found; cannot download Go toolchain"
    exit 1
  fi
  echo "Go toolchain saved to $GO_TARBALL"
else
  echo "Go toolchain tarball ready: $GO_TARBALL"
fi

# ── Build Docker image if missing ────────────────────────────────
# When obfuscating or OCR is requested, rebuild the image.
NEEDS_REBUILD=false
if $WITH_OCR; then
  # OCR build needs the dev image (includes opencv + g++)
  IMAGE="pdf2docx_dev:latest"
  if ! docker image inspect "$IMAGE" &>/dev/null; then
    echo "Building dev image $IMAGE ..."
    docker build "${DOCKER_BUILD_ARGS[@]}" -t "$IMAGE" -f Dockerfile.dev .
    echo "Done."
  fi
elif ! docker image inspect "$IMAGE" &>/dev/null; then
  NEEDS_REBUILD=true
elif $OBFUSCATE && ! docker run --rm "$IMAGE" command -v garble &>/dev/null; then
  NEEDS_REBUILD=true
fi

if $NEEDS_REBUILD; then
  echo "Building Docker image $IMAGE ..."
  docker build "${DOCKER_BUILD_ARGS[@]}" --build-arg "GO_VERSION=$GO_VERSION" -t "$IMAGE" -f Dockerfile .
  echo "Docker image $IMAGE built"
else
  echo "Docker image $IMAGE ready"
fi

COMMON_ENV=(
  -e GOFLAGS="-buildvcs=false"
  -e GOCACHE=/tmp/gocache
  -e GOMODCACHE=/go/pkg/mod
  -e GOPROXY="https://goproxy.cn,direct"
  -e HOST_UID="$(id -u)"
  -e HOST_GID="$(id -g)"
)

# ── Obfuscation toggle ────────────────────────────────────────────
if $OBFUSCATE && ! $WITH_OCR; then
  BUILD_BIN="garble -literals"
  GARBLE_ENV=(-e GOGARBLE=pdftoword)
  OBF_LABEL=" (obfuscated)"
else
  BUILD_BIN="go"
  GARBLE_ENV=()
  OBF_LABEL=""
fi

# ── OCR tags (Linux only) ────────────────────────────────────────
LINUX_OCR_TAGS=""
if $WITH_OCR; then
  LINUX_OCR_TAGS=""
  LINUX_OBF=""
else
  LINUX_OCR_TAGS="-tags noocr"
  LINUX_OBF=""
fi

# ── 1. Linux GUI ─────────────────────────────────────────────────
echo ""
echo "=== Building pdf2docx (Linux GUI)${OBF_LABEL} ==="
# Clean dist/ and build, all inside Docker (avoids root-ownership issues).
docker run --rm \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  "${COMMON_ENV[@]}" \
  ${DOCKER_RUN_ENV[@]+"${DOCKER_RUN_ENV[@]}"} \
  ${GARBLE_ENV[@]+"${GARBLE_ENV[@]}"} \
  -e CGO_ENABLED=1 \
  -e GOOS=linux \
  -e GOARCH=amd64 \
  "$IMAGE" \
  bash -c "
    rm -rf /workspace/dist/*
    mkdir -p /workspace/dist
    ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod ${LINUX_OCR_TAGS} -ldflags='-s -w' -o dist/pdf2docx . && \
    chown \$HOST_UID:\$HOST_GID dist/pdf2docx
  "

# Bundle libonnxruntime.so + OpenCV libs + models for OCR builds.
# dist/ was cleared inside Docker above, so there are no stale root-owned files.
if $WITH_OCR; then
  # Copy onnxruntime from vendored deps (done on host, dist/ is now clean and writable).
  cp "$SCRIPT_DIR/build/deps/onnxruntime/lib/libonnxruntime.so" "$SCRIPT_DIR/dist/libonnxruntime.so"
  echo "  bundled:  dist/libonnxruntime.so"

  # Copy OpenCV shared libs (and tbb, their only host-missing dep) from the
  # dev image into dist/. The binary is linked with -Wl,-rpath,'$ORIGIN' so it
  # finds them next to itself; the copied .so files get the same rpath so their
  # own transitive deps (e.g. libtbb) also resolve from dist/.
  docker run --rm -v "$SCRIPT_DIR":/workspace -w /workspace \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    "$IMAGE" bash -c '
    set -euo pipefail
    LIBDIR=/usr/lib/x86_64-linux-gnu
    mkdir -p /workspace/dist
    for lib in libopencv_imgproc.so.406 libopencv_core.so.406 libtbb.so.12; do
      cp -L "$LIBDIR/$lib" /workspace/dist/
      patchelf --set-rpath "\$ORIGIN" "/workspace/dist/$lib"
      echo "  bundled:  dist/$lib"
    done
    chown "$HOST_UID":"$HOST_GID" /workspace/dist/libopencv_*.so.406 /workspace/dist/libtbb.so.12
  '

  # Copy OCR model files so the GUI can find them at runtime.
  cp -r "$SCRIPT_DIR/models" "$SCRIPT_DIR/dist/models"
  echo "  bundled:  dist/models/"
fi

# ── 2. Windows GUI ───────────────────────────────────────────────
echo ""
echo "=== Building pdf2docx.exe (Windows GUI)${OBF_LABEL} ==="
# Windows always builds without OCR (no vendored win deps yet).
docker run --rm \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  "${COMMON_ENV[@]}" \
  ${DOCKER_RUN_ENV[@]+"${DOCKER_RUN_ENV[@]}"} \
  ${GARBLE_ENV[@]+"${GARBLE_ENV[@]}"} \
  -e CGO_ENABLED=1 \
  -e GOOS=windows \
  -e GOARCH=amd64 \
  -e CC=x86_64-w64-mingw32-gcc \
  -e CGO_LDFLAGS="-lucrt" \
  "$IMAGE" \
  bash -c "
    rm -rf /workspace/dist/pdf2docx.exe
    ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod -tags noocr -ldflags='-s -w -H windowsgui' -o dist/pdf2docx.exe . && \
    chown \$HOST_UID:\$HOST_GID dist/pdf2docx.exe
  "

echo ""
echo "=== Build complete ==="
echo "  Linux GUI:    dist/pdf2docx      ($(du -h "$SCRIPT_DIR/dist/pdf2docx" | cut -f1))"
echo "  Windows GUI:  dist/pdf2docx.exe  ($(du -h "$SCRIPT_DIR/dist/pdf2docx.exe" | cut -f1))"

# ── Package into tar for distribution ─────────────────────────────
echo ""
echo "--- Packaging ---"
ARCHIVE_LINUX="pdf2docx-linux-amd64.tar"
ARCHIVE_WIN="pdf2docx-windows-amd64.tar"

rm -f "$SCRIPT_DIR/dist/$ARCHIVE_LINUX" "$SCRIPT_DIR/dist/$ARCHIVE_WIN"

if $WITH_OCR; then
  cd "$SCRIPT_DIR/dist"
  tar -cf "$ARCHIVE_LINUX" --transform='s,^,pdf2docx-linux-amd64/,' \
    pdf2docx \
    libonnxruntime.so \
    libopencv_imgproc.so.406 libopencv_core.so.406 libtbb.so.12 \
    models/
  cd "$SCRIPT_DIR"
  echo "  $ARCHIVE_LINUX  ($(du -h "$SCRIPT_DIR/dist/$ARCHIVE_LINUX" | cut -f1)) — Linux OCR 完整包"

  # Remove loose files, keep only the tar.
  rm -rf \
    "$SCRIPT_DIR/dist/pdf2docx" \
    "$SCRIPT_DIR/dist/libonnxruntime.so" \
    "$SCRIPT_DIR/dist/libopencv_imgproc.so.406" "$SCRIPT_DIR/dist/libopencv_core.so.406" \
    "$SCRIPT_DIR/dist/libtbb.so.12" \
    "$SCRIPT_DIR/dist/models"
else
  cd "$SCRIPT_DIR/dist"
  tar -cf "$ARCHIVE_LINUX" --transform='s,^,pdf2docx-linux-amd64/,' pdf2docx
  cd "$SCRIPT_DIR"
  echo "  $ARCHIVE_LINUX  ($(du -h "$SCRIPT_DIR/dist/$ARCHIVE_LINUX" | cut -f1))"

  rm -f "$SCRIPT_DIR/dist/pdf2docx"
fi

cd "$SCRIPT_DIR/dist"
tar -cf "$ARCHIVE_WIN" --transform='s,^,pdf2docx-windows-amd64/,' pdf2docx.exe
cd "$SCRIPT_DIR"
echo "  $ARCHIVE_WIN  ($(du -h "$SCRIPT_DIR/dist/$ARCHIVE_WIN" | cut -f1))"
rm -f "$SCRIPT_DIR/dist/pdf2docx.exe"

echo ""
echo "分发文件（做好了的压缩包）:"
echo "  dist/$ARCHIVE_LINUX"
echo "  dist/$ARCHIVE_WIN"
echo ""
if $WITH_OCR; then
  echo "Linux OCR 包内容: pdf2docx + .so 库 + models/ 模型目录"
  echo "解包后进入 pdf2docx-linux-amd64/ 目录，运行 ./pdf2docx 即可使用 OCR。"
else
  echo "Linux 包内容: pdf2docx（独立静态文件，无需额外依赖）"
fi
