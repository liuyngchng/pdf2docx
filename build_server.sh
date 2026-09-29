#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Build the headless HTTP server binary (Linux).
#   ./build_server.sh                 # static, no OCR (original behavior)
#   ./build_server.sh --with-ocr      # dynamic, with OCR (needs OpenCV + onnxruntime)
#
# OCR build requires on the host:
#   - libopencv-dev (pkg-config opencv4)
#   - build/deps/onnxruntime/ (header + libonnxruntime.so, already vendored)
# ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f "go.mod" ]]; then
  echo "ERROR: run this script from the pdf2docx directory"
  exit 1
fi

if ! command -v go &>/dev/null; then
  echo "ERROR: go not found"
  exit 1
fi

GO_BUILD_X=""   # set to "-x" when verbose is requested
OBFUSCATE=true
WITH_OCR=false
for arg in "$@"; do
  case "$arg" in
    -x|verbose)      GO_BUILD_X="-x" ;;
    --no-obfuscate)  OBFUSCATE=false ;;
    --with-ocr)      WITH_OCR=true ;;
    *) ;;
  esac
done

mkdir -p "$SCRIPT_DIR/dist"

# ── Proxy (from environment) ──────────────────────────────────────
HTTP_PROXY_VAL="${HTTP_PROXY:-${http_proxy:-}}"
HTTPS_PROXY_VAL="${HTTPS_PROXY:-${https_proxy:-}}"

add_scheme() { local v="$1"; [[ -z "$v" || "$v" == *"://"* ]] && { printf '%s' "$v"; return; }; printf 'http://%s' "$v"; }
HTTP_PROXY_VAL="$(add_scheme "$HTTP_PROXY_VAL")"
HTTPS_PROXY_VAL="$(add_scheme "$HTTPS_PROXY_VAL")"

if [[ -n "$HTTP_PROXY_VAL" || -n "$HTTPS_PROXY_VAL" ]]; then
  export HTTP_PROXY="$HTTP_PROXY_VAL" HTTPS_PROXY="$HTTPS_PROXY_VAL"
  export http_proxy="$HTTP_PROXY_VAL" https_proxy="$HTTPS_PROXY_VAL"
fi

# ── OCR toggle ────────────────────────────────────────────────────
if $WITH_OCR; then
  if ! pkg-config --exists opencv4; then
    echo "ERROR: --with-ocr requires libopencv-dev (pkg-config opencv4)"
    exit 1
  fi
  ONNXRT_LIB="$SCRIPT_DIR/build/deps/onnxruntime/lib"
  if [[ ! -f "$ONNXRT_LIB/libonnxruntime.so" ]]; then
    echo "ERROR: --with-ocr requires $ONNXRT_LIB/libonnxruntime.so (vendored onnxruntime)"
    exit 1
  fi
  OCR_TAGS=""
  OCR_CGO=1
  OCR_LABEL=" with OCR"
else
  OCR_TAGS="-tags noocr"
  OCR_CGO=0
  OCR_LABEL=" (static, no OCR)"
fi

# ── Obfuscation toggle ────────────────────────────────────────────
if $OBFUSCATE && ! $WITH_OCR; then
  # Only garble for the static build; garble + cgo + vendored libs is flaky.
  if ! command -v garble &>/dev/null; then
    echo "garble not found; installing mvdan.cc/garble@v0.14.2 ..."
    GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
      go install mvdan.cc/garble@v0.14.2
    if ! command -v garble &>/dev/null; then
      echo "ERROR: garble installation failed; try adding \$(go env GOPATH)/bin to PATH"
      exit 1
    fi
    echo "garble installed successfully"
  fi
  BUILD_BIN="garble -literals"
  export GOGARBLE=pdftoword
  OBF_LABEL=" (obfuscated)"
  SERVER_CGO=0
elif $OBFUSCATE && $WITH_OCR; then
  # OCR build skips garble (cgo + garble incompatibility).
  BUILD_BIN="go"
  unset GOGARBLE 2>/dev/null || true
  OBF_LABEL=" (obfuscation skipped with OCR)"
  SERVER_CGO=1
else
  BUILD_BIN="go"
  unset GOGARBLE 2>/dev/null || true
  OBF_LABEL=""
  SERVER_CGO=${OCR_CGO}
fi

echo ""
echo "=== Building pdf2docx-server${OCR_LABEL}${OBF_LABEL} ==="
CGO_ENABLED=${SERVER_CGO} GOOS=linux GOARCH=amd64 \
  ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod ${OCR_TAGS} -ldflags='-s -w' -o dist/pdf2docx-server ./cmd/server/

# Bundle libonnxruntime.so next to the binary for OCR builds.
if $WITH_OCR; then
  cp "$ONNXRT_LIB/libonnxruntime.so" "$SCRIPT_DIR/dist/libonnxruntime.so"
  echo "  bundled:  dist/libonnxruntime.so"
fi

echo ""
echo "=== Build complete ==="
echo "  Linux server: dist/pdf2docx-server ($(du -h "$SCRIPT_DIR/dist/pdf2docx-server" | cut -f1))"
if $WITH_OCR; then
  echo ""
  echo "OCR build is dynamic: target host needs libopencv_core + libopencv_imgproc"
  echo "(libopencv-dev or equivalent) and dist/libonnxruntime.so beside the binary."
else
  echo ""
  echo "pdf2docx-server is a static binary, drop it on any Linux host."
fi