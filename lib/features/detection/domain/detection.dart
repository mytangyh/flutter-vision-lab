import 'dart:ui';

class Detection {
  const Detection({
    required this.classIndex,
    required this.label,
    required this.displayName,
    required this.confidence,
    required this.normalizedRect,
    this.trackId,
    this.description,
    this.enrichmentState = EnrichmentState.local,
  });

  final int classIndex;
  final String label;
  final String displayName;
  final double confidence;

  /// Coordinates in the oriented camera image, normalized to 0...1.
  final Rect normalizedRect;
  final String? trackId;
  final String? description;
  final EnrichmentState enrichmentState;

  Detection copyWith({
    String? displayName,
    String? trackId,
    String? description,
    EnrichmentState? enrichmentState,
  }) {
    return Detection(
      classIndex: classIndex,
      label: label,
      displayName: displayName ?? this.displayName,
      confidence: confidence,
      normalizedRect: normalizedRect,
      trackId: trackId ?? this.trackId,
      description: description ?? this.description,
      enrichmentState: enrichmentState ?? this.enrichmentState,
    );
  }
}

enum EnrichmentState {
  local,
  pending,
  enriched,
  failed,
}

class DetectionResult {
  const DetectionResult({
    required this.detections,
    required this.preprocessDuration,
    required this.inferenceDuration,
    required this.postprocessDuration,
    this.frameCapturedAt,
  });

  final List<Detection> detections;
  final Duration preprocessDuration;
  final Duration inferenceDuration;
  final Duration postprocessDuration;
  final DateTime? frameCapturedAt;

  Duration get totalDuration =>
      preprocessDuration + inferenceDuration + postprocessDuration;
}
