# AICAMERA

Flutter 端侧相机物体识别技术预研。当前 MVP 已优先跑通 YOLO：
实时相机帧 → 图像预处理 → TFLite 推理 → NMS → 预览画面检测框。

## 项目基线

- 项目性质：技术预研 Demo，不直接承载生产业务。
- Flutter：固定使用 `3.27.4`，通过 FVM 配置锁定。
- Dart：使用 Flutter 3.27.4 自带的 Dart 3.6.2。
- 目标平台：Android、iOS；当前优先验证 Android。
- 开发环境：WSL 命令行开发，使用 Windows 侧 Android 模拟器。
- IDE：不依赖 WSL 内安装 Android Studio。

## 当前能力

- 后置相机实时画面和运行时相机权限。
- YOLOv8n 320×320 FP32 TFLite、COCO 80 类。
- Android NV21/YUV420 与 iOS BGRA 帧转换。
- 旋转、前置镜像、letterbox 及检测框坐标还原。
- 类别级 NMS、置信度调节、暂停/继续。
- 实时显示预处理、推理、后处理耗时。

ML Kit 对比链路属于下一阶段，届时应在相同输入和设备条件下记录精度、
耗时和资源占用。当前不引入 ARCore 或 ARKit。

## 工程结构

```text
lib/
├── features/camera/              # 相机生命周期、预览与检测框 UI
└── features/detection/
    ├── domain/                   # 与推理框架无关的检测结果
    └── yolo/                     # 帧预处理、TFLite 推理、后处理
assets/models/                    # 模型及模型说明
```

## 环境准备

```bash
fvm flutter --version
fvm flutter pub get
```

版本必须显示 Flutter `3.27.4`。确认 Windows 模拟器已启动并能从 WSL
访问后运行：

```bash
fvm flutter devices
fvm flutter run -d <device-id>
```

模拟器没有真实摄像头时，需要在 AVD 设置中把 Back Camera 配置为
`VirtualScene` 或宿主机摄像头。也可以先只构建 APK：

```bash
fvm flutter build apk --debug
```

产物位于 `build/app/outputs/flutter-apk/app-debug.apk`。

## 质量检查

```bash
fvm flutter analyze
fvm flutter test
```

## 已知边界

- 这是技术预研 MVP，尚未完成真机性能、功耗、温升和长期稳定性验证。
- 模拟器摄像头及 CPU 推理性能不能代表真机。
- 当前模型识别 COCO 80 类，不包含业务定制类别。
- YOLO 模型来源、导出参数、校验值和许可证提示见
  `assets/models/README.md`；进入正式业务前必须完成模型与依赖的许可证评审。
