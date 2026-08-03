import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:flutter/material.dart';

class DetectionOverlay extends CustomPainter {
  const DetectionOverlay(this.detections, {required this.sourceName});

  final List<Detection> detections;
  final String sourceName;

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = const Color(0xFF8BFFCF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (final detection in detections) {
      final box = Rect.fromLTRB(
        detection.normalizedRect.left * size.width,
        detection.normalizedRect.top * size.height,
        detection.normalizedRect.right * size.width,
        detection.normalizedRect.bottom * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(10)),
        boxPaint,
      );
      _drawBubble(canvas, size, box, detection);
    }
  }

  void _drawBubble(
    Canvas canvas,
    Size size,
    Rect box,
    Detection detection,
  ) {
    final title = TextPainter(
      text: TextSpan(
        text:
            '${detection.displayName}  ${(detection.confidence * 100).round()}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 180);
    final subtitle = TextPainter(
      text: TextSpan(
        text: _subtitle(detection),
        style: const TextStyle(
          color: Color(0xFFC9D2DF),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 180);
    final description = detection.description == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: detection.description,
              style: const TextStyle(
                color: Color(0xFFE4E8EF),
                fontSize: 10,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: 220));

    var contentWidth =
        title.width > subtitle.width ? title.width : subtitle.width;
    if (description != null && description.width > contentWidth) {
      contentWidth = description.width;
    }
    final bubbleWidth = contentWidth + 20;
    final bubbleHeight = description == null ? 48.0 : 64.0;
    var bubbleLeft = box.left.clamp(4.0, size.width - bubbleWidth - 4);
    var bubbleTop = box.top - bubbleHeight - 7;
    if (bubbleTop < 4) {
      bubbleTop = box.top + 7;
    }

    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(bubbleLeft, bubbleTop, bubbleWidth, bubbleHeight),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      bubble,
      Paint()..color = const Color(0xDD111827),
    );
    canvas.drawRRect(
      bubble,
      Paint()
        ..color = const Color(0x668BFFCF)
        ..style = PaintingStyle.stroke,
    );
    title.paint(canvas, Offset(bubbleLeft + 10, bubbleTop + 7));
    subtitle.paint(canvas, Offset(bubbleLeft + 10, bubbleTop + 27));
    description?.paint(canvas, Offset(bubbleLeft + 10, bubbleTop + 43));
  }

  String _subtitle(Detection detection) {
    final state = switch (detection.enrichmentState) {
      EnrichmentState.pending => ' · 云端识别中',
      EnrichmentState.enriched => ' · 已云端增强',
      EnrichmentState.failed => ' · 云端失败',
      EnrichmentState.local => '',
    };
    return '$sourceName · ${detection.label}$state';
  }

  @override
  bool shouldRepaint(covariant DetectionOverlay oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.sourceName != sourceName;
  }
}
