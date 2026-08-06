import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/platform/app_platform.dart';

abstract interface class DetectionEngine {
  String get id;
  String get displayName;
  String get modelName;
  String get backendName;
  int? get threadCount;

  double get confidenceThreshold;
  set confidenceThreshold(double value);

  Future<void> initialize();
  Future<DetectionResult> detect({required CameraFrame frame});
  Future<void> close();
}

typedef DetectionEngineFactory = DetectionEngine Function();

class DetectionProfile {
  const DetectionProfile({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.iconName,
    required this.engineFactory,
    this.supportedPlatforms = const {
      AppPlatform.android,
      AppPlatform.ios,
    },
    this.minimumAndroidSdk,
    this.cloudEnabled = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String iconName;
  final DetectionEngineFactory engineFactory;
  final Set<AppPlatform> supportedPlatforms;
  final int? minimumAndroidSdk;
  final bool cloudEnabled;
}
