# AR 相机识别技术预研

基于 Flutter 的相机物体识别技术预研项目，用于验证端侧检测、目标跟踪和
识别结果叠加能力。

## 项目基线

- 项目性质：技术预研 Demo，不直接承载生产业务。
- Flutter：固定使用 `3.27.4`，通过 FVM 配置锁定。
- Dart：使用 Flutter 3.27.4 自带的 Dart 3.6.2。
- 目标平台：Android、iOS；当前优先验证 Android。
- 开发环境：WSL 命令行开发，使用 Windows 侧 Android 模拟器。
- IDE：不依赖 WSL 内安装 Android Studio。

## 预研范围

Demo 阶段保留两条端侧检测链路，在相同输入和设备条件下对比：

1. ML Kit：快速跑通检测、跟踪和画面叠加流程。
2. YOLO：验证既定 YOLO 模型的检测精度、性能和业务兼容性。

现阶段不接入正式业务、不确定最终检测实现，也不引入 ARCore 或 ARKit。

## 环境准备

```bash
fvm use 3.27.4
fvm flutter pub get
```

确认 Windows 模拟器已启动并可从 WSL 的 ADB 访问后运行：

```bash
fvm flutter devices
fvm flutter run
```

## 基础检查

```bash
fvm flutter analyze
fvm flutter test
```
