import 'dart:convert';

import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/platform/platform_info.dart';

class BenchmarkRecorder {
  static const warmupFrames = 10;
  static const defaultDuration = Duration(seconds: 60);

  final List<BenchmarkSample> _samples = [];
  DateTime? _startedAt;
  int droppedFrames = 0;
  int errors = 0;

  bool get isRecording => _startedAt != null;
  DateTime? get startedAt => _startedAt;
  int get totalFrames => _samples.length;
  int get measuredFrames =>
      (_samples.length - warmupFrames).clamp(0, _samples.length).toInt();

  void start() {
    _samples.clear();
    droppedFrames = 0;
    errors = 0;
    _startedAt = DateTime.now();
  }

  void add(DetectionResult result) {
    if (!isRecording) {
      return;
    }
    _samples.add(
      BenchmarkSample(
        preprocessMicros: result.preprocessDuration.inMicroseconds,
        inferenceMicros: result.inferenceDuration.inMicroseconds,
        postprocessMicros: result.postprocessDuration.inMicroseconds,
        detectionCount: result.detections.length,
      ),
    );
  }

  void markDropped() {
    if (isRecording) {
      droppedFrames++;
    }
  }

  void markError() {
    if (isRecording) {
      errors++;
    }
  }

  Future<String> stop({
    required DetectionProfile profile,
    required DetectionEngine engine,
    required PlatformInfo platform,
    required double confidenceThreshold,
  }) async {
    final startedAt = _startedAt ?? DateTime.now();
    final endedAt = DateTime.now();
    _startedAt = null;
    final measured = _samples.skip(warmupFrames).toList(growable: false);
    final durationSeconds =
        endedAt.difference(startedAt).inMilliseconds / 1000.0;

    final report = <String, Object?>{
      'schemaVersion': 1,
      'device': platform.toJson(),
      'engine': {
        'profileId': profile.id,
        'engineId': engine.id,
        'displayName': engine.displayName,
        'model': engine.modelName,
        'backend': engine.backendName,
        'threads': engine.threadCount,
        'confidenceThreshold': confidenceThreshold,
      },
      'session': {
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'durationMs': endedAt.difference(startedAt).inMilliseconds,
        'warmupFrames': warmupFrames,
        'totalFrames': _samples.length,
        'measuredFrames': measured.length,
        'droppedFrames': droppedFrames,
        'errors': errors,
      },
      'metrics': {
        'processedFps':
            durationSeconds <= 0 ? 0 : measured.length / durationSeconds,
        'averageDetectionCount': measured.isEmpty
            ? 0
            : measured
                    .map((item) => item.detectionCount)
                    .reduce((a, b) => a + b) /
                measured.length,
        'preprocessMs':
            _durationSummary(measured.map((item) => item.preprocessMicros)),
        'inferenceMs':
            _durationSummary(measured.map((item) => item.inferenceMicros)),
        'postprocessMs':
            _durationSummary(measured.map((item) => item.postprocessMicros)),
        'totalMs': _durationSummary(measured.map((item) => item.totalMicros)),
      },
    };
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  static Map<String, double> _durationSummary(Iterable<int> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) {
      return const {'mean': 0, 'p50': 0, 'p90': 0, 'p95': 0};
    }
    final mean = sorted.reduce((a, b) => a + b) / sorted.length / 1000.0;
    return {
      'mean': mean,
      'p50': _percentile(sorted, 0.50) / 1000.0,
      'p90': _percentile(sorted, 0.90) / 1000.0,
      'p95': _percentile(sorted, 0.95) / 1000.0,
    };
  }

  static double _percentile(List<int> sorted, double percentile) {
    final index = (sorted.length - 1) * percentile;
    final lower = index.floor();
    final upper = index.ceil();
    if (lower == upper) {
      return sorted[lower].toDouble();
    }
    final fraction = index - lower;
    return sorted[lower] + ((sorted[upper] - sorted[lower]) * fraction);
  }
}

class BenchmarkSample {
  const BenchmarkSample({
    required this.preprocessMicros,
    required this.inferenceMicros,
    required this.postprocessMicros,
    required this.detectionCount,
  });

  final int preprocessMicros;
  final int inferenceMicros;
  final int postprocessMicros;
  final int detectionCount;

  int get totalMicros => preprocessMicros + inferenceMicros + postprocessMicros;
}
