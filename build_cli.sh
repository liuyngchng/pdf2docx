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
    *) ;;
  esac
done
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
    ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod ${LINUX_OCR_TAGS} -ldflags='-s -w' -o dist/pdf2docx . && \
    chown \$HOST_UID:\$HOST_GID dist/pdf2docx
  "

# Bundle libonnxruntime.so + OpenCV libs for OCR builds.
if $WITH_OCR; then
  cp "$SCRIPT_DIR/build/deps/onnxruntime/lib/libonnxruntime.so" "$SCRIPT_DIR/dist/libonnxruntime.so"
  echo "  bundled:  dist/libonnxruntime.so"

  # Copy OpenCV shared libs (and tbb, their only host-missing dep) from the
  # dev image into dist/. The binary is linked with -Wl,-rpath,'$ORIGIN' so it
  # finds them next to itself; the copied .so files get the same rpath so their
  # own transitive deps (e.g. libtbb) also resolve from dist/.
  docker run --rm -v "$SCRIPT_DIR":/workspace -w /workspace "$IMAGE" bash -c '
    set -euo pipefail
    LIBDIR=/usr/lib/x86_64-linux-gnu
    mkdir -p /workspace/dist
    for lib in libopencv_imgproc.so.406 libopencv_core.so.406 libtbb.so.12; do
      cp -L "$LIBDIR/$lib" /workspace/dist/
      patchelf --set-rpath "\$ORIGIN" "/workspace/dist/$lib"
      echo "  bundled:  dist/$lib"
    done
    chown "$(id -u)":"$(id -g)" /workspace/dist/libopencv_*.so.406 /workspace/dist/libtbb.so.12
  '
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
    ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod -tags noocr -ldflags='-s -w -H windowsgui' -o dist/pdf2docx.exe . && \
    chown \$HOST_UID:\$HOST_GID dist/pdf2docx.exe
  "

echo ""
echo "=== Build complete ==="
echo "  Linux GUI:    dist/pdf2docx      ($(du -h "$SCRIPT_DIR/dist/pdf2docx" | cut -f1))"
echo "  Windows GUI:  dist/pdf2docx.exe  ($(du -h "$SCRIPT_DIR/dist/pdf2docx.exe" | cut -f1))"
echo ""
echo "Both are standalone; no external DLLs / .so required."
