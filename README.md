# Flutter Vision Lab

Flutter 相机识别技术预研 App。当前工程不把某一种推理框架当作最终结论，而是让
四条实现使用同一套相机输入、检测框 UI、置信度阈值和基准统计，便于在真机上直接
对比效果：

- YOLOv8n 320 + TFLite CPU：已验证的纯端侧基线。
- YOLOv8n 320 + MNN 3.5 CPU：官方 Native API + Dart FFI。
- Google ML Kit Object Detection：通用检测/粗分类对照。
- MNN YOLO 端侧定位 + 云端 VLM：目标稳定后自动裁剪上传并补充精细名称。

## 固定基线

- Flutter 固定为 `3.27.4`，Dart 为随附的 `3.6.2`。
- Android 优先，`minSdk 21` 保持不变；ML Kit 入口在 API 21–22 禁用。
- 开发环境为 WSL 命令行，不要求在 WSL 安装 Android Studio。
- YOLO 两种引擎使用相同权重、输入尺寸、前后处理和 COCO 80 类标签。
- 当前为技术预研 Demo，不直接承载生产业务。

## 工程结构

```text
lib/
├── features/home/               # 四种方案入口与兼容性提示
├── features/camera/             # 共用相机生命周期、预览和控制
├── features/benchmark/          # 统一 60 秒基准及 JSON 报告
└── features/detection/
    ├── domain/                  # 框架无关的帧、引擎和检测结果
    ├── yolo/                    # TFLite 引擎、前后处理
    ├── mnn/                     # MNN 3.5 FFI 引擎
    ├── mlkit/                   # ML Kit 引擎
    ├── tracking/                # 云端触发所需的稳定目标追踪
    └── cloud/                   # 裁剪上传及结果增强
android/app/src/main/cpp/        # MNN 官方 C++ API 桥
server/                          # FastAPI + OpenAI-compatible VLM 代理
tools/convert_mnn_model.sh       # 固定 MNN 3.5 的模型转换脚本
```

## 本地运行

```bash
fvm flutter --version
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter run -d <device-id>
```

版本必须显示 Flutter `3.27.4`。首次 Android Native 构建会获取 MNN 3.5
源码并编译目标 ABI，因此比普通 Flutter 构建慢。所需 NDK 版本由 Flutter 基线
统一指定。

连接 Windows 侧手机时，可以让 Flutter/adb 使用同一 ADB server；也可以直接
构建并由 Windows adb 安装：

```bash
fvm flutter build apk --debug --target-platform android-arm64
/mnt/d/LocalData/SDK/platform-tools/adb.exe install -r \
  build/app/outputs/flutter-apk/app-debug.apk
```

## 基准测试

每个识别页面底部都可以启动 60 秒测试。前 10 帧为 warm-up，不进入延迟统计；
报告记录设备、ABI、模型、后端、线程数、阈值、处理帧数、丢帧数、检测数以及
预处理/推理/后处理的 mean、P50、P90、P95。报告可复制或通过 Android 分享面板
导出为 JSON。

同一轮方案比较应使用同一部手机、相同画面、相同阈值，并在设备温度稳定后各跑
至少三次。模拟器数据只能验证功能，不作为性能结论。

## MNN 模型

仓库内 `.mnn` 文件由相同的 TFLite 模型转换，不另行训练：

```bash
tools/convert_mnn_model.sh
```

脚本固定 MNN `3.5.0` 并输出 SHA-256。模型输入/输出契约和许可证提示见
`assets/models/README.md`。

## 云端识别

云端模式必须连接真实代理，不再提供 Mock 回退。启动代理及环境变量说明见
`server/README.md`。连接方式：

```bash
fvm flutter run \
  --dart-define=CLOUD_API_BASE_URL=http://<server-ip>:8000 \
  --dart-define=CLOUD_CLIENT_TOKEN=<token>
```

VLM 密钥只配置在 FastAPI 服务端，不能写入 App。云端模式进入前会显示上传说明；
当前实现上传的仅是稳定检测框加少量边距后的 JPEG 裁剪图。USB 真机联调建议通过
`adb reverse tcp:8000 tcp:8000` 访问 WSL 本地代理，具体步骤见 `server/README.md`。
仓库不内置任何云端上游地址；缺少 `CLOUD_API_BASE_URL` 或
`CLOUD_CLIENT_TOKEN` 时云端页面会明确显示初始化错误。启用真实云端模式前必须
自行配置并确认供应商的数据处理条款。`CLOUD_CLIENT_TOKEN` 会进入 App 构建产物，
只适合受控的内部预研。

## 已知边界

- YOLOv8n 当前是通用 COCO 模型，不包含业务定制类别。
- 云端代理使用单进程内存限流和共享客户端令牌，适合少量内部试用，不面向正式用户。
- 当前 MNN 入口以 CPU 为首轮公平对照，OpenCL 开关已在引擎和 Native 层预留，
  应在 CPU 数据稳定后单独测试。
- 尚需积累多机型的性能、功耗、温升、长时间稳定性和识别效果数据。

## 许可证

本项目以 GNU Affero General Public License v3.0 发布，完整条款见 `LICENSE`。
仓库包含由 Ultralytics YOLOv8 权重导出的模型；如需闭源、内部或商业使用，请先
确认 Ultralytics 的适用许可，必要时取得企业许可或更换模型。
