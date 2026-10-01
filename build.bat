@echo off
setlocal enabledelayedexpansion

:: ================================================================
:: build.bat - Windows OCR �汾�����ű�
::
:: �� Windows �Ϲ����� OCR ֧�ֵ� pdf2docx.exe��
:: ��Ҫ��װ MSYS2 (https://www.msys2.org/)��
::
:: MSYS2 ��װ�󣬴� "MSYS2 UCRT64" �նˣ�ִ��һ��:
::   pacman -Syu
:: Ȼ��ر��նˣ��ٴ���ִ��һ��:
::   pacman -Su
:: ֮��Ϳ������б��ű���
::
:: ���ű����� cmd �� PowerShell ��ֱ�����У���Ҫ��� MSYS2 �ն�������
:: ================================================================

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

:: --- �ҵ� MSYS2 ---
set "MSYS2="
if exist "C:\msys64\ucrt64.exe"      set "MSYS2=C:\msys64"
if exist "D:\msys64\ucrt64.exe"      set "MSYS2=D:\msys64"
if exist "%USERPROFILE%\msys64\ucrt64.exe" set "MSYS2=%USERPROFILE%\msys64"

if "%MSYS2%"=="" (
    echo [ERROR] �Ҳ��� MSYS2 ��װĿ¼��
    echo ����λ��: C:\msys64, D:\msys64, %%USERPROFILE%%\msys64
    echo ��� https://www.msys2.org/ ���ذ�װ MSYS2��
    exit /b 1
)

echo [INFO] MSYS2 found at: %MSYS2%

:: MSYS2 ��� bash / pacman ·��
set "BASH=%MSYS2%\usr\bin\bash.exe"
set "PACMAN=%MSYS2%\usr\bin\pacman.exe"

if not exist "%BASH%" (
    echo [ERROR] bash.exe not found: %BASH%
    exit /b 1
)

:: --- ȷ�� MSYS2 pacman ��Կ���� ---
echo.
echo === Step 1: Check/install MSYS2 packages ===
echo.

:: �ȸ��� pacman ���ݿ⣨����һ����Ҫ��
"%BASH%" -lc "pacman -Sy --noconfirm 2>/dev/null || true"

:: ��װ UCRT64 ���빤���� + OpenCV
:: --needed ��ʾ�Ѱ�װ�������������ظ�װ
set "PKGS=mingw-w64-ucrt-x86_64-go mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-opencv mingw-w64-ucrt-x86_64-pkg-config mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-binutils mingw-w64-ucrt-x86_64-tools-git"

echo   Installing: %PKGS%
"%BASH%" -lc "pacman -S --needed --noconfirm %PKGS%"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] pacman install failed.
    echo ���ֶ��� "MSYS2 UCRT64" �նˣ�ִ��:
    echo   pacman -Syu
    echo   pacman -S --needed %PKGS%
    exit /b 1
)

echo [OK] Packages ready.

:: OpenCV 5 �İ�װֻ�ṩ opencv5.pc������ opencv.go ����д���� opencv4��
:: �� pkgconfig Ŀ¼���� opencv4.pc -> opencv5.pc ���������ӡ�
if not exist "%MSYS2%\ucrt64\lib\pkgconfig\opencv4.pc" (
    mklink "%MSYS2%\ucrt64\lib\pkgconfig\opencv4.pc" "%MSYS2%\ucrt64\lib\pkgconfig\opencv5.pc" >nul 2>&1
    if errorlevel 1 (
        :: mklink ��Ҫ����ԱȨ�ޣ�ʧ��ʱ��Ϊ�ļ�����
        copy /Y "%MSYS2%\ucrt64\lib\pkgconfig\opencv5.pc" "%MSYS2%\ucrt64\lib\pkgconfig\opencv4.pc" >nul
    )
)

:: --- ����/׼�� Windows �� onnxruntime ---
echo.
echo === Step 2: Prepare onnxruntime for Windows ===

set "ORT_DIR=%SCRIPT_DIR%build\deps\onnxruntime\win-x64"
:: 1.21.1 �� Windows Ԥ���� zip����Դ�룩��������Ԥ������� 1.22.0
set "ORT_VER=1.22.0"

:: ����Ƿ����������ļ�
if exist "%ORT_DIR%\include\onnxruntime_c_api.h" (
    if exist "%ORT_DIR%\lib\libonnxruntime.a" (
        if exist "%ORT_DIR%\bin\onnxruntime.dll" (
            echo   onnxruntime already prepared, skipping.
            goto :ort_done
        )
    )
)

:: ���� onnxruntime Windows Ԥ�����
set "ORT_ZIP=%SCRIPT_DIR%build\deps\onnxruntime-win-x64-%ORT_VER%.zip"
set "ORT_URL=https://github.com/microsoft/onnxruntime/releases/download/v%ORT_VER%/onnxruntime-win-x64-%ORT_VER%.zip"

if not exist "%ORT_ZIP%" (
    echo   Downloading onnxruntime %ORT_VER% ...
    powershell -Command "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%ORT_URL%' -OutFile '%ORT_ZIP%'; }"
    if %ERRORLEVEL% neq 0 (
        echo [ERROR] Download failed: %ORT_URL%
        echo ���ֶ����ز���ѹ��: %ORT_DIR%
        exit /b 1
    )
    echo [OK] Downloaded.
)

echo   Extracting ...
mkdir "%ORT_DIR%" 2>nul
:: �� PowerShell ��ѹ��Windows �Դ���������⹤�ߣ�
powershell -Command "& { Expand-Archive -Path '%ORT_ZIP%' -DestinationPath '%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp' -Force; }"
:: onnxruntime zip ��ѹ�������� onnxruntime-win-x64-%ORT_VER%/ Ŀ¼��
:: �ƶ���Ŀ��λ��
set "ORT_EXTRACTED=%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp\onnxruntime-win-x64-%ORT_VER%"
if not exist "%ORT_EXTRACTED%" (
    :: ��Щ�汾��ѹ��ֱ��ƽ��
    echo   Checking extracted structure...
    dir "%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp" 2>nul
)

:: ֻ������Ҫ��: include/, lib/onnxruntime.lib, lib/onnxruntime.dll
mkdir "%ORT_DIR%\include" 2>nul
mkdir "%ORT_DIR%\lib" 2>nul
mkdir "%ORT_DIR%\bin" 2>nul

xcopy /Y /Q "%ORT_EXTRACTED%\include\*" "%ORT_DIR%\include\" >nul 2>&1
copy /Y "%ORT_EXTRACTED%\lib\onnxruntime.lib" "%ORT_DIR%\lib\" >nul 2>&1
copy /Y "%ORT_EXTRACTED%\lib\onnxruntime.dll" "%ORT_DIR%\bin\" >nul 2>&1

:: ��� onnxruntime.dll �� bin Ŀ¼
if not exist "%ORT_DIR%\bin\onnxruntime.dll" (
    copy /Y "%ORT_EXTRACTED%\bin\onnxruntime.dll" "%ORT_DIR%\bin\" >nul 2>&1
)

:: ������ʱĿ¼
rmdir /S /Q "%SCRIPT_DIR%build\deps\onnxruntime\win-x64-tmp" 2>nul

:: --- �� gendef + dlltool ���� MinGW ���ݵĵ���� ---
:: MSVC �� .lib ���ܱ� MinGW ���ӣ���Ҫ�� DLL ���� .def ������ .a
echo   Generating MinGW import library ...
"%BASH%" -lc "cd $(cygpath '%SCRIPT_DIR%') && export PATH=/ucrt64/bin:\$PATH && gendef - build/deps/onnxruntime/win-x64/bin/onnxruntime.dll > build/deps/onnxruntime/win-x64/lib/onnxruntime.def 2>/dev/null && dlltool -d build/deps/onnxruntime/win-x64/lib/onnxruntime.def -l build/deps/onnxruntime/win-x64/lib/libonnxruntime.a -D build/deps/onnxruntime/win-x64/bin/onnxruntime.dll"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] gendef/dlltool failed.
    echo 请确认 MSYS2 中已安装 binutils 和 tools: pacman -S --needed mingw-w64-ucrt-x86_64-binutils mingw-w64-ucrt-x86_64-tools-git
    exit /b 1
)

echo [OK] onnxruntime MinGW import lib ready.

:ort_done

:: --- ���� ---
echo.
echo === Step 3: Build pdf2docx.exe (Windows OCR) ===

mkdir dist 2>nul

"%BASH%" -lc "cd $(cygpath '%SCRIPT_DIR%') && export PATH=/ucrt64/bin:\$PATH && export GOROOT=/ucrt64/lib/go && export CGO_ENABLED=1 && export GOOS=windows && export GOARCH=amd64 && export GOPROXY=https://goproxy.cn,direct && export CGO_CXXFLAGS='-std=c++17' && echo '  Building...' && go build -mod=mod -ldflags='-s -w -H windowsgui' -o dist/pdf2docx.exe . && echo '  Build OK.'"

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Build failed.
    exit /b 1
)

echo [OK] pdf2docx.exe built.

:: --- �ռ� DLL ---
echo.
echo === Step 4: Collect DLL dependencies ===

set "DIST_DIR=%SCRIPT_DIR%dist"
set "PKG_DIR=%DIST_DIR%\pdf2docx-windows-amd64"

:: ������Ŀ¼
if exist "%PKG_DIR%" rmdir /S /Q "%PKG_DIR%"
mkdir "%PKG_DIR%"

:: ���� exe
copy /Y "%DIST_DIR%\pdf2docx.exe" "%PKG_DIR%\" >nul

:: �� MSYS2 �� bash + ldd �ҳ�������Ҫ�� DLL
echo   Finding DLL dependencies...
"%BASH%" -lc "
    cd \$(cygpath '%SCRIPT_DIR%')
    export PATH=/ucrt64/bin:\$PATH

    exe_file=dist/pdf2docx.exe
    pkg_dir=dist/pdf2docx-windows-amd64

    # ��Ҫ���Ƶ� DLL �б�
    DLLS=\$(
        ldd \"\$exe_file\" 2>/dev/null | grep '/ucrt64/bin/' | awk '{print \$3}' | sort -u
    )

    # ���ǰ��� onnxruntime��������ͨ�� MSYS2 ��װ�ģ�
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

:: --- ���� models ---
echo   Copying models...
xcopy /E /I /Q /Y "%SCRIPT_DIR%models" "%PKG_DIR%\models\" >nul
echo   models/ copied.

:: --- ��� ---
echo.
echo === Step 5: Package ===

set "ZIP_NAME=%DIST_DIR%\pdf2docx-windows-amd64-ocr.zip"
if exist "%ZIP_NAME%" del /Q "%ZIP_NAME%"

powershell -Command "& { Compress-Archive -Path '%PKG_DIR%\*' -DestinationPath '%ZIP_NAME%' -Force; }"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Packaging failed.
    exit /b 1
)

:: ��ȡ�ļ���С
for %%A in ("%ZIP_NAME%") do set "ZIP_SIZE=%%~zA"
set /a ZIP_SIZE_MB=%ZIP_SIZE%/1048576

echo.
echo ================================================================
echo Build complete!
echo   Output: %ZIP_NAME%  (~%ZIP_SIZE_MB% MB)
echo.
echo ����:
echo   pdf2docx.exe
echo   models/ (OCR ģ��)
echo   *.dll (����ʱ��̬��)
echo.
echo ��ѹ����ͬһĿ¼���� pdf2docx.exe ����ʹ�� OCR��
echo ================================================================

:: ����������ʱ�ļ������� exe��������ԣ�
echo.
echo [INFO] �м���ﱣ���� %PKG_DIR%\
echo [INFO] run "rmdir /S /Q %PKG_DIR%" to clean up

endlocal