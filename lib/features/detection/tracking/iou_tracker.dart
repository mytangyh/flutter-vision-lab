import 'dart:ui';

import 'package:aicamera/features/detection/domain/detection.dart';
import 'package:aicamera/features/detection/yolo/yolo_postprocessor.dart';

class TrackerUpdate {
  const TrackerUpdate({
    required this.detections,
    required this.newlyStable,
  });

  final List<Detection> detections;
  final List<Detection> newlyStable;
}

class IouTracker {
  IouTracker({
    this.iouThreshold = 0.5,
    this.minimumHits = 3,
    this.minimumStableDuration = const Duration(milliseconds: 600),
    this.activeTimeout = const Duration(milliseconds: 1500),
    this.cacheDuration = const Duration(seconds: 30),
  });

  final double iouThreshold;
  final int minimumHits;
  final Duration minimumStableDuration;
  final Duration activeTimeout;
  final Duration cacheDuration;

  final List<_Track> _tracks = [];
  int _nextId = 1;

  TrackerUpdate update(List<Detection> detections, DateTime now) {
    _tracks.removeWhere(
      (track) => now.difference(track.lastSeen) > cacheDuration,
    );
    final unmatchedTracks = <_Track>{..._tracks};
    final updated = <Detection>[];
    final newlyStable = <Detection>[];

    for (final detection in [...detections]
      ..sort((a, b) => b.confidence.compareTo(a.confidence))) {
      _Track? best;
      var bestIou = iouThreshold;
      for (final track in unmatchedTracks) {
        if (track.classIndex != detection.classIndex ||
            now.difference(track.lastSeen) > cacheDuration) {
          continue;
        }
        final iou = YoloPostprocessor.intersectionOverUnion(
          track.rect,
          detection.normalizedRect,
        );
        if (iou >= bestIou) {
          best = track;
          bestIou = iou;
        }
      }

      final track = best ??
          _Track(
            id: 'track-${_nextId++}',
            classIndex: detection.classIndex,
            rect: detection.normalizedRect,
            firstSeen: now,
            lastSeen: now,
          );
      if (best == null) {
        _tracks.add(track);
      } else {
        unmatchedTracks.remove(track);
        if (now.difference(track.lastSeen) <= activeTimeout) {
          track.hits++;
        } else {
          track.hits = 1;
          track.firstSeen = now;
        }
        track.rect = detection.normalizedRect;
        track.lastSeen = now;
      }

      final decorated = detection.copyWith(
        displayName: track.enrichedName,
        description: track.description,
        trackId: track.id,
        enrichmentState: track.state,
      );
      updated.add(decorated);
      if (!track.requested &&
          detection.confidence >= 0.5 &&
          track.hits >= minimumHits &&
          now.difference(track.firstSeen) >= minimumStableDuration) {
        newlyStable.add(decorated);
      }
    }
    return TrackerUpdate(detections: updated, newlyStable: newlyStable);
  }

  void markPending(String trackId) {
    final track = _find(trackId);
    if (track == null) {
      return;
    }
    track.requested = true;
    track.state = EnrichmentState.pending;
  }

  void markEnriched(
    String trackId, {
    required String name,
    required String description,
  }) {
    final track = _find(trackId);
    if (track == null) {
      return;
    }
    track.enrichedName = name;
    track.description = description;
    track.state = EnrichmentState.enriched;
  }

  void markFailed(String trackId) {
    final track = _find(trackId);
    if (track != null) {
      track.state = EnrichmentState.failed;
    }
  }

  Detection decorate(Detection detection) {
    final trackId = detection.trackId;
    final track = trackId == null ? null : _find(trackId);
    if (track == null) {
      return detection;
    }
    return detection.copyWith(
      displayName: track.enrichedName,
      description: track.description,
      enrichmentState: track.state,
    );
  }

  _Track? _find(String id) {
    for (final track in _tracks) {
      if (track.id == id) {
        return track;
      }
    }
    return null;
  }
}

class _Track {
  _Track({
    required this.id,
    required this.classIndex,
    required this.rect,
    required this.firstSeen,
    required this.lastSeen,
  });

  final String id;
  final int classIndex;
  Rect rect;
  DateTime firstSeen;
  DateTime lastSeen;
  int hits = 1;
  bool requested = false;
  String? enrichedName;
  String? description;
  EnrichmentState state = EnrichmentState.local;
}
