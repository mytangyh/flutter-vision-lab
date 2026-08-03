import 'dart:async';
import 'dart:io';

import 'package:aicamera/features/benchmark/benchmark_recorder.dart';
import 'package:aicamera/features/camera/detection_overlay.dart';
import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/platform/platform_info.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum CameraPageState { loading, ready, error }

class CameraDetectionPage extends StatefulWidget {
  const CameraDetectionPage({super.key, required this.profile});

  final DetectionProfile profile;

  @override
  State<CameraDetectionPage> createState() => _CameraDetectionPageState();
}

class _CameraDetectionPageState extends State<CameraDetectionPage>
    with WidgetsBindingObserver {
  static const _minimumFrameInterval = Duration(milliseconds: 250);

  final BenchmarkRecorder _benchmark = BenchmarkRecorder();
  CameraController? _controller;
  CameraDescription? _camera;
  DetectionEngine? _engine;
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
  Timer? _benchmarkTimer;
  int _benchmarkSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
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
    if (_isDisposed || _isInitializing || _controller != null) return;
    _isInitializing = true;
    if (mounted) {
      setState(() {
        _pageState = CameraPageState.loading;
        _errorMessage = null;
      });
    }

    CameraController? pendingController;
    try {
      final engine = _engine ?? widget.profile.engineFactory();
      engine.confidenceThreshold = _confidenceThreshold;
      await engine.initialize();
      _engine = engine;

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('没有发现可用摄像头，请确认设备或模拟器摄像头设置。');
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
      setState(() => _pageState = CameraPageState.ready);
    } on CameraException catch (error) {
      await pendingController?.dispose();
      _setInitializationError(_cameraErrorText(error));
    } catch (error) {
      await pendingController?.dispose();
      _setInitializationError(error.toString());
    } finally {
      _isInitializing = false;
    }
  }

  void _onCameraImage(CameraImage image) {
    final engine = _engine;
    final camera = _camera;
    final controller = _controller;
    if (_isDisposed ||
        !_isStreaming ||
        engine == null ||
        camera == null ||
        controller == null) {
      return;
    }
    if (_isProcessing) {
      _benchmark.markDropped();
      return;
    }

    final now = DateTime.now();
    final lastFrame = _lastFrameStartedAt;
    if (!_benchmark.isRecording &&
        lastFrame != null &&
        now.difference(lastFrame) < _minimumFrameInterval) {
      return;
    }
    _lastFrameStartedAt = now;
    _isProcessing = true;
    final frame = CameraFrame.snapshot(
      image: image,
      camera: camera,
      orientation: controller.value.deviceOrientation,
    );
    unawaited(_processFrame(frame, engine));
  }

  Future<void> _processFrame(
    CameraFrame frame,
    DetectionEngine engine,
  ) async {
    try {
      final result = await engine.detect(frame: frame);
      _benchmark.add(result);
      if (mounted && !_isDisposed) {
        setState(() {
          _result = result;
          _errorMessage = null;
        });
      }
    } catch (error) {
      _benchmark.markError();
      if (mounted && !_isDisposed) {
        setState(() => _errorMessage = '当前帧处理失败：$error');
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _toggleStreaming() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      if (_isStreaming) {
        await controller.stopImageStream();
        _isStreaming = false;
      } else {
        await controller.startImageStream(_onCameraImage);
        _isStreaming = true;
      }
      if (mounted) setState(() {});
    } on CameraException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = _cameraErrorText(error));
      }
    }
  }

  void _toggleBenchmark() {
    if (_benchmark.isRecording) {
      unawaited(_stopBenchmark());
      return;
    }
    _benchmark.start();
    _benchmarkSeconds = 0;
    _benchmarkTimer?.cancel();
    _benchmarkTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _benchmarkSeconds++);
      if (_benchmarkSeconds >= BenchmarkRecorder.defaultDuration.inSeconds) {
        unawaited(_stopBenchmark());
      }
    });
    setState(() {});
  }

  Future<void> _stopBenchmark() async {
    if (!_benchmark.isRecording) return;
    _benchmarkTimer?.cancel();
    _benchmarkTimer = null;
    final engine = _engine;
    if (engine == null) return;
    final platform = await PlatformInfo.load();
    final json = await _benchmark.stop(
      profile: widget.profile,
      engine: engine,
      platform: platform,
      confidenceThreshold: _confidenceThreshold,
    );
    if (!mounted) return;
    setState(() {});
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('基准测试已完成'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('JSON 已复制')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('复制'),
          ),
          FilledButton.icon(
            onPressed: () => PlatformInfo.shareJson(json),
            icon: const Icon(Icons.share),
            label: const Text('分享'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _setInitializationError(String message) {
    if (!mounted || _isDisposed) return;
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
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // Android may already have released the camera during a lifecycle change.
    }
    await controller.dispose();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _benchmarkTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    final engine = _engine;
    if (engine != null) unawaited(engine.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_pageState) {
          CameraPageState.loading => _LoadingView(profile: widget.profile),
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
    final engine = _engine;
    if (controller == null ||
        engine == null ||
        !controller.value.isInitialized) {
      return _LoadingView(profile: widget.profile);
    }
    final detections = _result?.detections ?? const <Detection>[];
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(
            controller,
            child: CustomPaint(
              painter: DetectionOverlay(
                detections,
                sourceName: engine.displayName,
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatusPanel(
                  engine: engine,
                  result: _result,
                  isStreaming: _isStreaming,
                  isProcessing: _isProcessing,
                ),
              ),
            ],
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
            isBenchmarking: _benchmark.isRecording,
            benchmarkSeconds: _benchmarkSeconds,
            measuredFrames: _benchmark.measuredFrames,
            onThresholdChanged: (value) {
              setState(() {
                _confidenceThreshold = value;
                engine.confidenceThreshold = value;
              });
            },
            onToggleStreaming: _toggleStreaming,
            onToggleBenchmark: _toggleBenchmark,
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
  const _LoadingView({required this.profile});

  final DetectionProfile profile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text('正在加载 ${profile.title} 和摄像头…'),
          const SizedBox(height: 6),
          Text(
            profile.subtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
    required this.engine,
    required this.result,
    required this.isStreaming,
    required this.isProcessing,
  });

  final DetectionEngine engine;
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    engine.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    engine.backendName,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
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
    required this.isBenchmarking,
    required this.benchmarkSeconds,
    required this.measuredFrames,
    required this.onThresholdChanged,
    required this.onToggleStreaming,
    required this.onToggleBenchmark,
  });

  final double confidenceThreshold;
  final bool isStreaming;
  final bool isBenchmarking;
  final int benchmarkSeconds;
  final int measuredFrames;
  final ValueChanged<double> onThresholdChanged;
  final VoidCallback onToggleStreaming;
  final VoidCallback onToggleBenchmark;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isStreaming ? onToggleBenchmark : null,
                icon: Icon(isBenchmarking ? Icons.stop : Icons.timer_outlined),
                label: Text(
                  isBenchmarking
                      ? '停止基准 · ${benchmarkSeconds}s · $measuredFrames 帧'
                      : '开始 60 秒基准测试',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
