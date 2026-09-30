@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ================================================================
:: build.bat - Windows OCR 版本构建脚本
::
:: 在 Windows 上构建带 OCR 支持的 pdf2docx.exe。
:: 需要安装 MSYS2 (https://www.msys2.org/)。
::
:: MSYS2 安装后，打开 "MSYS2 UCRT64" 终端，执行一次:
::   pacman -Syu
:: 然后关闭终端，再打开再执行一次:
::   pacman -Su
:: 之后就可以运行本脚本。
::
:: 本脚本可在 cmd 或 PowerShell 中直接运行，不要求从 MSYS2 终端启动。
:: ================================================================

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

:: --- 找到 MSYS2 ---
set "MSYS2="
if exist "C:\msys64\ucrt64.exe"      set "MSYS2=C:\msys64"
if exist "D:\msys64\ucrt64.exe"      set "MSYS2=D:\msys64"
if exist "%USERPROFILE%\msys64\ucrt64.exe" set "MSYS2=%USERPROFILE%\msys64"

if "%MSYS2%"=="" (
    echo [ERROR] 找不到 MSYS2 安装目录。
    echo 常见位置: C:\msys64, D:\msys64, %%USERPROFILE%%\msys64
    echo 请从 https://www.msys2.org/ 下载安装 MSYS2。
    exit /b 1
)

echo [INFO] MSYS2 found at: %MSYS2%

:: MSYS2 里的 bash / pacman 路径
set "BASH=%MSYS2%\usr\bin\bash.exe"
set "PACMAN=%MSYS2%\usr\bin\pacman.exe"

if not exist "%BASH%" (
    echo [ERROR] bash.exe not found: %BASH%
    exit /b 1
)

:: --- 确保 MSYS2 pacman 密钥正常 ---
echo.
echo === Step 1: Check/install MSYS2 packages ===
echo.

:: 先更新 pacman 数据库（仅第一次需要）
"%BASH%" -lc "pacman -Sy --noconfirm 2>/dev/null || true"

:: 安装 UCRT64 编译工具链 + OpenCV
:: --needed 表示已安装的跳过，不会重复装
set "PKGS=mingw-w64-ucrt-x86_64-go mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-opencv mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-cmake"

echo   Installing: %PKGS%
"%BASH%" -lc "pacman -S --needed --noconfirm %PKGS%"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] pacman install failed.
    echo 请手动打开 "MSYS2 UCRT64" 终端，执行:
    echo   pacman -Syu
    echo   pacman -S --needed %PKGS%
    exit /b 1
)

echo [OK] Packages ready.

:: --- 下载/准备 Windows 版 onnxruntime ---
echo.
echo === Step 2: Prepare onnxruntime for Windows ===

set "ORT_DIR=%SCRIPT_DIR%build\deps\onnxruntime\win-x64"
set "ORT_VER=1.21.1"

:: 检查是否已有完整文件
if exist "%ORT_DIR%\include\onnxruntime_c_api.h" (
    if exist "%ORT_DIR%\lib\libonnxruntime.a" (
        if exist "%ORT_DIR%\bin\onnxruntime.dll" (
            echo   onnxruntime already prepared, skipping.
            goto :ort_done
        )
    )
)

:: 下载 onnxruntime Windows 预编译包
set "ORT_ZIP=%SCRIPT_DIR%build\deps\onnxruntime-win-x64-%ORT_VER%.zip"
set "ORT_URL=https://github.com/microsoft/onnxruntime/releases/download/v%ORT_VER%/onnxruntime-win-x64-%ORT_VER%.zip"

if not exist "%ORT_ZIP%" (
    echo   Downloading onnxruntime %ORT_VER% ...
    powershell -Command "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%ORT_URL%' -OutFile '%ORT_ZIP%'; }"
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] Download failed: %ORT_URL%
        echo 请手动下载并解压到: %ORT_DIR%
        exit /b 1
    )
    echo [OK] Downloaded.
)

echo   Extracting ...
mkdir "%ORT_DIR%" 2>nul
:: 用 PowerShell 解压（Windows 自带，无需额外工具）
powershell -Command "& { Expand-Archive -Path '%ORT_ZIP%' -DestinationPath '%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp' -Force; }"
:: onnxruntime zip 解压后内容在 onnxruntime-win-x64-%ORT_VER%/ 目录下
:: 移动到目标位置
set "ORT_EXTRACTED=%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp\onnxruntime-win-x64-%ORT_VER%"
if not exist "%ORT_EXTRACTED%" (
    :: 有些版本解压后直接平铺
    echo   Checking extracted structure...
    dir "%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp" 2>nul
)

:: 只拷贝需要的: include/, lib/onnxruntime.lib, lib/onnxruntime.dll
mkdir "%ORT_DIR%\include" 2>nul
mkdir "%ORT_DIR%\lib" 2>nul
mkdir "%ORT_DIR%\bin" 2>nul

xcopy /Y /Q "%ORT_EXTRACTED%\include\*" "%ORT_DIR%\include\" >nul 2>&1
copy /Y "%ORT_EXTRACTED%\lib\onnxruntime.lib" "%ORT_DIR%\lib\" >nul 2>&1
copy /Y "%ORT_EXTRACTED%\lib\onnxruntime.dll" "%ORT_DIR%\bin\" >nul 2>&1

:: 如果 onnxruntime.dll 在 bin 目录
if not exist "%ORT_DIR%\bin\onnxruntime.dll" (
    copy /Y "%ORT_EXTRACTED%\bin\onnxruntime.dll" "%ORT_DIR%\bin\" >nul 2>&1
)

:: 清理临时目录
rmdir /S /Q "%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp" 2>nul

:: --- 用 gendef + dlltool 生成 MinGW 兼容的导入库 ---
:: MSVC 的 .lib 不能被 MinGW 链接，需要从 DLL 生成 .def 再生成 .a
echo   Generating MinGW import library ...
"%BASH%" -lc "cd $(cygpath '%SCRIPT_DIR%') && \
    export PATH=/ucrt64/bin:\$PATH && \
    gendef - build/deps/onnxruntime/win-x64/bin/onnxruntime.dll > build/deps/onnxruntime/win-x64/lib/onnxruntime.def 2>/dev/null && \
    dlltool -d build/deps/onnxruntime/win-x64/lib/onnxruntime.def -l build/deps/onnxruntime/win-x64/lib/libonnxruntime.a -D build/deps/onnxruntime/win-x64/bin/onnxruntime.dll"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] gendef/dlltool failed.
    echo 请确认 MSYS2 中已安装 binutils: pacman -S --needed mingw-w64-ucrt-x86_64-binutils
    exit /b 1
)

echo [OK] onnxruntime MinGW import lib ready.

:ort_done

:: --- 编译 ---
echo.
echo === Step 3: Build pdf2docx.exe (Windows OCR) ===

"%BASH%" -lc "cd $(cygpath '%SCRIPT_DIR%') && \
    export PATH=/ucrt64/bin:\$PATH && \
    export CGO_ENABLED=1 && \
    export GOOS=windows && \
    export GOARCH=amd64 && \
    export GOPROXY=https://goproxy.cn,direct && \
    export CGO_CXXFLAGS='-std=c++17' && \
    mkdir -p dist && \
    echo '  Building...' && \
    go build -mod=mod -ldflags='-s -w -H windowsgui' -o dist/pdf2docx.exe . && \
    echo '  Build OK.'"

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Build failed.
    exit /b 1
)

echo [OK] pdf2docx.exe built.

:: --- 收集 DLL ---
echo.
echo === Step 4: Collect DLL dependencies ===

set "DIST_DIR=%SCRIPT_DIR%dist"
set "PKG_DIR=%DIST_DIR%\pdf2docx-windows-amd64"

:: 清理旧目录
if exist "%PKG_DIR%" rmdir /S /Q "%PKG_DIR%"
mkdir "%PKG_DIR%"

:: 复制 exe
copy /Y "%DIST_DIR%\pdf2docx.exe" "%PKG_DIR%\" >nul

:: 用 MSYS2 的 bash + ldd 找出所有需要的 DLL
echo   Finding DLL dependencies...
"%BASH%" -lc "
    cd \$(cygpath '%SCRIPT_DIR%')
    export PATH=/ucrt64/bin:\$PATH

    exe_file=dist/pdf2docx.exe
    pkg_dir=dist/pdf2docx-windows-amd64

    # 需要复制的 DLL 列表
    DLLS=\$(
        ldd \"\$exe_file\" 2>/dev/null | grep '/ucrt64/bin/' | awk '{print \$3}' | sort -u
    )

    # 总是包含 onnxruntime（它不是通过 MSYS2 安装的）
    ort_bin='build/deps/onnxruntime/win-x64/bin/onnxruntime.dll'

    echo \"  Copying DLLs...\"
    for dll in \$DLLS; do
        echo \"    \$dll\"
        cp \"\$dll\" \"\$pkg_dir/\"
    done

    if [ -f \"\$ort_bin\" ]; then
        echo \"    \$ort_bin\"
        cp \"\$ort_bin\" \"\$pkg_dir/\"
    fi

    echo \"  DLLs copied.\"
"

:: --- 复制 models ---
echo   Copying models...
xcopy /E /I /Q /Y "%SCRIPT_DIR%models" "%PKG_DIR%\models\" >nul
echo   models/ copied.

:: --- 打包 ---
echo.
echo === Step 5: Package ===

set "ZIP_NAME=%DIST_DIR%\pdf2docx-windows-amd64-ocr.zip"
if exist "%ZIP_NAME%" del /Q "%ZIP_NAME%"

powershell -Command "& { Compress-Archive -Path '%PKG_DIR%\*' -DestinationPath '%ZIP_NAME%' -Force; }"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Packaging failed.
    exit /b 1
)

:: 获取文件大小
for %%A in ("%ZIP_NAME%") do set "ZIP_SIZE=%%~zA"
set /a ZIP_SIZE_MB=%ZIP_SIZE%/1048576

echo.
echo ================================================================
echo Build complete!
echo   Output: %ZIP_NAME%  (~%ZIP_SIZE_MB% MB)
echo.
echo 内容:
echo   pdf2docx.exe
echo   models/ (OCR 模型)
echo   *.dll (运行时动态库)
echo.
echo 解压后在同一目录运行 pdf2docx.exe 即可使用 OCR。
echo ================================================================

:: 清理构建临时文件（保留 exe，方便调试）
echo.
echo [INFO] 中间产物保留在 %PKG_DIR%\
echo [INFO] run "rmdir /S /Q %PKG_DIR%" to clean up

endlocal