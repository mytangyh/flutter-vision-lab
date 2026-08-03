import 'dart:ui';

import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/tracking/iou_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emits one cloud candidate after a target becomes stable', () {
    final tracker = IouTracker(
      minimumHits: 3,
      minimumStableDuration: const Duration(milliseconds: 600),
    );
    final started = DateTime(2026);

    final first = tracker.update([detection()], started);
    final second = tracker.update(
      [detection()],
      started.add(const Duration(milliseconds: 300)),
    );
    final third = tracker.update(
      [detection()],
      started.add(const Duration(milliseconds: 700)),
    );

    expect(first.newlyStable, isEmpty);
    expect(second.newlyStable, isEmpty);
    expect(third.newlyStable, hasLength(1));
    expect(third.newlyStable.single.trackId, 'track-1');

    tracker.markPending('track-1');
    final pending = tracker.decorate(third.detections.single);
    expect(pending.enrichmentState, EnrichmentState.pending);

    tracker.markEnriched(
      'track-1',
      name: '陶瓷马克杯',
      description: '白色杯子',
    );
    final enriched = tracker.decorate(pending);
    expect(enriched.displayName, '陶瓷马克杯');
    expect(enriched.description, '白色杯子');
    expect(enriched.enrichmentState, EnrichmentState.enriched);
  });
}

Detection detection() {
  return const Detection(
    classIndex: 41,
    label: 'cup',
    displayName: '杯子',
    confidence: 0.8,
    normalizedRect: Rect.fromLTWH(0.2, 0.2, 0.4, 0.4),
  );
}
