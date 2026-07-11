import 'dart:ui' show Offset, Rect;

import 'package:fluid_grid/src/model/grid_zoom_config.dart';

/// Pure math for pinch-to-zoom column switching. No Flutter widget state here,
/// so every rule is unit-testable in isolation.

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
  final raw = scale <= 0 ? config.maxCrossAxisCount.toDouble() : baseZoom / scale;
  return _rubberBand(
    raw,
    min: config.minCrossAxisCount.toDouble(),
    max: config.maxCrossAxisCount.toDouble(),
    factor: config.rubberBandFactor,
  );
}

/// Eases a value that has run past `[min, max]` back toward the boundary so the
/// overshoot compresses asymptotically rather than tracking the finger 1:1.
double _rubberBand(double value, {required double min, required double max, required double factor}) {
  if (value < min) return min - _resist(min - value, factor);
  if (value > max) return max + _resist(value - max, factor);
  return value;
}

/// Diminishing-returns curve: `d` in, always less than `d` out, flattening as
/// `d` grows. `factor` scales how far the overshoot is allowed to travel.
double _resist(double distance, double factor) => factor * distance / (1 + distance);

/// The integer column count a gesture settles to when the fingers lift.
///
/// A deliberate fling — [scaleVelocity] beyond [GridZoomConfig.flingVelocityThreshold]
/// — commits one step in the fling's direction even if the finger stopped
/// short. `scaleVelocity > 0` means still spreading (fewer columns); `< 0` means
/// still pinching (more columns). A gentle release snaps to the nearest count.
/// The result is always clamped to the configured range.
int resolveZoomRelease({
  required double zoomLevel,
  required double scaleVelocity,
  required GridZoomConfig config,
}) {
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
    resolved = zoomLevel.round();
  }

  return resolved.clamp(min, max);
}

/// The fractional position of [localPoint] inside [anchorRect].
///
/// Deliberately **unclamped**: the fraction is an affine reference, not a UI
/// coordinate. When the focal point lies outside the nearest item (the anchor
/// fallback), a clamped fraction would silently move the anchored point away
/// from the fingers and the scroll pinning would jump the moment the pinch
/// starts.
Offset anchorFractionForPoint({required Rect anchorRect, required Offset localPoint}) => Offset(
  anchorRect.width == 0 ? 0 : (localPoint.dx - anchorRect.left) / anchorRect.width,
  anchorRect.height == 0 ? 0 : (localPoint.dy - anchorRect.top) / anchorRect.height,
);
