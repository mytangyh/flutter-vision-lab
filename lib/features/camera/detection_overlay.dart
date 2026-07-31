import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:flutter/material.dart';

class DetectionOverlay extends CustomPainter {
  const DetectionOverlay(this.detections);

  final List<Detection> detections;

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
        text: 'YOLO 端侧识别 · ${detection.label}',
        style: const TextStyle(
          color: Color(0xFFC9D2DF),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 180);

    final bubbleWidth =
        (title.width > subtitle.width ? title.width : subtitle.width) + 20;
    const bubbleHeight = 48.0;
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
  }

  @override
  bool shouldRepaint(covariant DetectionOverlay oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
