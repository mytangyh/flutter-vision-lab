# AICAMERA 云端识别代理

Flutter 只向此服务上传稳定目标的 JPEG 裁剪图。代理在服务端读取 VLM Key，按
OpenAI Chat Completions 多模态格式调用上游，并返回统一 JSON。上游 Key 不进入
Flutter 构建参数、APK 或 Git。

```text
Flutter --multipart JPEG--> FastAPI --Base64 Data URL--> VLM
        <--统一 JSON-------         <--模型 JSON---------
```

## 本地启动

```bash
cd server
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[test]'
cp .env.example .env
```

只在被 `.gitignore` 排除的 `server/.env` 中填写上游地址、上游密钥和本地联调令牌：

```env
VLM_BASE_URL=https://your-openai-compatible-endpoint.example/v1
VLM_API_KEY=your-server-side-key
CLIENT_TOKEN=replace-with-at-least-32-random-characters
```

仓库不提供默认上游地址，避免在未确认数据处理方时上传相机图像。模型及请求参数可按
所选供应商调整：

```env
VLM_MODEL=doubao-seed-2-1-pro-260628
VLM_DISABLE_THINKING=true
```

启动与检查：

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
curl http://127.0.0.1:8000/health
pytest
```

`/health` 只报告是否已配置 Key，不会返回 Key 内容。

## 手机连接 WSL 本地服务

USB 真机可通过 ADB reverse 使用 WSL 的 `127.0.0.1:8000`：

```bash
/mnt/d/LocalData/SDK/platform-tools/adb.exe -P 5038 reverse \
  tcp:8000 tcp:8000

fvm flutter build apk --debug --target-platform android-arm64 \
  --dart-define=CLOUD_API_BASE_URL=http://127.0.0.1:8000 \
  --dart-define=CLOUD_CLIENT_TOKEN=<same-local-client-token>
```

也可以让手机和电脑处于同一局域网，并把构建参数改为 WSL/Windows 可访问的局域网
地址。配置真实云端地址时必须同时提供 `CLOUD_CLIENT_TOKEN`，否则 App 会拒绝启动
云端客户端。这个共享值会进入 App 构建产物，只适合本地研究联调，不是上游 VLM
Key；正式部署必须替换为业务登录态和短期令牌，并使用 HTTPS、限流和服务端审计。

未设置 `CLOUD_API_BASE_URL` 时，App 使用明确标记的 Mock 结果，便于在无服务端时
验证追踪、稳定触发和 UI 状态流转。

## API 契约

请求为 `POST /api/v1/recognitions`，使用 `multipart/form-data`：

- `image`：JPEG 或 PNG，当前客户端上传最长边不超过 640 的 JPEG。
- `request_id`、`track_id`：请求和端侧目标标识。
- `coarse_label`、`coarse_confidence`：MNN YOLO 粗识别提示。
- `locale`：默认 `zh-CN`。

返回示例：

```json
{
  "request_id": "request-1",
  "track_id": "track-1",
  "name": "棉柔亲肤抽纸",
  "brand": "清风",
  "description": "4层加厚升级，棉柔亲肤",
  "provider": "openai-compatible",
  "model": "doubao-seed-2-1-pro-260628",
  "latency_ms": 2130,
  "usage": {
    "prompt_tokens": 243,
    "completion_tokens": 31,
    "reasoning_tokens": 0
  }
}
```

迁移到云端时保持这个客户端 API 不变，只需替换服务地址，并补充 HTTPS、正式鉴权、
限流、请求审计、数据留存策略和成本告警。
