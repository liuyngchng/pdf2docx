# pdf2docx-server API 文档

## 概述

HTTP 服务，接收 PDF 文件，返回转换后的 DOCX 文件。

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

### 2. PDF 转 DOCX

```
POST /convert
Content-Type: multipart/form-data
```

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

**错误响应**

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
# 简单检查
curl -s http://localhost:8080/health

# 只看 HTTP 状态码
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/health
```

### 转换 PDF

```bash
# 基本转换
curl -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx

# 显示上传进度
curl -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  --progress-bar

# 显示请求/响应头
curl -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  -v

# 忽略自签名证书（HTTPS 场景）
curl -X POST https://your-server:8443/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  --insecure

# 强制不走代理（直连内网服务器）
curl -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  --noproxy "*"

# 只对 localhost 不走代理
curl -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  --noproxy "localhost,127.0.0.1"

# 重试（网络不稳定时）
curl -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  --retry 3 --retry-delay 5
```

### 验证结果

```bash
# 检查返回的是否为有效的 DOCX 文件
curl -s -X POST http://localhost:8080/convert \
  -F "file=@input.pdf" \
  -o output.docx \
  -w "\nHTTP %{http_code}, size %{size_download} bytes, took %{time_total}s\n"

# 确认文件头（DOCX 本质是 ZIP）
file output.docx
# 输出: output.docx: Microsoft Word 2007+
```

## 限制

- PDF 最大 64 MB
- 不支持加密 PDF
- 读写超时：请求 60 秒，响应 300 秒