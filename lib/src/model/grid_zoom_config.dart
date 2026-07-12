import 'package:flutter/foundation.dart';

/// Configures pinch-to-zoom column switching. Passing an instance to
/// `FluidGrid.zoomConfig` enables the gesture; leaving it null
/// disables pinch entirely.
@immutable
class GridZoomConfig {
  const GridZoomConfig({
    this.minCrossAxisCount = 1,
    this.maxCrossAxisCount = 4,
    this.rubberBandFactor = 0,
    this.flingVelocityThreshold = 1.0,
    this.crossfade = true,
  }) : assert(minCrossAxisCount >= 1, 'minCrossAxisCount must be at least 1'),
       assert(maxCrossAxisCount >= minCrossAxisCount, 'maxCrossAxisCount must be >= minCrossAxisCount'),
       assert(rubberBandFactor >= 0 && rubberBandFactor < double.infinity, 'rubberBandFactor must be finite and non-negative'),
       assert(flingVelocityThreshold >= 0 && flingVelocityThreshold < double.infinity, 'flingVelocityThreshold must be finite and non-negative');

  /// Fewest columns the grid zooms out to (biggest cards).
  final int minCrossAxisCount;

  /// Most columns the grid zooms in to (smallest cards).
  final int maxCrossAxisCount;

  /// How far the zoom is allowed to rubber-band past the range while pinching.
  ///
  /// Defaults to 0: the edges are hard stops — pinching past the minimum or
  /// maximum column count produces no movement at all, so the grid's limits
  /// read unambiguously. Set a positive value (e.g. 0.15) for iOS-style give,
  /// where the overshoot compresses asymptotically and springs back on
  /// release.
  final double rubberBandFactor;

  /// Scale-velocity (in scale units per second) above which a release is
  /// treated as a fling that commits one step in the fling's direction rather
  /// than snapping to the nearest count.
  final double flingVelocityThreshold;

  /// Cross-fade the outgoing and incoming column-count renderings during the
  /// morph, iOS-Photos style.
  ///
  /// Each item is rendered once at each endpoint's exact column width, and
  /// **both renditions ride the item's own interpolated rect**, scaled to the
  /// interpolated width — so the pair coincides and every tile reads as one
  /// element travelling from its old slot to its new slot while its content
  /// crossfades between the two renderings. The incoming rendition paints
  /// beneath and ramps to solid within the first fifth of the morph, while the
  /// outgoing one ghosts out linearly above it the whole way. Section headers
  /// float above the tiles. Tiles stay within the grid's bounds; mid-gesture
  /// paint is additionally clipped to them, so scaled copies of items whose
  /// height is not proportional to their width (e.g. wrapping text) can
  /// momentarily cover trailing list content but never unrelated UI.
  ///
  /// While a zoom is in flight every item is built **twice** (the transient
  /// copy is pointer- and semantics-excluded). Item widgets must therefore
  /// tolerate two live instances: no GlobalKeys, Heroes, or single-subscription
  /// stream listens inside `itemBuilder` content. Set to false for such content
  /// to fall back to the live-reflow morph, where each card re-lays-out at the
  /// interpolated width every frame and no copies are made.
  final bool crossfade;

  /// Whether pinch can actually change anything. A single allowed count leaves
  /// nothing to zoom between.
  bool get isEnabled => maxCrossAxisCount > minCrossAxisCount;

  @override
  bool operator ==(Object other) =>
      other is GridZoomConfig &&
      other.minCrossAxisCount == minCrossAxisCount &&
      other.maxCrossAxisCount == maxCrossAxisCount &&
      other.rubberBandFactor == rubberBandFactor &&
      other.flingVelocityThreshold == flingVelocityThreshold &&
      other.crossfade == crossfade;

  @override
  int get hashCode => Object.hash(minCrossAxisCount, maxCrossAxisCount, rubberBandFactor, flingVelocityThreshold, crossfade);
}
