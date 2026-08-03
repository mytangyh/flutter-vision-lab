import 'dart:ui';

import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class MlKitDetector implements DetectionEngine {
  ObjectDetector? _detector;

  @override
  String get id => 'mlkit';

  @override
  String get displayName => 'ML Kit';

  @override
  String get modelName => 'ML Kit Object Detection';

  @override
  String get backendName => 'Google ML Kit · Native';

  @override
  int? get threadCount => null;

  @override
  double confidenceThreshold = 0.35;

  @override
  Future<void> initialize() async {
    _detector ??= ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  @override
  Future<DetectionResult> detect({required CameraFrame frame}) async {
    final detector = _detector;
    if (detector == null) {
      throw StateError('ML Kit engine is not initialized.');
    }
    if (frame.planes.length != 1) {
      throw UnsupportedError(
        'ML Kit stream requires a single NV21/BGRA plane; '
        'received ${frame.planes.length} planes.',
      );
    }

    final inputFormat = switch (frame.format) {
      'nv21' => InputImageFormat.nv21,
      'bgra8888' => InputImageFormat.bgra8888,
      _ => throw UnsupportedError('Unsupported ML Kit format: ${frame.format}'),
    };
    final rotation = InputImageRotationValue.fromRawValue(
      frame.rotationDegrees,
    );
    if (rotation == null) {
      throw UnsupportedError(
        'Unsupported ML Kit rotation: ${frame.rotationDegrees}',
      );
    }

    final watch = Stopwatch()..start();
    final objects = await detector.processImage(
      InputImage.fromBytes(
        bytes: frame.planes.first.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: rotation,
          format: inputFormat,
          bytesPerRow: frame.planes.first.bytesPerRow,
        ),
      ),
    );
    watch.stop();

    final rotated = frame.rotationDegrees == 90 || frame.rotationDegrees == 270;
    final outputWidth =
        rotated ? frame.height.toDouble() : frame.width.toDouble();
    final outputHeight =
        rotated ? frame.width.toDouble() : frame.height.toDouble();
    final detections = <Detection>[];

    for (final object in objects) {
      final label = object.labels.isEmpty ? null : object.labels.first;
      final score = label?.confidence ?? 1.0;
      if (score < confidenceThreshold) {
        continue;
      }
      final rect = object.boundingBox;
      detections.add(
        Detection(
          classIndex: label?.index ?? -1,
          label: label?.text ?? 'object',
          displayName: _displayName(label?.text),
          confidence: score,
          normalizedRect: Rect.fromLTRB(
            (rect.left / outputWidth).clamp(0.0, 1.0),
            (rect.top / outputHeight).clamp(0.0, 1.0),
            (rect.right / outputWidth).clamp(0.0, 1.0),
            (rect.bottom / outputHeight).clamp(0.0, 1.0),
          ),
          trackId: object.trackingId?.toString(),
        ),
      );
    }

    return DetectionResult(
      detections: detections,
      preprocessDuration: Duration.zero,
      inferenceDuration: watch.elapsed,
      postprocessDuration: Duration.zero,
      frameCapturedAt: frame.capturedAt,
    );
  }

  @override
  Future<void> close() async {
    final detector = _detector;
    _detector = null;
    await detector?.close();
  }

  static String _displayName(String? label) {
    return switch (label?.toLowerCase()) {
      'home good' || 'home goods' => '家居用品',
      'fashion good' || 'fashion goods' => '服饰',
      'food' => '食物',
      'plant' || 'plants' => '植物',
      'place' || 'places' => '地点',
      _ => '物体',
    };
  }
}
