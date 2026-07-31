import 'dart:typed_data';
import 'dart:ui';

import 'package:aicamera/features/detection/yolo/yolo_postprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const transform = LetterboxTransform(
    sourceWidth: 320,
    sourceHeight: 320,
    modelSize: 320,
    scale: 1,
    padX: 0,
    padY: 0,
  );

  test('decodes YOLO channel-first output into normalized detections', () {
    final output = _outputFor([
      const _Prediction(
        centerX: 0.5,
        centerY: 0.5,
        width: 0.25,
        height: 0.125,
        classIndex: 67,
        confidence: 0.9,
      ),
    ]);

    final detections = const YoloPostprocessor().process(output, transform);

    expect(detections, hasLength(1));
    expect(detections.single.label, 'cell phone');
    expect(detections.single.displayName, '手机');
    expect(detections.single.normalizedRect,
        const Rect.fromLTRB(0.375, 0.4375, 0.625, 0.5625));
  });

  test('applies class-aware non-maximum suppression', () {
    final output = _outputFor([
      const _Prediction(
        centerX: 0.3125,
        centerY: 0.3125,
        width: 0.25,
        height: 0.25,
        classIndex: 0,
        confidence: 0.95,
      ),
      const _Prediction(
        centerX: 0.31875,
        centerY: 0.31875,
        width: 0.25,
        height: 0.25,
        classIndex: 0,
        confidence: 0.8,
      ),
      const _Prediction(
        centerX: 0.31875,
        centerY: 0.31875,
        width: 0.25,
        height: 0.25,
        classIndex: 15,
        confidence: 0.75,
      ),
    ]);

    final detections = const YoloPostprocessor().process(output, transform);

    expect(detections, hasLength(2));
    expect(
        detections.map((item) => item.label), containsAll(['person', 'cat']));
  });

  test('undoes letterbox padding before normalizing coordinates', () {
    const portraitTransform = LetterboxTransform(
      sourceWidth: 180,
      sourceHeight: 320,
      modelSize: 320,
      scale: 1,
      padX: 70,
      padY: 0,
    );
    final output = _outputFor([
      const _Prediction(
        centerX: 0.5,
        centerY: 0.5,
        width: 0.28125,
        height: 0.5,
        classIndex: 39,
        confidence: 0.85,
      ),
    ]);

    final detection =
        const YoloPostprocessor().process(output, portraitTransform).single;

    expect(detection.normalizedRect.left, closeTo(0.25, 0.0001));
    expect(detection.normalizedRect.top, closeTo(0.25, 0.0001));
    expect(detection.normalizedRect.right, closeTo(0.75, 0.0001));
    expect(detection.normalizedRect.bottom, closeTo(0.75, 0.0001));
  });
}

Float32List _outputFor(List<_Prediction> predictions) {
  final count = predictions.length;
  final output = Float32List(84 * count);
  for (var index = 0; index < count; index++) {
    final prediction = predictions[index];
    output[index] = prediction.centerX;
    output[count + index] = prediction.centerY;
    output[(2 * count) + index] = prediction.width;
    output[(3 * count) + index] = prediction.height;
    output[((4 + prediction.classIndex) * count) + index] =
        prediction.confidence;
  }
  return output;
}

class _Prediction {
  const _Prediction({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
    required this.classIndex,
    required this.confidence,
  });

  final double centerX;
  final double centerY;
  final double width;
  final double height;
  final int classIndex;
  final double confidence;
}
