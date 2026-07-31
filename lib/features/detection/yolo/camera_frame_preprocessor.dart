import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aicamera/features/detection/yolo/yolo_postprocessor.dart';
import 'package:image/image.dart' as img;

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

class CameraFrameData {
  const CameraFrameData({
    required this.width,
    required this.height,
    required this.format,
    required this.planes,
    required this.rotationDegrees,
    required this.mirrorHorizontally,
  });

  final int width;
  final int height;
  final String format;
  final List<FramePlaneData> planes;
  final int rotationDegrees;
  final bool mirrorHorizontally;
}

class PreparedYoloFrame {
  const PreparedYoloFrame({
    required this.input,
    required this.transform,
  });

  final Float32List input;
  final LetterboxTransform transform;
}

PreparedYoloFrame prepareYoloFrame(
  CameraFrameData frame, {
  int modelSize = 320,
}) {
  var source = _decodeCameraFrame(frame);

  if (frame.rotationDegrees != 0) {
    source = img.copyRotate(source, angle: frame.rotationDegrees);
  }
  if (frame.mirrorHorizontally) {
    img.flipHorizontal(source);
  }

  final scale = math.min(
    modelSize / source.width,
    modelSize / source.height,
  );
  final resizedWidth = math.max(1, (source.width * scale).round());
  final resizedHeight = math.max(1, (source.height * scale).round());
  final padX = ((modelSize - resizedWidth) / 2).floor();
  final padY = ((modelSize - resizedHeight) / 2).floor();

  final resized = img.copyResize(
    source,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: img.Interpolation.linear,
  );
  final letterboxed = img.Image(width: modelSize, height: modelSize);
  img.fill(letterboxed, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(
    letterboxed,
    resized,
    dstX: padX,
    dstY: padY,
    blend: img.BlendMode.direct,
  );

  final channelSize = modelSize * modelSize;
  final input = Float32List(channelSize * 3);
  for (final pixel in letterboxed) {
    final index = (pixel.y * modelSize) + pixel.x;
    input[index] = pixel.rNormalized.toDouble();
    input[channelSize + index] = pixel.gNormalized.toDouble();
    input[(channelSize * 2) + index] = pixel.bNormalized.toDouble();
  }

  return PreparedYoloFrame(
    input: input,
    transform: LetterboxTransform(
      sourceWidth: source.width,
      sourceHeight: source.height,
      modelSize: modelSize,
      scale: scale,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    ),
  );
}

img.Image _decodeCameraFrame(CameraFrameData frame) {
  switch (frame.format) {
    case 'bgra8888':
      return _decodeBgra(frame);
    case 'nv21':
      return _decodeNv21(frame);
    case 'yuv420':
      return _decodeYuv420(frame);
    case 'jpeg':
      final decoded = img.decodeImage(frame.planes.first.bytes);
      if (decoded == null) {
        throw const FormatException('Unable to decode JPEG camera frame.');
      }
      return decoded;
    default:
      throw UnsupportedError('Unsupported camera format: ${frame.format}');
  }
}

img.Image _decodeBgra(CameraFrameData frame) {
  final plane = frame.planes.first;
  final output = img.Image(width: frame.width, height: frame.height);

  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final index = (y * plane.bytesPerRow) + (x * plane.bytesPerPixel);
      output.setPixelRgba(
        x,
        y,
        plane.bytes[index + 2],
        plane.bytes[index + 1],
        plane.bytes[index],
        plane.bytesPerPixel > 3 ? plane.bytes[index + 3] : 255,
      );
    }
  }
  return output;
}

img.Image _decodeNv21(CameraFrameData frame) {
  final plane = frame.planes.first;
  final output = img.Image(width: frame.width, height: frame.height);
  final yPlaneSize = plane.bytesPerRow * frame.height;

  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final yValue = plane.bytes[(y * plane.bytesPerRow) + x];
      final uvIndex = yPlaneSize + ((y ~/ 2) * plane.bytesPerRow) + (x & ~1);
      final vValue = plane.bytes[uvIndex];
      final uValue = plane.bytes[uvIndex + 1];
      _setYuvPixel(output, x, y, yValue, uValue, vValue);
    }
  }
  return output;
}

img.Image _decodeYuv420(CameraFrameData frame) {
  if (frame.planes.length < 3) {
    throw const FormatException('YUV420 frame requires three planes.');
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final output = img.Image(width: frame.width, height: frame.height);

  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final yValue = yPlane.bytes[(y * yPlane.bytesPerRow) + x];
      final uvX = x ~/ 2;
      final uvY = y ~/ 2;
      final uIndex = (uvY * uPlane.bytesPerRow) + (uvX * uPlane.bytesPerPixel);
      final vIndex = (uvY * vPlane.bytesPerRow) + (uvX * vPlane.bytesPerPixel);
      _setYuvPixel(
        output,
        x,
        y,
        yValue,
        uPlane.bytes[uIndex],
        vPlane.bytes[vIndex],
      );
    }
  }
  return output;
}

void _setYuvPixel(
  img.Image output,
  int x,
  int y,
  int yValue,
  int uValue,
  int vValue,
) {
  final chromaU = uValue - 128;
  final chromaV = vValue - 128;
  final red = (yValue + (1.402 * chromaV)).round().clamp(0, 255);
  final green = (yValue - (0.344136 * chromaU) - (0.714136 * chromaV))
      .round()
      .clamp(0, 255);
  final blue = (yValue + (1.772 * chromaU)).round().clamp(0, 255);
  output.setPixelRgb(x, y, red, green, blue);
}
