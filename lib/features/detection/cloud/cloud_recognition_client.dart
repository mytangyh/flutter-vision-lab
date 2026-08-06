import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aicamera/features/detection/domain/camera_frame.dart';
import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/yolo/camera_frame_preprocessor.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;

class CloudRecognition {
  const CloudRecognition({
    required this.name,
    required this.brand,
    required this.description,
    required this.provider,
    required this.model,
    required this.latencyMs,
  });

  final String name;
  final String? brand;
  final String description;
  final String provider;
  final String model;
  final int latencyMs;
}

abstract interface class CloudRecognitionClient {
  Future<CloudRecognition> recognize({
    required CameraFrame frame,
    required Detection detection,
  });

  void close();

  static CloudRecognitionClient fromEnvironment() {
    const baseUrl = String.fromEnvironment('CLOUD_API_BASE_URL');
    const clientToken = String.fromEnvironment('CLOUD_CLIENT_TOKEN');
    return CloudRecognitionClient.fromConfiguration(
      baseUrl: baseUrl,
      clientToken: clientToken,
    );
  }

  static CloudRecognitionClient fromConfiguration({
    required String baseUrl,
    required String clientToken,
    http.Client? client,
  }) {
    final normalizedBaseUrl = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    if (normalizedBaseUrl.isEmpty) {
      throw StateError(
        'CLOUD_API_BASE_URL is required for cloud recognition.',
      );
    }
    if (clientToken.isEmpty || clientToken != clientToken.trim()) {
      throw StateError(
        'CLOUD_CLIENT_TOKEN is required for cloud recognition.',
      );
    }
    final uri = Uri.tryParse(normalizedBaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('CLOUD_API_BASE_URL must be an HTTP(S) URL.');
    }
    return HttpCloudRecognitionClient(
      baseUrl: normalizedBaseUrl,
      clientToken: clientToken,
      client: client,
    );
  }
}

class HttpCloudRecognitionClient implements CloudRecognitionClient {
  HttpCloudRecognitionClient({
    required this.baseUrl,
    required this.clientToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String clientToken;
  final http.Client _client;

  @override
  Future<CloudRecognition> recognize({
    required CameraFrame frame,
    required Detection detection,
  }) async {
    final jpeg = await _cropTarget(frame, detection.normalizedRect);
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      try {
        return await _send(jpeg, detection).timeout(
          const Duration(seconds: 8),
        );
      } on CloudRecognitionException catch (error) {
        lastError = error;
        if (!error.retryable) {
          rethrow;
        }
      } on TimeoutException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
    }
    throw CloudRecognitionException(
      'Cloud recognition failed after retry: $lastError',
      retryable: false,
    );
  }

  Future<CloudRecognition> _send(
    Uint8List jpeg,
    Detection detection,
  ) async {
    final uri = Uri.parse(
      '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/api/v1/recognitions',
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..fields['request_id'] =
          '${DateTime.now().microsecondsSinceEpoch}-${detection.trackId}'
      ..fields['track_id'] = detection.trackId ?? 'untracked'
      ..fields['coarse_label'] = detection.label
      ..fields['coarse_confidence'] = detection.confidence.toString()
      ..fields['locale'] = 'zh-CN'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          jpeg,
          filename: 'target.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    if (clientToken.isNotEmpty) {
      request.headers['X-Client-Token'] = clientToken;
    }

    final watch = Stopwatch()..start();
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    watch.stop();
    final responseText = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudRecognitionException(
        'Cloud proxy returned ${response.statusCode}: $responseText',
        retryable: response.statusCode >= 500,
      );
    }
    final json = decodeCloudJson(response.bodyBytes);
    return CloudRecognition(
      name: json['name'] as String,
      brand: json['brand'] as String?,
      description: json['description'] as String,
      provider: json['provider'] as String? ?? 'unknown',
      model: json['model'] as String? ?? 'unknown',
      latencyMs: json['latency_ms'] as int? ?? watch.elapsedMilliseconds,
    );
  }

  @override
  void close() => _client.close();

  static Future<Uint8List> _cropTarget(
    CameraFrame frame,
    Rect normalizedRect,
  ) async {
    final source = decodeOrientedCameraFrame(frame);
    const margin = 0.12;
    final left = math.max(
      0,
      ((normalizedRect.left - normalizedRect.width * margin) * source.width)
          .floor(),
    );
    final top = math.max(
      0,
      ((normalizedRect.top - normalizedRect.height * margin) * source.height)
          .floor(),
    );
    final right = math.min(
      source.width,
      ((normalizedRect.right + normalizedRect.width * margin) * source.width)
          .ceil(),
    );
    final bottom = math.min(
      source.height,
      ((normalizedRect.bottom + normalizedRect.height * margin) * source.height)
          .ceil(),
    );
    var crop = img.copyCrop(
      source,
      x: left,
      y: top,
      width: math.max(1, right - left),
      height: math.max(1, bottom - top),
    );
    if (math.max(crop.width, crop.height) > 640) {
      crop = crop.width >= crop.height
          ? img.copyResize(crop, width: 640)
          : img.copyResize(crop, height: 640);
    }
    return Uint8List.fromList(img.encodeJpg(crop, quality: 80));
  }
}

Map<String, dynamic> decodeCloudJson(Uint8List bodyBytes) {
  return jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
}

class CloudRecognitionException implements Exception {
  const CloudRecognitionException(
    this.message, {
    required this.retryable,
  });

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}
