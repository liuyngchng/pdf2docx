#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="pdf2docx_build:1.0"

# ── Optional proxy ──────────────────────────────────────────────
HTTP_PROXY_VAL=""
HTTPS_PROXY_VAL=""
NO_PROXY_VAL=""
GO_BUILD_X=""   # set to "-x" when verbose is requested
for arg in "$@"; do
  case "$arg" in
    http_proxy=*|HTTP_PROXY=*)   HTTP_PROXY_VAL="${arg#*=}" ;;
    https_proxy=*|HTTPS_PROXY=*) HTTPS_PROXY_VAL="${arg#*=}" ;;
    no_proxy=*|NO_PROXY=*)       NO_PROXY_VAL="${arg#*=}" ;;
    -x|verbose)                  GO_BUILD_X="-x" ;;
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

# ── Build Docker image if go.mod changed ─────────────────────────
# docker build cache handles unchanged layers (base stays cached).
if ! docker image inspect "$IMAGE" &>/dev/null; then
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
  -e CGO_ENABLED=1
  -e HOST_UID="$(id -u)"
  -e HOST_GID="$(id -g)"
)

# ── 1. Linux binary ─────────────────────────────────────────────
echo ""
echo "=== Building pdf2docx (Linux) ==="
docker run --rm \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  "${COMMON_ENV[@]}" \
  ${DOCKER_RUN_ENV[@]+"${DOCKER_RUN_ENV[@]}"} \
  -e GOOS=linux \
  -e GOARCH=amd64 \
  "$IMAGE" \
  bash -c "
    go build ${GO_BUILD_X} -mod=mod -ldflags='-s -w' -o dist/pdf2docx . && \
    chown \$HOST_UID:\$HOST_GID dist/pdf2docx
  "

# ── 2. Windows .exe ─────────────────────────────────────────────
echo ""
echo "=== Building pdf2docx.exe (Windows) ==="
docker run --rm \
  -v "$SCRIPT_DIR":/workspace \
  -v "$GOCACHE_DIR":/tmp/gocache \
  -v "$GOMODCACHE_DIR":/go/pkg/mod \
  -w /workspace \
  "${COMMON_ENV[@]}" \
  ${DOCKER_RUN_ENV[@]+"${DOCKER_RUN_ENV[@]}"} \
  -e GOOS=windows \
  -e GOARCH=amd64 \
  -e CC=x86_64-w64-mingw32-gcc \
	  -e CGO_LDFLAGS="-lucrt" \
  "$IMAGE" \
  bash -c "
    go build ${GO_BUILD_X} -mod=mod -ldflags='-s -w -H windowsgui' -o dist/pdf2docx.exe . && \
    chown \$HOST_UID:\$HOST_GID dist/pdf2docx.exe
  "

echo ""
echo "=== Build complete ==="
echo "  Linux:   dist/pdf2docx    ($(du -h "$SCRIPT_DIR/dist/pdf2docx" | cut -f1))"
echo "  Windows: dist/pdf2docx.exe  ($(du -h "$SCRIPT_DIR/dist/pdf2docx.exe" | cut -f1))"
echo ""
echo "Both are standalone; no external DLLs / .so required."