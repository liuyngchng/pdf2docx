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
for arg in "$@"; do
  case "$arg" in
    -x|verbose) GO_BUILD_X="-x" ;;
    *) ;;
  esac
done

mkdir -p "$SCRIPT_DIR/dist"

echo ""
echo "=== Building pdf2docx-server (Linux, static) ==="
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build ${GO_BUILD_X} -mod=mod -ldflags='-s -w' -o dist/pdf2docx-server ./cmd/server/

echo ""
echo "=== Build complete ==="
echo "  Linux server: dist/pdf2docx-server ($(du -h "$SCRIPT_DIR/dist/pdf2docx-server" | cut -f1))"
echo ""
echo "pdf2docx-server is a static binary (CGO_ENABLED=0), drop it on any Linux host."
