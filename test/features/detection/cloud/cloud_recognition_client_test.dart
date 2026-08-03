import 'dart:convert';
import 'dart:typed_data';

import 'package:aicamera/features/detection/cloud/cloud_recognition_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes cloud JSON bytes as UTF-8 when charset is absent', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'name': '棉柔亲肤抽纸',
          'brand': '清风',
          'description': '4层加厚升级，棉柔亲肤',
        }),
      ),
    );

    final result = decodeCloudJson(bytes);

    expect(result['name'], '棉柔亲肤抽纸');
    expect(result['brand'], '清风');
    expect(result['description'], '4层加厚升级，棉柔亲肤');
  });
}
