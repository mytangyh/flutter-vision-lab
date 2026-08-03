import 'dart:convert';

import 'package:aicamera/features/benchmark/benchmark_recorder.dart';
import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/platform/platform_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('excludes warmup frames and exports comparable JSON metrics', () async {
    final recorder = BenchmarkRecorder()..start();
    for (var index = 0; index < 12; index++) {
      recorder.add(
        const DetectionResult(
          detections: [],
          preprocessDuration: Duration(milliseconds: 2),
          inferenceDuration: Duration(milliseconds: 10),
          postprocessDuration: Duration(milliseconds: 3),
        ),
      );
    }
    recorder.markDropped();

    final report = jsonDecode(
      await recorder.stop(
        profile: profile,
        engine: FakeEngine(),
        platform: const PlatformInfo(
          manufacturer: 'test',
          model: 'device',
          androidSdk: 36,
          abi: 'arm64-v8a',
        ),
        confidenceThreshold: 0.35,
      ),
    ) as Map<String, dynamic>;

    expect(report['schemaVersion'], 1);
    expect(report['session']['totalFrames'], 12);
    expect(report['session']['measuredFrames'], 2);
    expect(report['session']['droppedFrames'], 1);
    expect(report['metrics']['inferenceMs']['p95'], 10);
    expect(report['metrics']['totalMs']['mean'], 15);
  });
}

final profile = DetectionProfile(
  id: 'fake',
  title: 'Fake',
  subtitle: 'Fake',
  description: 'Fake',
  iconName: 'memory',
  engineFactory: FakeEngine.new,
);

class FakeEngine implements DetectionEngine {
  @override
  String get backendName => 'fake-backend';

  @override
  double confidenceThreshold = 0.35;

  @override
  String get displayName => 'Fake';

  @override
  String get id => 'fake';

  @override
  String get modelName => 'fake-model';

  @override
  int get threadCount => 1;

  @override
  Future<void> close() async {}

  @override
  Future<DetectionResult> detect({required CameraFrame frame}) {
    throw UnimplementedError();
  }

  @override
  Future<void> initialize() async {}
}
