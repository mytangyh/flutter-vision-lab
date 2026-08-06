import 'dart:io';

import 'package:flutter/services.dart';

class PlatformInfo {
  const PlatformInfo({
    required this.manufacturer,
    required this.model,
    required this.androidSdk,
    required this.abi,
    this.operatingSystem = 'unknown',
    this.systemVersion = 'unknown',
  });

  static const _channel = MethodChannel('aicamera/platform');

  final String manufacturer;
  final String model;
  final String operatingSystem;
  final String systemVersion;
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
        operatingSystem:
            value?['operatingSystem'] as String? ?? Platform.operatingSystem,
        systemVersion: value?['systemVersion'] as String? ?? 'unknown',
        androidSdk: value?['androidSdk'] as int? ?? 0,
        abi: value?['abi'] as String? ?? 'unknown',
      );
    } on MissingPluginException {
      return PlatformInfo(
        manufacturer: 'development',
        model: 'unknown',
        operatingSystem: Platform.operatingSystem,
        systemVersion: Platform.operatingSystemVersion,
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
        'operatingSystem': operatingSystem,
        'systemVersion': systemVersion,
        'androidSdk': androidSdk,
        'abi': abi,
      };
}
