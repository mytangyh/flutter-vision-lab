import 'dart:convert';

import 'package:aicamera/features/detection/yolo/yolo_detector.dart';
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
}
