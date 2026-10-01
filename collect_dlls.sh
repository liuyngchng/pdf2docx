#!/usr/bin/env bash
set -e
# 脚本位于项目根目录，dist/ 在其下；直接切换到脚本自身所在目录
cd "$(dirname "$0")"
export PATH=/ucrt64/bin:$PATH

exe_file=dist/pdf2docx.exe
pkg_dir=dist/pdf2docx-windows-amd64

echo "  Copying DLLs..."

# Collect ucrt64 DLLs
ldd "$exe_file" 2>/dev/null | grep '/ucrt64/bin/' | awk '{print $3}' | sort -u | while read dll; do
    echo "    $dll"
    cp "$dll" "$pkg_dir/"
done

# onnxruntime DLL
ort_bin='build/deps/onnxruntime/win-x64/bin/onnxruntime.dll'
if [ -f "$ort_bin" ]; then
    echo "    $ort_bin"
    cp "$ort_bin" "$pkg_dir/"
fi

echo "  DLLs copied."
