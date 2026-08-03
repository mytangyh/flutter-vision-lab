import 'dart:isolate';
import 'dart:typed_data';

import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/features/detection/yolo/camera_frame_preprocessor.dart';
import 'package:aicamera/features/detection/yolo/yolo_postprocessor.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloDetector implements DetectionEngine {
  YoloDetector();

  static const modelAsset = 'assets/models/yolov8n_320.tflite';
  static const modelSize = 320;
  static const outputChannels = 84;
  static const predictionCount = 2100;

  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  @override
  double confidenceThreshold = 0.35;

  @override
  String get id => 'yolo_tflite';

  @override
  String get displayName => 'YOLO · TFLite';

  @override
  String get modelName => 'YOLOv8n 320 FP32';

  @override
  String get backendName => 'TFLite 2.11 · CPU';

  @override
  int get threadCount => 4;

  @override
  Future<void> initialize() async {
    if (_interpreter != null) {
      return;
    }
    final options = InterpreterOptions()..threads = 4;
    final interpreter = await Interpreter.fromAsset(
      modelAsset,
      options: options,
    );

    final input = interpreter.getInputTensor(0);
    final output = interpreter.getOutputTensor(0);
    if (!_sameShape(input.shape, [1, 3, modelSize, modelSize])) {
      interpreter.close();
      throw StateError('Unexpected YOLO input shape: ${input.shape}');
    }
    if (!_sameShape(output.shape, [1, outputChannels, predictionCount])) {
      interpreter.close();
      throw StateError('Unexpected YOLO output shape: ${output.shape}');
    }

    final isolateInterpreter = await IsolateInterpreter.create(
      address: interpreter.address,
      debugName: 'YoloV8Inference',
    );
    _interpreter = interpreter;
    _isolateInterpreter = isolateInterpreter;
  }

  @override
  Future<DetectionResult> detect({
    required CameraFrame frame,
  }) async {
    final isolateInterpreter = _isolateInterpreter;
    if (isolateInterpreter == null) {
      throw StateError('YOLO TFLite engine is not initialized.');
    }
    final preprocessWatch = Stopwatch()..start();
    final prepared = await Isolate.run(
      () => prepareYoloFrame(frame, modelSize: modelSize),
      debugName: 'YoloV8Preprocess',
    );
    preprocessWatch.stop();

    final output = Float32List(outputChannels * predictionCount);
    final inferenceWatch = Stopwatch()..start();
    await isolateInterpreter.run(prepared.input.buffer, output.buffer);
    inferenceWatch.stop();

    final postprocessWatch = Stopwatch()..start();
    final postprocessor = YoloPostprocessor(
      confidenceThreshold: confidenceThreshold,
    );
    final detections = await Isolate.run(
      () => postprocessor.process(output, prepared.transform),
      debugName: 'YoloV8Postprocess',
    );
    postprocessWatch.stop();

    return DetectionResult(
      detections: detections,
      preprocessDuration: preprocessWatch.elapsed,
      inferenceDuration: inferenceWatch.elapsed,
      postprocessDuration: postprocessWatch.elapsed,
      frameCapturedAt: frame.capturedAt,
    );
  }

  @override
  Future<void> close() async {
    final isolateInterpreter = _isolateInterpreter;
    _isolateInterpreter = null;
    if (isolateInterpreter != null) {
      await isolateInterpreter.close();
    }
    _interpreter?.close();
    _interpreter = null;
  }

  static bool _sameShape(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) {
      return false;
    }
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) {
        return false;
      }
    }
    return true;
  }
}
