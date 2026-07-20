import 'dart:ui' show Offset, Rect;

import 'package:fluid_grid/src/model/grid_zoom_config.dart';

/// Pure math for pinch-to-zoom column switching. No Flutter widget state here,
/// so every rule is unit-testable in isolation.

/// The adjacent allowed-level pair the continuous [zoom] morphs between, and
/// the normalized position `t` within it.
///
/// Null (or empty) [levels] preserves today's behavior bit-for-bit: every
/// integer is a level, so the pair is `(floor(zoom), ceil(zoom))` clamped to at
/// least 1 and `t` is the fraction. With explicit levels (sorted ascending,
/// e.g. `[1, 3, 5, 9]`), the pair is the two adjacent levels containing
/// [zoom] and `t = (zoom - low) / (high - low)`. Exactly on a level returns
/// `(L, L, 0)` — the single-solve fast path. Beyond the first/last level the
/// END pair carries the rubber-band overshoot as `t < 0` / `t > 1`, matching
/// the existing extrapolating lerp.
({int low, int high, double t}) levelNeighbors(double zoom, List<int>? levels) {
  if (levels == null || levels.isEmpty) {
    final low = zoom.floor() < 1 ? 1 : zoom.floor();
    final high = zoom.ceil() < 1 ? 1 : zoom.ceil();
    return (low: low, high: high, t: low == high ? 0.0 : zoom - low);
  }
  if (levels.length == 1) {
    return (low: levels.first, high: levels.first, t: 0.0);
  }

  var index = 0;
  while (index < levels.length - 2 && zoom >= levels[index + 1]) {
    index++;
  }
  final low = levels[index];
  final high = levels[index + 1];
  if (zoom == low) return (low: low, high: low, t: 0.0);
  if (zoom == high) return (low: high, high: high, t: 0.0);
  return (low: low, high: high, t: (zoom - low) / (high - low));
}

/// The greatest level at or below [zoom], or the first level when [zoom] sits
/// below the whole set.
int _levelFloor(double zoom, List<int> levels) {
  var result = levels.first;
  for (final level in levels) {
    if (level <= zoom) {
      result = level;
    } else {
      break;
    }
  }
  return result;
}

/// The smallest level at or above [zoom], or the last level when [zoom] sits
/// above the whole set.
int _levelCeil(double zoom, List<int> levels) {
  for (final level in levels) {
    if (level >= zoom) return level;
  }
  return levels.last;
}

/// Maps a live pinch scale factor to a continuous column count.
///
/// Pinching out ([scale] > 1) makes cards bigger, and a bigger card means
/// *fewer* columns — column width is inversely proportional to count, so the
/// target count scales as `baseZoom / scale`. Pinching in ([scale] < 1) yields
/// more columns.
///
/// [baseZoom] is the zoom level at gesture start — a **double**, because a new
/// pinch can begin while the previous settle is mid-flight (z ≈ 2.4); an
/// integer base would snap the grid to the integer on the first update.
///
/// The result is rubber-banded, not hard-clamped, past the configured range so
/// the grid resists softly at the edges instead of stopping dead.
double zoomLevelForScale({
  required double scale,
  required double baseZoom,
  required GridZoomConfig config,
}) {
  // No scale change → no zoom change: preserve [baseZoom] exactly, even when it
  // is itself a rubber-banded overshoot from an unsettled previous pinch.
  // Re-applying the rubber-band curve here would compress that overshoot and
  // snap the grid back under the fingers before they have moved.
  if (scale == 1) return baseZoom;
  final raw = scale <= 0
      ? config.effectiveMaxCrossAxisCount.toDouble()
      : baseZoom / scale;
  return _rubberBand(
    raw,
    min: config.effectiveMinCrossAxisCount.toDouble(),
    max: config.effectiveMaxCrossAxisCount.toDouble(),
    factor: config.rubberBandFactor,
  );
}

/// Eases a value that has run past `[min, max]` back toward the boundary so the
/// overshoot compresses asymptotically rather than tracking the finger 1:1.
double _rubberBand(
  double value, {
  required double min,
  required double max,
  required double factor,
}) {
  if (value < min) return min - _resist(min - value, factor);
  if (value > max) return max + _resist(value - max, factor);
  return value;
}

/// Diminishing-returns curve `factor·d/(1 + d)`: grows sublinearly in `d` and
/// saturates toward `factor` as `d` → ∞, so `factor` bounds how far the
/// overshoot is ever allowed to travel. With the intended `factor` in `[0, 1]`
/// the result stays below `d`.
double _resist(double distance, double factor) =>
    factor * distance / (1 + distance);

/// The integer column count a gesture settles to when the fingers lift.
///
/// A deliberate fling — [scaleVelocity] beyond [GridZoomConfig.flingVelocityThreshold]
/// — commits one step in the fling's direction even if the finger stopped
/// short. `scaleVelocity > 0` means still spreading (fewer columns); `< 0` means
/// still pinching (more columns). The result is always clamped to the
/// configured range.
///
/// A gentle release commits by [GridZoomConfig.switchThreshold]: it takes the
/// neighbouring count in the drag's direction only once the zoom has travelled
/// at least that fraction of a level-step toward it, measured from [baseZoom]
/// (the zoom the gesture started on); otherwise it springs back. A threshold
/// of 0.5 is the classic snap-to-nearest. When [baseZoom] is null (or the
/// release lands exactly on a level, so there is no travel to measure) it
/// falls back to nearest, ties toward the higher count like `round()`'s half-up.
///
/// With [GridZoomConfig.zoomLevels], counts step through the allowed levels
/// instead of every integer: a fling commits to the adjacent level in its
/// direction (level-space floor/ceil, so an overshoot past the last level still
/// lands on it) and a gentle release applies the same threshold in level space.
int resolveZoomRelease({
  required double zoomLevel,
  required double scaleVelocity,
  required GridZoomConfig config,
  double? baseZoom,
}) {
  final levels = config.zoomLevels;
  if (levels != null && levels.isNotEmpty) {
    final low = _levelFloor(zoomLevel, levels);
    final high = _levelCeil(zoomLevel, levels);
    if (scaleVelocity > config.flingVelocityThreshold) return low;
    if (scaleVelocity < -config.flingVelocityThreshold) return high;
    return _gentleCommit(
      zoomLevel: zoomLevel,
      low: low.toDouble(),
      high: high.toDouble(),
      baseZoom: baseZoom,
      threshold: config.switchThreshold,
    ).round();
  }

  final min = config.minCrossAxisCount;
  final max = config.maxCrossAxisCount;

  int resolved;
  if (scaleVelocity > config.flingVelocityThreshold) {
    // Spreading fast: bias toward fewer columns (round down).
    resolved = zoomLevel.floor();
  } else if (scaleVelocity < -config.flingVelocityThreshold) {
    // Pinching fast: bias toward more columns (round up).
    resolved = zoomLevel.ceil();
  } else {
    final low = zoomLevel.floor() < 1 ? 1 : zoomLevel.floor();
    final high = zoomLevel.ceil() < 1 ? 1 : zoomLevel.ceil();
    resolved = _gentleCommit(
      zoomLevel: zoomLevel,
      low: low.toDouble(),
      high: high.toDouble(),
      baseZoom: baseZoom,
      threshold: config.switchThreshold,
    ).round();
  }

  return resolved.clamp(min, max);
}

/// The level a gentle release commits to within the pair [low], [high].
///
/// [threshold] is the fraction of the step the zoom must travel from [baseZoom]
/// toward a neighbour to switch to it: the TRAVEL `|zoomLevel − baseZoom|`
/// relative to the step `high − low` is what is measured, so a gesture that
/// starts mid-pair (a re-pinch during a settle) needs the same deliberate
/// movement as one starting on a level. A release short of the threshold
/// springs back to the level nearest [baseZoom]. Falls back to snap-to-nearest
/// (ties to [high]) when there is no direction to measure — [baseZoom] is
/// null, the endpoints coincide, or the release sits exactly on the starting
/// zoom.
double _gentleCommit({
  required double zoomLevel,
  required double low,
  required double high,
  required double? baseZoom,
  required double threshold,
}) {
  if (low == high) return low;
  final t = (zoomLevel - low) / (high - low);
  if (baseZoom == null || zoomLevel == baseZoom) {
    return t < 0.5 ? low : high;
  }
  // A sweep across several pairs releases with [baseZoom] outside this pair;
  // clamping it to the pair measures only the travel INSIDE the pair, so
  // stopping just past a level does not overshoot to the one beyond it.
  final start = baseZoom.clamp(low, high);
  final travel = (zoomLevel - start).abs() / (high - low);
  if (travel >= threshold) {
    return zoomLevel > baseZoom ? high : low;
  }
  return start - low < high - start ? low : high;
}

/// The fractional position of [localPoint] inside [anchorRect].
///
/// Deliberately **unclamped**: the fraction is an affine reference, not a UI
/// coordinate. When the focal point lies outside the nearest item (the anchor
/// fallback), a clamped fraction would silently move the anchored point away
/// from the fingers and the scroll pinning would jump the moment the pinch
/// starts.
Offset anchorFractionForPoint({
  required Rect anchorRect,
  required Offset localPoint,
}) => Offset(
  anchorRect.width == 0
      ? 0
      : (localPoint.dx - anchorRect.left) / anchorRect.width,
  anchorRect.height == 0
      ? 0
      : (localPoint.dy - anchorRect.top) / anchorRect.height,
);
