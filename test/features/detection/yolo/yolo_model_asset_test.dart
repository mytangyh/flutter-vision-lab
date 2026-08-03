import 'dart:convert';
import 'dart:typed_data';

import 'package:aicamera/features/detection/yolo/yolo_detector.dart';
import 'package:aicamera/features/detection/mnn/mnn_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles a non-empty TFLite flatbuffer model', () async {
    final data = await rootBundle.load(YoloDetector.modelAsset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    expect(bytes.length, greaterThan(10 * 1024 * 1024));
    expect(ascii.decode(bytes.sublist(4, 8)), 'TFL3');
  });

  test('bundles the converted MNN 3.5 model', () async {
    final data = await rootBundle.load(MnnDetector.modelAsset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    expect(bytes.length, greaterThan(10 * 1024 * 1024));
    expect(data.getUint32(0, Endian.little), 32);
  });
}
