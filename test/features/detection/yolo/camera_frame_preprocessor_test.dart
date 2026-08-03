import 'dart:typed_data';

import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/yolo/camera_frame_preprocessor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts BGRA pixels to normalized NCHW RGB with letterbox padding',
      () {
    final frame = CameraFrame(
      width: 2,
      height: 1,
      format: 'bgra8888',
      planes: [
        FramePlaneData(
          bytes: Uint8List.fromList([
            0,
            0,
            255,
            255,
            0,
            255,
            0,
            255,
          ]),
          bytesPerRow: 8,
          bytesPerPixel: 4,
        ),
      ],
      rotationDegrees: 0,
      mirrorHorizontally: false,
      capturedAt: DateTime(2026),
    );

    final prepared = prepareYoloFrame(frame, modelSize: 2);

    expect(prepared.input, hasLength(12));
    expect(prepared.input[0], closeTo(1, 0.0001));
    expect(prepared.input[1], closeTo(0, 0.0001));
    expect(prepared.input[4], closeTo(0, 0.0001));
    expect(prepared.input[5], closeTo(1, 0.0001));
    expect(prepared.input[8], closeTo(0, 0.0001));
    expect(prepared.input[9], closeTo(0, 0.0001));
    expect(prepared.input[2], closeTo(114 / 255, 0.0001));
    expect(prepared.transform.sourceWidth, 2);
    expect(prepared.transform.sourceHeight, 1);
    expect(prepared.transform.scale, 1);
  });
}
