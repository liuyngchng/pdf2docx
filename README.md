# pdf2docx

将 PDF 逐页渲染为图片，并嵌入 Word 文档的桌面工具。适合在 Word 中像翻页一样逐页阅读 PDF 内容（尤其是扫描件）。

## 技术栈

| 组件 | 选型 | 说明 |
|------|------|------|
| GUI | [Fyne](https://fyne.io/) v2 | Go 原生 GUI 框架 |
| PDF 渲染 | [go-fitz](https://github.com/gen2brain/go-fitz) (MuPDF) | 工业级 PDF 引擎，支持所有 PDF 版本，文字+图片+矢量全渲染 |
| Word 生成 | 手写 OOXML（标准库 `archive/zip` + `encoding/xml`） | 无外部依赖，输出标准 .docx |

## 编译

### 前置条件

- Docker（编译环境全部容器化，本机无需 Go）
- Go 工具链 tarball：放到 `build/deps/go1.24.13.linux-amd64.tar.gz`（`build.sh` 自动复制 Dockerfile 引用，首次需手动下载）

### 一键编译

```bash
./build.sh
```

产出 `dist/` 下两个文件：

| 文件 | 平台 | 说明 |
|------|------|------|
| `pdf2docx` | Linux amd64 | 独立二进制 |
| `pdf2docx.exe` | Windows amd64 | 无外部 DLL 依赖，双击运行 |

如果需要代理访问外网：

```bash
./build.sh http_proxy=http://proxy:8080 https_proxy=http://proxy:8080
```

### 纯 Go 核心逻辑测试（可选）

核心转换流程可以用命令行版本测试，无需 GUI、无需 CGO：

```bash
CGO_ENABLED=0 go build -o pdf2docx-cli ./cmd/cli/
./pdf2docx-cli /path/to/input.pdf
```

## 使用

1. 双击 `pdf2docx.exe`（Windows）或运行 `./pdf2docx`（Linux）
2. 弹出文件选择对话框，选一个 PDF 文件
3. 等待转换完成（进度条显示页码进度）
4. 在同目录下生成同名的 `.docx` 文件，用 Word / WPS 打开即可

## 编译原理

```
ubuntu:24.04
  └─ 安装 gcc + MinGW-w64 + X11/GL/Wayland 开发头文件 + Go toolchain
       └─ go mod download（模块缓存，挂载外部 volume 复用）
            ├─ CGO_ENABLED=1 GOOS=linux   → pdf2docx（ELF）
            └─ CGO_ENABLED=1 GOOS=windows
               CC=x86_64-w64-mingw32-gcc  → pdf2docx.exe（PE32+）

MuPDF 静态库由 go-fitz 内置提供（libmupdf_linux_amd64.a / libmupdf_windows_amd64.a），
编译时直接链接进二进制，运行时不需要任何外部 .so / .dll。
```

## 项目结构

```
pdf2docx/
├── main.go                    # Fyne GUI 入口
├── build.sh                   # Docker 一键编译脚本
├── Dockerfile                 # 编译镜像（基于 ubuntu:24.04）
├── go.mod / go.sum
├── cmd/cli/main.go            # 纯 Go 命令行版本（CGO_ENABLED=0）
└── internal/pdfconv/
    ├── convert.go             # PDF → 图片 → docx 主流程
    └── docx.go                # 手写 OOXML 打包
```

## 限制

- 暂不支持加密 PDF
- 纯文字页面依赖 MuPDF 字体回退，特殊字体效果可能不完美
- 中文字体渲染依赖系统字体（Windows 通常无问题）

## License

MIT