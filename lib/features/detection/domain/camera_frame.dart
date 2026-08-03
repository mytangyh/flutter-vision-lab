import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

class FramePlaneData {
  const FramePlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class CameraFrame {
  const CameraFrame({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    required this.rotationDegrees,
    required this.mirrorHorizontally,
    required this.capturedAt,
  });

  final int width;
  final int height;
  final String format;
  final List<FramePlaneData> planes;
  final int rotationDegrees;
  final bool mirrorHorizontally;
  final DateTime capturedAt;

  static CameraFrame snapshot({
    required CameraImage image,
    required CameraDescription camera,
    required DeviceOrientation orientation,
  }) {
    return CameraFrame(
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
      rotationDegrees: computeRotationDegrees(
        camera.sensorOrientation,
        orientation,
        camera.lensDirection,
      ),
      mirrorHorizontally: camera.lensDirection == CameraLensDirection.front,
      capturedAt: DateTime.now(),
    );
  }

  static int computeRotationDegrees(
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
}
