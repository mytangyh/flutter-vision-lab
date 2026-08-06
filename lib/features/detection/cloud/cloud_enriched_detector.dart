import 'dart:async';

import 'package:aicamera/features/detection/cloud/cloud_recognition_client.dart';
import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/features/detection/tracking/iou_tracker.dart';

class CloudEnrichedDetector implements DetectionEngine {
  CloudEnrichedDetector({
    required this.delegate,
    CloudRecognitionClient? client,
    IouTracker? tracker,
  })  : _client = client ?? CloudRecognitionClient.fromEnvironment(),
        _tracker = tracker ?? IouTracker();

  final DetectionEngine delegate;
  final CloudRecognitionClient _client;
  final IouTracker _tracker;

  @override
  String get id => '${delegate.id}_cloud';

  @override
  String get displayName => '${delegate.displayName} + Cloud VLM';

  @override
  String get modelName => '${delegate.modelName} + VLM';

  @override
  String get backendName => '${delegate.backendName} + Cloud';

  @override
  int? get threadCount => delegate.threadCount;

  @override
  double get confidenceThreshold => delegate.confidenceThreshold;

  @override
  set confidenceThreshold(double value) {
    delegate.confidenceThreshold = value;
  }

  @override
  Future<void> initialize() => delegate.initialize();

  @override
  Future<DetectionResult> detect({required CameraFrame frame}) async {
    final local = await delegate.detect(frame: frame);
    final update = _tracker.update(local.detections, frame.capturedAt);
    for (final detection in update.newlyStable.take(3)) {
      final trackId = detection.trackId;
      if (trackId == null) {
        continue;
      }
      _tracker.markPending(trackId);
      unawaited(_enrich(frame, detection));
    }
    return DetectionResult(
      detections: update.detections.map(_tracker.decorate).toList(),
      preprocessDuration: local.preprocessDuration,
      inferenceDuration: local.inferenceDuration,
      postprocessDuration: local.postprocessDuration,
      frameCapturedAt: local.frameCapturedAt,
    );
  }

  Future<void> _enrich(CameraFrame frame, Detection detection) async {
    final trackId = detection.trackId;
    if (trackId == null) {
      return;
    }
    try {
      final result = await _client.recognize(
        frame: frame,
        detection: detection,
      );
      _tracker.markEnriched(
        trackId,
        name: _displayName(result),
        description: result.description,
      );
    } catch (_) {
      _tracker.markFailed(trackId);
    }
  }

  String _displayName(CloudRecognition recognition) {
    final brand = recognition.brand?.trim();
    if (brand == null || brand.isEmpty || recognition.name.contains(brand)) {
      return recognition.name;
    }
    return '$brand · ${recognition.name}';
  }

  @override
  Future<void> close() async {
    _client.close();
    await delegate.close();
  }
}
