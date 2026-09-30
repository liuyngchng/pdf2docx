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

# ── Usage ───────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
用法: ./build_server.sh [参数...]

参数说明:
  --with-ocr              构建带 OCR 支持的服务器（需要 libopencv-dev + vendored onnxruntime）
  --no-obfuscate          关闭 garble 代码混淆（默认开启；OCR 模式下混淆自动跳过）
  -x | verbose            输出 go build 的详细编译日志（-x）
  -h | --help             显示本帮助并退出

代理参数（从环境变量继承，可选）:
  HTTP_PROXY / http_proxy     设置 HTTP 代理
  HTTPS_PROXY / https_proxy   设置 HTTPS 代理

示例:
  ./build_server.sh                  # 默认构建（静态链接，无 OCR，开启混淆）
  ./build_server.sh --with-ocr       # 构建带 OCR 的服务器（动态链接）
  ./build_server.sh --with-ocr -x    # 带 OCR 且输出详细编译日志
  ./build_server.sh --no-obfuscate   # 不混淆构建

说明:
  不带 --with-OCR 时产出静态链接二进制，可直接部署到任意 Linux 主机。
  带 --with-OCR 时产出动态链接二进制，目标主机需安装 libopencv-dev 并在二进制旁放置
  libonnxruntime.so。
EOF
}

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
    -h|--help|help)  usage; exit 0 ;;
    *)               echo "WARNING: 未知参数 '$arg'，已忽略（用 -h 查看用法）" ;;
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
echo "    --with-ocr         构建带 OCR 支持的服务器"
echo "                       需要 libopencv-dev + vendored onnxruntime"
echo "    --no-obfuscate     关闭 garble 代码混淆（默认开启混淆）"
echo "    -x | verbose       输出 go build 详细编译日志"
echo "    -h | --help        显示帮助并退出"
echo "    HTTP_PROXY         从环境变量继承 HTTP 代理"
echo "    HTTPS_PROXY        从环境变量继承 HTTPS 代理"
echo "────────────────────────────────────────────────────────"
echo "  当前参数:"
echo "    WITH_OCR       = $WITH_OCR"
echo "    OBFUSCATE      = $OBFUSCATE"
echo "    GO_BUILD_X     = ${GO_BUILD_X:-(未设置)}"
echo "    HTTP_PROXY     = ${HTTP_PROXY:-${http_proxy:-(未设置)}}"
echo "    HTTPS_PROXY    = ${HTTPS_PROXY:-${https_proxy:-(未设置)}}"
echo "────────────────────────────────────────────────────────"
echo ""

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

# Clean dist/ and build.
rm -rf "$SCRIPT_DIR/dist/pdf2docx-server" "$SCRIPT_DIR/dist/libonnxruntime.so" "$SCRIPT_DIR/dist/models"
mkdir -p "$SCRIPT_DIR/dist"

echo ""
echo "=== Building pdf2docx-server${OCR_LABEL}${OBF_LABEL} ==="
CGO_ENABLED=${SERVER_CGO} GOOS=linux GOARCH=amd64 \
  ${BUILD_BIN} build ${GO_BUILD_X} -mod=mod ${OCR_TAGS} -ldflags='-s -w' -o dist/pdf2docx-server ./cmd/server/

# Bundle libonnxruntime.so + models for OCR builds.
if $WITH_OCR; then
  cp "$ONNXRT_LIB/libonnxruntime.so" "$SCRIPT_DIR/dist/libonnxruntime.so"
  echo "  bundled:  dist/libonnxruntime.so"

  cp -r "$SCRIPT_DIR/models" "$SCRIPT_DIR/dist/models"
  echo "  bundled:  dist/models/"
fi

echo ""
echo "=== Build complete ==="
echo "  Linux server: dist/pdf2docx-server ($(du -h "$SCRIPT_DIR/dist/pdf2docx-server" | cut -f1))"

# ── Package into tar for distribution ────────────────────────────
echo ""
echo "--- Packaging ---"
ARCHIVE="pdf2docx-server-linux-amd64.tar"
rm -f "$SCRIPT_DIR/dist/$ARCHIVE"
if $WITH_OCR; then
  cd "$SCRIPT_DIR/dist"
  tar -cf "$ARCHIVE" pdf2docx-server libonnxruntime.so models/
  cd "$SCRIPT_DIR"
  echo "  $ARCHIVE  ($(du -h "$SCRIPT_DIR/dist/$ARCHIVE" | cut -f1)) — Linux server OCR 完整包"

  rm -rf "$SCRIPT_DIR/dist/pdf2docx-server" "$SCRIPT_DIR/dist/libonnxruntime.so" "$SCRIPT_DIR/dist/models"
else
  cd "$SCRIPT_DIR/dist"
  tar -cf "$ARCHIVE" pdf2docx-server
  cd "$SCRIPT_DIR"
  echo "  $ARCHIVE  ($(du -h "$SCRIPT_DIR/dist/$ARCHIVE" | cut -f1))"

  rm -f "$SCRIPT_DIR/dist/pdf2docx-server"
fi

echo ""
echo "分发文件（做好的压缩包）:"
echo "  dist/$ARCHIVE"
echo ""
if $WITH_OCR; then
  echo "OCR 包内容: pdf2docx-server + libonnxruntime.so + models/ 模型目录"
  echo "OCR build is dynamic: target host needs libopencv_core + libopencv_imgproc"
  echo "(libopencv-dev or equivalent) and dist/libonnxruntime.so beside the binary."
else
  echo "包内容: pdf2docx-server（静态链接二进制，可直接部署到任意 Linux 主机）"
fi