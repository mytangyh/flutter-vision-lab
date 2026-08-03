import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/domain/detection_engine.dart';
import 'package:aicamera/features/detection/yolo/camera_frame_preprocessor.dart';
import 'package:aicamera/features/detection/yolo/yolo_detector.dart';
import 'package:aicamera/features/detection/yolo/yolo_postprocessor.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

enum MnnBackend {
  cpu,
  openCl,
}

class MnnDetector implements DetectionEngine {
  MnnDetector({
    this.backend = MnnBackend.cpu,
    this.lowPrecision = false,
  });

  static const modelAsset = 'assets/models/yolov8n_320.mnn';
  static const _inputCount =
      3 * YoloDetector.modelSize * YoloDetector.modelSize;
  static const _outputCount =
      YoloDetector.outputChannels * YoloDetector.predictionCount;

  final MnnBackend backend;
  final bool lowPrecision;
  _MnnBindings? _bindings;
  Pointer<Void> _handle = nullptr;

  @override
  String get id =>
      backend == MnnBackend.cpu ? 'yolo_mnn_cpu' : 'yolo_mnn_opencl';

  @override
  String get displayName => 'YOLO · MNN';

  @override
  String get modelName => 'YOLOv8n 320 FP32';

  @override
  String get backendName =>
      'MNN 3.5 · ${backend == MnnBackend.cpu ? 'CPU' : 'OpenCL'}'
      '${lowPrecision ? ' · Low Precision' : ''}';

  @override
  int get threadCount => 4;

  @override
  double confidenceThreshold = 0.35;

  @override
  Future<void> initialize() async {
    if (_handle != nullptr) {
      return;
    }
    final bindings = _MnnBindings.open();
    final model = await rootBundle.load(modelAsset);
    final bytes =
        model.buffer.asUint8List(model.offsetInBytes, model.lengthInBytes);
    final nativeModel = calloc<Uint8>(bytes.length);
    nativeModel.asTypedList(bytes.length).setAll(0, bytes);
    try {
      _handle = bindings.create(
        nativeModel,
        bytes.length,
        threadCount,
        backend == MnnBackend.openCl ? 3 : 0,
        lowPrecision ? 1 : 0,
      );
    } finally {
      calloc.free(nativeModel);
    }
    if (_handle == nullptr) {
      throw StateError('MNN initialization failed: ${bindings.error(nullptr)}');
    }
    _bindings = bindings;
  }

  @override
  Future<DetectionResult> detect({required CameraFrame frame}) async {
    final bindings = _bindings;
    final handle = _handle;
    if (bindings == null || handle == nullptr) {
      throw StateError('MNN engine is not initialized.');
    }

    final preprocessWatch = Stopwatch()..start();
    final prepared = await Isolate.run(
      () => prepareYoloFrame(frame, modelSize: YoloDetector.modelSize),
      debugName: 'MnnYoloPreprocess',
    );
    preprocessWatch.stop();

    final handleAddress = handle.address;
    final input = prepared.input;
    final inferenceWatch = Stopwatch()..start();
    final output = await Isolate.run(() {
      final isolateBindings = _MnnBindings.open();
      final isolateHandle = Pointer<Void>.fromAddress(handleAddress);
      final inputPointer = calloc<Float>(_inputCount);
      final outputPointer = calloc<Float>(_outputCount);
      try {
        inputPointer.asTypedList(_inputCount).setAll(0, input);
        final result = isolateBindings.run(
          isolateHandle,
          inputPointer,
          _inputCount,
          outputPointer,
          _outputCount,
        );
        if (result != 0) {
          throw StateError(
            'MNN inference failed: ${isolateBindings.error(isolateHandle)}',
          );
        }
        return Float32List.fromList(
          outputPointer.asTypedList(_outputCount),
        );
      } finally {
        calloc.free(inputPointer);
        calloc.free(outputPointer);
      }
    }, debugName: 'MnnYoloInference');
    inferenceWatch.stop();

    final postprocessWatch = Stopwatch()..start();
    final postprocessor = YoloPostprocessor(
      confidenceThreshold: confidenceThreshold,
    );
    final detections = await Isolate.run(
      () => postprocessor.process(output, prepared.transform),
      debugName: 'MnnYoloPostprocess',
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
    if (_handle != nullptr) {
      _bindings?.destroy(_handle);
    }
    _handle = nullptr;
    _bindings = null;
  }
}

typedef _CreateNative = Pointer<Void> Function(
  Pointer<Uint8>,
  IntPtr,
  Int32,
  Int32,
  Int32,
);
typedef _CreateDart = Pointer<Void> Function(
  Pointer<Uint8>,
  int,
  int,
  int,
  int,
);
typedef _RunNative = Int32 Function(
  Pointer<Void>,
  Pointer<Float>,
  IntPtr,
  Pointer<Float>,
  IntPtr,
);
typedef _RunDart = int Function(
  Pointer<Void>,
  Pointer<Float>,
  int,
  Pointer<Float>,
  int,
);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _ErrorNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _ErrorDart = Pointer<Utf8> Function(Pointer<Void>);

class _MnnBindings {
  _MnnBindings(DynamicLibrary library)
      : create = library.lookupFunction<_CreateNative, _CreateDart>(
          'aicamera_mnn_create',
        ),
        run = library.lookupFunction<_RunNative, _RunDart>(
          'aicamera_mnn_run',
        ),
        destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
          'aicamera_mnn_destroy',
        ),
        _lastError = library.lookupFunction<_ErrorNative, _ErrorDart>(
          'aicamera_mnn_last_error',
        );

  factory _MnnBindings.open() {
    return _MnnBindings(DynamicLibrary.open('libaicamera_mnn.so'));
  }

  final _CreateDart create;
  final _RunDart run;
  final _DestroyDart destroy;
  final _ErrorDart _lastError;

  String error(Pointer<Void> handle) {
    final value = _lastError(handle);
    return value == nullptr ? 'unknown native error' : value.toDartString();
  }
}
