import 'dart:isolate';
import 'dart:typed_data';

import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/yolo/camera_frame_preprocessor.dart';
import 'package:aicamera/features/detection/yolo/yolo_postprocessor.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloDetector {
  YoloDetector._({
    required Interpreter interpreter,
    required IsolateInterpreter isolateInterpreter,
  })  : _interpreter = interpreter,
        _isolateInterpreter = isolateInterpreter;

  static const modelAsset = 'assets/models/yolov8n_320.tflite';
  static const modelSize = 320;
  static const outputChannels = 84;
  static const predictionCount = 2100;

  final Interpreter _interpreter;
  final IsolateInterpreter _isolateInterpreter;
  double confidenceThreshold = 0.35;

  static Future<YoloDetector> load() async {
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
    return YoloDetector._(
      interpreter: interpreter,
      isolateInterpreter: isolateInterpreter,
    );
  }

  Future<DetectionResult> detect({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation orientation,
  }) async {
    final preprocessWatch = Stopwatch()..start();
    final frame = _snapshotFrame(image, camera, orientation);
    final prepared = await Isolate.run(
      () => prepareYoloFrame(frame, modelSize: modelSize),
      debugName: 'YoloV8Preprocess',
    );
    preprocessWatch.stop();

    final output = Float32List(outputChannels * predictionCount);
    final inferenceWatch = Stopwatch()..start();
    await _isolateInterpreter.run(prepared.input.buffer, output.buffer);
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
    );
  }

  Future<void> close() async {
    await _isolateInterpreter.close();
    _interpreter.close();
  }

  static CameraFrameData _snapshotFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    return CameraFrameData(
      width: image.width,
      height: image.height,
      format: image.format.group.name,
      planes: image.planes
          .map(
            (plane) => FramePlaneData(
              bytes: Uint8List.fromList(plane.bytes),
              bytesPerRow: plane.bytesPerRow,
              bytesPerPixel: plane.bytesPerPixel ?? 1,
            ),
          )
          .toList(growable: false),
      rotationDegrees: _rotationDegrees(
        camera.sensorOrientation,
        orientation,
        camera.lensDirection,
      ),
      mirrorHorizontally: camera.lensDirection == CameraLensDirection.front,
    );
  }

  static int _rotationDegrees(
    int sensorOrientation,
    DeviceOrientation orientation,
    CameraLensDirection lensDirection,
  ) {
    final deviceDegrees = switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    if (lensDirection == CameraLensDirection.front) {
      return (sensorOrientation + deviceDegrees) % 360;
    }
    return (sensorOrientation - deviceDegrees + 360) % 360;
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
