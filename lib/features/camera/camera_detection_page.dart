import 'dart:async';
import 'dart:io';

import 'package:aicamera/features/camera/detection_overlay.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/yolo/yolo_detector.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CameraPageState {
  loading,
  ready,
  error,
}

class CameraDetectionPage extends StatefulWidget {
  const CameraDetectionPage({super.key});

  @override
  State<CameraDetectionPage> createState() => _CameraDetectionPageState();
}

class _CameraDetectionPageState extends State<CameraDetectionPage>
    with WidgetsBindingObserver {
  static const _minimumFrameInterval = Duration(milliseconds: 250);

  CameraController? _controller;
  CameraDescription? _camera;
  YoloDetector? _detector;
  DetectionResult? _result;
  CameraPageState _pageState = CameraPageState.loading;
  String? _errorMessage;
  bool _isProcessing = false;
  bool _isStreaming = false;
  bool _isInitializing = false;
  bool _isAppActive = true;
  bool _isDisposed = false;
  DateTime? _lastFrameStartedAt;
  double _confidenceThreshold = 0.35;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _isAppActive = false;
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _isAppActive = true;
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    if (_isDisposed || _isInitializing || _controller != null) {
      return;
    }
    _isInitializing = true;
    setState(() {
      _pageState = CameraPageState.loading;
      _errorMessage = null;
    });

    CameraController? pendingController;
    try {
      final detector = _detector ?? await YoloDetector.load();
      detector.confidenceThreshold = _confidenceThreshold;
      _detector = detector;

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('没有发现可用摄像头，请确认模拟器已启用虚拟摄像头。');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      pendingController = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (!mounted || _isDisposed || !_isAppActive) {
        await controller.dispose();
        pendingController = null;
        return;
      }

      _camera = camera;
      _controller = controller;
      pendingController = null;
      await controller.startImageStream(_onCameraImage);
      _isStreaming = true;
      setState(() {
        _pageState = CameraPageState.ready;
      });
    } on CameraException catch (error) {
      await pendingController?.dispose();
      _setInitializationError(_cameraErrorText(error));
    } catch (error) {
      await pendingController?.dispose();
      _setInitializationError(error.toString());
    } finally {
      _isInitializing = false;
      if (_isAppActive &&
          !_isDisposed &&
          _controller == null &&
          _pageState == CameraPageState.loading) {
        unawaited(_initialize());
      }
    }
  }

  void _onCameraImage(CameraImage image) {
    final detector = _detector;
    final camera = _camera;
    final controller = _controller;
    if (_isDisposed ||
        !_isStreaming ||
        _isProcessing ||
        detector == null ||
        camera == null ||
        controller == null) {
      return;
    }

    final now = DateTime.now();
    final lastFrame = _lastFrameStartedAt;
    if (lastFrame != null &&
        now.difference(lastFrame) < _minimumFrameInterval) {
      return;
    }

    _lastFrameStartedAt = now;
    _isProcessing = true;
    unawaited(
      _processFrame(
        image: image,
        detector: detector,
        camera: camera,
        orientation: controller.value.deviceOrientation,
      ),
    );
  }

  Future<void> _processFrame({
    required CameraImage image,
    required YoloDetector detector,
    required CameraDescription camera,
    required DeviceOrientation orientation,
  }) async {
    try {
      final result = await detector.detect(
        image: image,
        camera: camera,
        orientation: orientation,
      );
      if (mounted && !_isDisposed) {
        setState(() {
          _result = result;
          _errorMessage = null;
        });
      }
    } catch (error) {
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = '当前帧处理失败：$error';
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _toggleStreaming() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      if (_isStreaming) {
        await controller.stopImageStream();
        _isStreaming = false;
      } else {
        await controller.startImageStream(_onCameraImage);
        _isStreaming = true;
      }
      if (mounted) {
        setState(() {});
      }
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = _cameraErrorText(error);
        });
      }
    }
  }

  void _setInitializationError(String message) {
    if (!mounted || _isDisposed) {
      return;
    }
    setState(() {
      _pageState = CameraPageState.error;
      _errorMessage = message;
    });
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    _camera = null;
    _isStreaming = false;
    if (controller == null) {
      return;
    }
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // The platform may already have closed the stream during lifecycle change.
    }
    await controller.dispose();
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    final detector = _detector;
    if (detector != null) {
      unawaited(detector.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_pageState) {
          CameraPageState.loading => const _LoadingView(),
          CameraPageState.error => _ErrorView(
              message: _errorMessage ?? '初始化失败',
              onRetry: _initialize,
            ),
          CameraPageState.ready => _buildCameraView(),
        },
      ),
    );
  }

  Widget _buildCameraView() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const _LoadingView();
    }
    final detections = _result?.detections ?? const <Detection>[];

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(
            controller,
            child: CustomPaint(
              painter: DetectionOverlay(detections),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: _StatusPanel(
            result: _result,
            isStreaming: _isStreaming,
            isProcessing: _isProcessing,
          ),
        ),
        if (_errorMessage != null)
          Positioned(
            left: 12,
            right: 12,
            top: 88,
            child: _InlineError(message: _errorMessage!),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _ControlPanel(
            confidenceThreshold: _confidenceThreshold,
            isStreaming: _isStreaming,
            onThresholdChanged: (value) {
              setState(() {
                _confidenceThreshold = value;
                _detector?.confidenceThreshold = value;
              });
            },
            onToggleStreaming: _toggleStreaming,
          ),
        ),
      ],
    );
  }

  static String _cameraErrorText(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' => '摄像头权限被拒绝，请在系统设置中允许摄像头访问。',
      'CameraAccessDeniedWithoutPrompt' => '摄像头权限已被永久拒绝，请前往系统设置开启。',
      'CameraAccessRestricted' => '当前设备限制了摄像头访问。',
      _ => '摄像头错误（${error.code}）：${error.description ?? '未知错误'}',
    };
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 18),
          Text('正在加载 YOLOv8n 和摄像头…'),
          SizedBox(height: 6),
          Text(
            '320×320 · 纯端侧推理',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.orange),
            const SizedBox(height: 16),
            const Text(
              '无法启动识别',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.result,
    required this.isStreaming,
    required this.isProcessing,
  });

  final DetectionResult? result;
  final bool isStreaming;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final totalMs = result?.totalDuration.inMilliseconds;
    final targetCount = result?.detections.length ?? 0;
    final stateText = !isStreaming
        ? '已暂停'
        : isProcessing
            ? '识别中'
            : '实时';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC10151F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color:
                    isStreaming ? const Color(0xFF66F2B3) : Colors.orangeAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'YOLOv8n · 320 · CPU',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              totalMs == null
                  ? stateText
                  : '$stateText · ${totalMs}ms · $targetCount 个',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6A33B18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.confidenceThreshold,
    required this.isStreaming,
    required this.onThresholdChanged,
    required this.onToggleStreaming,
  });

  final double confidenceThreshold;
  final bool isStreaming;
  final ValueChanged<double> onThresholdChanged;
  final VoidCallback onToggleStreaming;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE6111824),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Row(
          children: [
            Text(
              '阈值 ${(confidenceThreshold * 100).round()}%',
              style: const TextStyle(fontSize: 12),
            ),
            Expanded(
              child: Slider(
                value: confidenceThreshold,
                min: 0.2,
                max: 0.8,
                divisions: 12,
                onChanged: onThresholdChanged,
              ),
            ),
            IconButton.filled(
              onPressed: onToggleStreaming,
              tooltip: isStreaming ? '暂停识别' : '继续识别',
              icon: Icon(isStreaming ? Icons.pause : Icons.play_arrow),
            ),
          ],
        ),
      ),
    );
  }
}
