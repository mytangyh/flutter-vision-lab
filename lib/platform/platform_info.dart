import 'package:flutter/services.dart';

class PlatformInfo {
  const PlatformInfo({
    required this.manufacturer,
    required this.model,
    required this.androidSdk,
    required this.abi,
  });

  static const _channel = MethodChannel('aicamera/platform');

  final String manufacturer;
  final String model;
  final int androidSdk;
  final String abi;

  static Future<PlatformInfo> load() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'getPlatformInfo',
      );
      return PlatformInfo(
        manufacturer: value?['manufacturer'] as String? ?? 'unknown',
        model: value?['model'] as String? ?? 'unknown',
        androidSdk: value?['androidSdk'] as int? ?? 0,
        abi: value?['abi'] as String? ?? 'unknown',
      );
    } on MissingPluginException {
      return const PlatformInfo(
        manufacturer: 'development',
        model: 'non-Android',
        androidSdk: 0,
        abi: 'unknown',
      );
    }
  }

  static Future<void> shareJson(String json) async {
    await _channel.invokeMethod<void>('shareJson', {'json': json});
  }

  Map<String, Object> toJson() => {
        'manufacturer': manufacturer,
        'model': model,
        'androidSdk': androidSdk,
        'abi': abi,
      };
}
