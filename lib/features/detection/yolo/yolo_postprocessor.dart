import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/yolo/coco_labels.dart';

class LetterboxTransform {
  const LetterboxTransform({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.modelSize,
    required this.scale,
    required this.padX,
    required this.padY,
  });

  final int sourceWidth;
  final int sourceHeight;
  final int modelSize;
  final double scale;
  final double padX;
  final double padY;
}

class YoloPostprocessor {
  const YoloPostprocessor({
    this.confidenceThreshold = 0.35,
    this.iouThreshold = 0.45,
    this.maxDetections = 10,
  });

  final double confidenceThreshold;
  final double iouThreshold;
  final int maxDetections;

  List<Detection> process(
    Float32List output,
    LetterboxTransform transform, {
    int classCount = 80,
  }) {
    final channelCount = 4 + classCount;
    if (output.length % channelCount != 0) {
      throw ArgumentError(
        'Unexpected YOLO output size ${output.length}; '
        'it must be divisible by $channelCount.',
      );
    }

    final predictionCount = output.length ~/ channelCount;
    final candidates = <Detection>[];

    for (var prediction = 0; prediction < predictionCount; prediction++) {
      var bestClass = 0;
      var bestScore = output[(4 * predictionCount) + prediction];

      for (var classIndex = 1; classIndex < classCount; classIndex++) {
        final score = output[((4 + classIndex) * predictionCount) + prediction];
        if (score > bestScore) {
          bestScore = score;
          bestClass = classIndex;
        }
      }

      if (bestScore < confidenceThreshold) {
        continue;
      }

      // The Ultralytics LiteRT export normalizes xywh against the square model
      // input. Convert back to model pixels before undoing letterbox padding.
      final modelSize = transform.modelSize.toDouble();
      final centerX = output[prediction] * modelSize;
      final centerY = output[predictionCount + prediction] * modelSize;
      final width = output[(2 * predictionCount) + prediction] * modelSize;
      final height = output[(3 * predictionCount) + prediction] * modelSize;

      final left = ((centerX - (width / 2) - transform.padX) / transform.scale)
          .clamp(0.0, transform.sourceWidth.toDouble());
      final top = ((centerY - (height / 2) - transform.padY) / transform.scale)
          .clamp(0.0, transform.sourceHeight.toDouble());
      final right = ((centerX + (width / 2) - transform.padX) / transform.scale)
          .clamp(0.0, transform.sourceWidth.toDouble());
      final bottom =
          ((centerY + (height / 2) - transform.padY) / transform.scale)
              .clamp(0.0, transform.sourceHeight.toDouble());

      if (right <= left || bottom <= top) {
        continue;
      }

      candidates.add(
        Detection(
          classIndex: bestClass,
          label: cocoLabels[bestClass],
          displayName: cocoDisplayNames[bestClass],
          confidence: bestScore,
          normalizedRect: Rect.fromLTRB(
            left / transform.sourceWidth,
            top / transform.sourceHeight,
            right / transform.sourceWidth,
            bottom / transform.sourceHeight,
          ),
        ),
      );
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <Detection>[];

    for (final candidate in candidates) {
      final overlaps = selected.any(
        (existing) =>
            existing.classIndex == candidate.classIndex &&
            intersectionOverUnion(
                  existing.normalizedRect,
                  candidate.normalizedRect,
                ) >
                iouThreshold,
      );

      if (!overlaps) {
        selected.add(candidate);
        if (selected.length == maxDetections) {
          break;
        }
      }
    }

    return selected;
  }

  static double intersectionOverUnion(Rect a, Rect b) {
    final intersectionLeft = math.max(a.left, b.left);
    final intersectionTop = math.max(a.top, b.top);
    final intersectionRight = math.min(a.right, b.right);
    final intersectionBottom = math.min(a.bottom, b.bottom);

    final intersectionWidth =
        math.max(0.0, intersectionRight - intersectionLeft);
    final intersectionHeight =
        math.max(0.0, intersectionBottom - intersectionTop);
    final intersectionArea = intersectionWidth * intersectionHeight;
    final unionArea =
        (a.width * a.height) + (b.width * b.height) - intersectionArea;

    return unionArea <= 0 ? 0 : intersectionArea / unionArea;
  }
}
