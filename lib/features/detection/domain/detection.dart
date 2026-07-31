import 'dart:ui';

class Detection {
  const Detection({
    required this.classIndex,
    required this.label,
    required this.displayName,
    required this.confidence,
    required this.normalizedRect,
  });

  final int classIndex;
  final String label;
  final String displayName;
  final double confidence;

  /// Coordinates in the oriented camera image, normalized to 0...1.
  final Rect normalizedRect;
}

class DetectionResult {
  const DetectionResult({
    required this.detections,
    required this.preprocessDuration,
    required this.inferenceDuration,
    required this.postprocessDuration,
  });

  final List<Detection> detections;
  final Duration preprocessDuration;
  final Duration inferenceDuration;
  final Duration postprocessDuration;

  Duration get totalDuration =>
      preprocessDuration + inferenceDuration + postprocessDuration;
}
