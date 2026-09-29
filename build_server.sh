#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# Build the headless HTTP server binary (Linux, static).
#   ./build_server.sh
#
# No Docker needed: server has no GUI/CGO deps, so we build with
# the host Go toolchain directly.
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
for arg in "$@"; do
  case "$arg" in
    -x|verbose)      GO_BUILD_X="-x" ;;
    --no-obfuscate)  OBFUSCATE=false ;;
    *) ;;
  esac
done

mkdir -p "$SCRIPT_DIR/dist"

# ── Obfuscation toggle ────────────────────────────────────────────
if $OBFUSCATE; then
  if ! command -v garble &>/dev/null; then
    echo "ERROR: garble not found; install it with: go install mvdan.cc/garble@v0.14.2"
    exit 1
  fi
  BUILD_BIN="garble -literals"
  GARBLE_ENV=("GOGARBLE=pdftoword")
  OBF_LABEL=" (obfuscated)"
  # garble has issues with purego assembly when CGO_ENABLED=0, so we
  # switch to CGO_ENABLED=1 (the resulting binary is still portable).
  SERVER_CGO=1
else
  BUILD_BIN="go"
  GARBLE_ENV=()
  OBF_LABEL=""
  SERVER_CGO=0
fi

echo ""
echo "=== Building pdf2docx-server (Linux, static)${OBF_LABEL} ==="
CGO_ENABLED=${SERVER_CGO} GOOS=linux GOARCH=amd64 ${GARBLE_ENV[@]+"${GARBLE_ENV[@]}"} \
  ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod -ldflags='-s -w' -o dist/pdf2docx-server ./cmd/server/

echo ""
echo "=== Build complete ==="
echo "  Linux server: dist/pdf2docx-server ($(du -h "$SCRIPT_DIR/dist/pdf2docx-server" | cut -f1))"
echo ""
echo "pdf2docx-server is a static binary, drop it on any Linux host."
