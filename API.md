# pdf2docx-server API 文档

## 概述

HTTP 服务，接收 PDF 文件，返回转换后的 DOCX 文件。提供两种转换模式：

| 端点 | 模式 | 产出 | 说明 |
|------|------|------|------|
| `/convert/image` | 截图版 | `.docx` | 每页渲染为图片嵌入 Word，始终可用 |
| `/convert/text` | 文字版 | `.text.docx` | 提取文字（有文字层的 PDF 直接提取，扫描件 OCR），需要 OCR 模型 |

---

## 端点

### 1. 健康检查

```
GET /health
```

**响应**

```
200 OK
Content-Type: application/json

{"status":"ok"}
```

---

### 2. 截图版转换

```
POST /convert/image
Content-Type: multipart/form-data
```

每页渲染为 JPEG 图片嵌入 DOCX，适合所有 PDF（包括纯扫描件）。

**请求**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file` | file | 是 | 要转换的 PDF 文件，最大 64 MB |

**成功响应**

```
200 OK
Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document
Content-Disposition: attachment; filename="xxx.docx"

<DOCX 二进制流>
```

---

### 3. 文字版转换

```
POST /convert/text
Content-Type: multipart/form-data
```

优先使用 MuPDF 提取 PDF 内嵌文字层；对纯扫描件（无文字层）回退到 OCR 识别。

**请求**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `file` | file | 是 | 要转换的 PDF 文件，最大 64 MB |

**成功响应**

```
200 OK
Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document
Content-Disposition: attachment; filename="xxx.text.docx"

<DOCX 二进制流>
```

---

### 错误响应

| 状态码 | 说明 |
|--------|------|
| 400 | 请求格式错误（缺少 file 字段、非 multipart 等） |
| 413 | 文件超过 64 MB |
| 500 | 转换失败或内部错误 |

---

## 配置

| 环境变量 | 默认值 | 说明 |
|----------|--------|------|
| `PORT` | `8080` | 监听端口 |
| `LOG_LEVEL` | `info` | 日志级别：`debug` / `info` / `warn` / `error` |

## 示例

### 健康检查

```bash
curl -s --noproxy "*" http://localhost:8080/health
```

### 截图版转换

```bash
curl -X POST --noproxy "*" http://localhost:8080/convert/image \
  -F "file=@input.pdf" \
  -o output.docx
```

### 文字版转换

```bash
curl -X POST --noproxy "*" http://localhost:8080/convert/text \
  -F "file=@input.pdf" \
  -o output.text.docx
```



### 显示上传进度

```bash
curl -X POST http://localhost:8080/convert/image \
  -F "file=@input.pdf" \
  -o output.docx \
  --progress-bar
```



### 验证结果

```bash
# 检查返回的文件类型（DOCX 本质是 ZIP）
file output.docx
# 输出: output.docx: Microsoft Word 2007+
```

## 限制

- PDF 最大 64 MB
- 不支持加密 PDF
- 读写超时：请求 60 秒，响应 300 秒