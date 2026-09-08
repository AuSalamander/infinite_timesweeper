import 'package:flutter/foundation.dart';

/// Lightweight frame/render stats. Cheap counters only (no allocs in
/// hot loop); summary is printed throttled in debug AND profile builds,
/// silent in release, so release cost is ~zero.
class FrameStats {
  final List<double> _frameMs = [];
  final List<double> _renderMs = [];
  static const int _maxSamples = 120;

  int lastVisibleTiles = 0;
  double lastZoom = 1.0;
  int reportCount = 0;

  double _accumDt = 0;

  void recordFrame(double dtSeconds) {
    if (kReleaseMode) return;
    final ms = dtSeconds * 1000.0;
    if (_frameMs.length >= _maxSamples) _frameMs.removeAt(0);
    _frameMs.add(ms);
  }

  void recordRender(double renderMs, int visibleTiles, double zoom) {
    if (kReleaseMode) return;
    if (_renderMs.length >= _maxSamples) _renderMs.removeAt(0);
    _renderMs.add(renderMs);
    lastVisibleTiles = visibleTiles;
    lastZoom = zoom;
  }

  /// Returns a one-line summary when due (every [interval]s), else null.
  String? maybeReport(double dtSeconds,
      {required int storedTiles,
      required int chunkHits,
      required int chunkMisses,
      double interval = 2.0}) {
    if (kReleaseMode) return null;
    _accumDt += dtSeconds;
    if (_accumDt < interval) return null;
    _accumDt = 0;
    reportCount++;

    double avg(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    double p95(List<double> xs) {
      if (xs.isEmpty) return 0;
      final s = List<double>.from(xs)..sort();
      return s[((s.length * 0.95).floor()).clamp(0, s.length - 1)];
    }

    final totalLookups = chunkHits + chunkMisses;
    final hitPct = totalLookups == 0
        ? 0
        : (chunkHits * 100.0 / totalLookups).toStringAsFixed(0);
    final avgF = avg(_frameMs);
    final fps = avgF > 0 ? 1000.0 / avgF : 0;
    return 'PERF fps=${fps.toStringAsFixed(0)} f${avgF.toStringAsFixed(1)}/p95_${p95(_frameMs).toStringAsFixed(1)}ms '
        'render_avg${avg(_renderMs).toStringAsFixed(2)}/p95_${p95(_renderMs).toStringAsFixed(2)}ms '
        'tiles=$lastVisibleTiles zoom=${lastZoom.toStringAsFixed(2)} '
        'stored=$storedTiles chunkHit=$hitPct% ($chunkHits/$totalLookups)';
  }

  void reset() {
    _frameMs.clear();
    _renderMs.clear();
    _accumDt = 0;
  }
}
