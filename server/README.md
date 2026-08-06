# Flutter Vision Lab 云端识别代理

Flutter 将稳定目标的 JPEG 裁剪图上传到此服务。服务端验证并重新编码图片，调用
OpenAI-compatible VLM，再返回统一 JSON。上游 API Key 只存在于服务端，不进入
APK、Git 或接口响应。

```text
Flutter --multipart JPEG--> FastAPI --净化后的 JPEG--> VLM
        <--统一 JSON-------         <--模型 JSON---------
```

当前实现面向单人维护、少量同事试用：使用一个共享客户端令牌、单进程内存限流和
并发保护，不依赖数据库或 Redis。

## 配置

```bash
cd server
cp .env.example .env
python -c 'import secrets; print(secrets.token_urlsafe(32))'
```

将生成的随机值作为 `CLIENT_TOKEN`，并在 `.env` 中填写：

```env
VLM_BASE_URL=https://your-openai-compatible-endpoint.example/v1
VLM_API_KEY=your-server-side-key
VLM_MODEL=your-model-id
CLIENT_TOKEN=your-random-client-token-at-least-32-characters
```

`VLM_BASE_URL` 默认必须使用 HTTPS。本地测试明文上游时才可显式设置：

```env
ALLOW_HTTP_UPSTREAM=true
```

主要保护参数：

```env
MAX_CONCURRENT_REQUESTS=4
RATE_LIMIT_REQUESTS=30
RATE_LIMIT_WINDOW_SECONDS=60
UPSTREAM_MAX_ATTEMPTS=2
REQUEST_TIMEOUT_SECONDS=20
MAX_IMAGE_BYTES=2097152
MAX_IMAGE_DIMENSION=4096
```

所有密钥禁止包含空白字符；`CLIENT_TOKEN` 至少 32 位。超时、图片、并发和限流参数
都有启动期范围校验，配置错误时服务会拒绝启动。

## 本地运行

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install .
uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1
```

健康检查：

```bash
curl http://127.0.0.1:8000/health/live
curl http://127.0.0.1:8000/health/ready
```

- `/health/live`：进程存活。
- `/health/ready`：配置已通过启动校验，可以接收识别请求。
- `/health`：兼容旧客户端，内容与 ready 相同。

健康检查不调用上游模型，因此不会产生费用。

## Docker 部署

安装 Docker 后：

```bash
cd server
docker compose up --build -d
docker compose ps
docker compose logs -f cloud-proxy
```

Compose 默认只绑定 `127.0.0.1:8000`。通过 Nginx、Caddy 或云平台负载均衡器提供
公网 HTTPS，再反向代理到该端口。若必须直接暴露端口，可在 `.env` 中设置：

```env
SERVER_BIND_ADDRESS=0.0.0.0
SERVER_PORT=8000
```

不要在公网直接使用 HTTP。容器以非 root 用户和只读文件系统运行，并提供 Docker
健康检查。当前限流器是进程内状态，因此保持一个 Uvicorn worker；少量同事试用足够。

## 手机连接本地服务

USB 真机可通过 ADB reverse 使用电脑的 `127.0.0.1:8000`：

```bash
/mnt/d/LocalData/SDK/platform-tools/adb.exe -P 5038 reverse \
  tcp:8000 tcp:8000

fvm flutter build apk --debug --target-platform android-arm64 \
  --dart-define=CLOUD_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=CLOUD_CLIENT_TOKEN=<same-client-token>
```

打包给同事时，将 `CLOUD_API_BASE_URL` 改为已部署的 HTTPS 地址。客户端不再提供
Mock；缺少地址或令牌时，云端模式会明确显示初始化失败。

`CLOUD_CLIENT_TOKEN` 会进入 APK，只适合受控的内部预研。泄露后应立即更换服务端
`CLIENT_TOKEN` 并重新打包。限流和并发保护用于降低误用和费用风险，不等同于正式
用户鉴权。

## 请求处理与隐私

服务端会：

- 限制上传字节数和图片尺寸；
- 只接受实际解码为 JPEG/PNG 的图片；
- 应用 EXIF 方向、删除元数据，并统一重新编码为 JPEG；
- 不保存上传图片；
- 对上游临时错误执行有上限的指数退避；
- 返回脱敏错误，不向客户端暴露上游 URL、响应体或 Key；
- 记录请求 ID、延迟、模型和 Token 用量，不记录图片或密钥。

仍需根据实际 VLM 供应商确认其图片留存和数据处理条款。

## API 契约

请求为 `POST /api/v1/recognitions`，使用 `multipart/form-data`，并携带：

```text
X-Client-Token: <CLIENT_TOKEN>
```

字段：

- `image`：JPEG 或 PNG，最多由 `MAX_IMAGE_BYTES` 控制；
- `request_id`、`track_id`：请求和端侧目标标识；
- `coarse_label`、`coarse_confidence`：端侧 YOLO 粗识别提示；
- `locale`：形如 `zh-CN` 或 `en-US`。

成功响应：

```json
{
  "request_id": "request-1",
  "track_id": "track-1",
  "name": "棉柔亲肤抽纸",
  "brand": "清风",
  "description": "4层加厚升级，棉柔亲肤",
  "provider": "openai-compatible",
  "model": "your-model-id",
  "latency_ms": 2130,
  "usage": {
    "prompt_tokens": 243,
    "completion_tokens": 31,
    "reasoning_tokens": 0
  }
}
```

常见状态码：`401` 令牌错误、`413/422` 图片错误、`429` 触发限流、`503` 并发已满、
`502` 上游请求或响应失败。响应头 `X-Request-ID` 可用于对应服务端日志。
