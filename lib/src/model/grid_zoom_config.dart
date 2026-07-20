import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:flutter/foundation.dart';

/// Configures pinch-to-zoom column switching. Passing an instance to
/// `FluidGrid.zoomConfig` enables the gesture; leaving it null
/// disables pinch entirely.
@immutable
class GridZoomConfig {
  const GridZoomConfig({
    this.minCrossAxisCount = 1,
    this.maxCrossAxisCount = 4,
    this.zoomLevels,
    this.rubberBandFactor = 0,
    this.flingVelocityThreshold = 1.0,
    this.switchThreshold = 0.1,
    this.style = GridZoomStyle.morph,
  }) : assert(minCrossAxisCount >= 1, 'minCrossAxisCount must be at least 1'),
       assert(
         maxCrossAxisCount >= minCrossAxisCount,
         'maxCrossAxisCount must be >= minCrossAxisCount',
       ),
       assert(
         rubberBandFactor >= 0 && rubberBandFactor < double.infinity,
         'rubberBandFactor must be finite and non-negative',
       ),
       assert(
         flingVelocityThreshold >= 0 && flingVelocityThreshold < double.infinity,
         'flingVelocityThreshold must be finite and non-negative',
       ),
       assert(
         switchThreshold > 0 && switchThreshold <= 1,
         'switchThreshold must be in (0, 1]',
       );

  /// Fewest columns the grid zooms out to (biggest cards). Superseded by
  /// [zoomLevels] when that is provided.
  final int minCrossAxisCount;

  /// Most columns the grid zooms in to (smallest cards). Superseded by
  /// [zoomLevels] when that is provided.
  final int maxCrossAxisCount;

  /// The only column counts the pinch may rest on, iOS-Photos style (e.g.
  /// `[1, 3, 5, 9]`). When non-null it supersedes [minCrossAxisCount] and
  /// [maxCrossAxisCount]: the pinch morphs between ADJACENT levels — never an
  /// intermediate count — the release snaps to the nearest level, and a fling
  /// commits one level in the fling's direction.
  ///
  /// Must be non-empty, strictly ascending, and every value at least 1
  /// (asserted by the grids in debug mode; list contents cannot be validated in
  /// a const constructor). Null (the default) allows every integer in
  /// `[minCrossAxisCount, maxCrossAxisCount]`, as before.
  final List<int>? zoomLevels;

  /// The smallest resting column count, from [zoomLevels] when provided.
  int get effectiveMinCrossAxisCount => (zoomLevels?.isNotEmpty ?? false) ? zoomLevels!.first : minCrossAxisCount;

  /// The largest resting column count, from [zoomLevels] when provided.
  int get effectiveMaxCrossAxisCount => (zoomLevels?.isNotEmpty ?? false) ? zoomLevels!.last : maxCrossAxisCount;

  /// Whether [zoomLevels] satisfies its contract (non-empty, strictly
  /// ascending, all >= 1). Always true when [zoomLevels] is null. Consulted by
  /// the grids' debug asserts.
  bool get debugZoomLevelsValid {
    final levels = zoomLevels;
    if (levels == null) return true;
    if (levels.isEmpty) return false;
    for (var i = 0; i < levels.length; i++) {
      if (levels[i] < 1) return false;
      if (i > 0 && levels[i] <= levels[i - 1]) return false;
    }
    return true;
  }

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

  /// How far a gentle (non-fling) pinch must travel toward a neighbouring
  /// column count before releasing commits to it — expressed as a fraction of
  /// one level-step, measured from the zoom the gesture started on.
  ///
  /// One level-step is the gap between ADJACENT ALLOWED levels: with
  /// [zoomLevels] `[1, 3]` the step is 2, so a threshold of 0.1 requires 0.2
  /// zoom units of travel to switch.
  ///
  /// Directional and symmetric: whether you pinch to add or remove columns, you
  /// must drag at least this fraction of the way toward the next level for the
  /// release to switch; otherwise it springs back to the starting count.
  ///
  /// Defaults to 0.1 — eager switching, one tenth of a step commits. 0.5 is
  /// the classic snap-to-nearest; 1.0 requires dragging all the way onto the
  /// next level. Must be in `(0, 1]`. Flings ignore it (they always commit one
  /// step in the fling's direction).
  final double switchThreshold;

  /// How each item's two column-count renderings are placed and blended during
  /// the morph. Defaults to [GridZoomStyle.morph] (the travelling per-item
  /// crossfade). See [GridZoomStyle] for the trade-offs of each mode; both
  /// [GridZoomStyle.morph] and [GridZoomStyle.photos] build every item twice
  /// and so require content that tolerates two live instances.
  ///
  /// Section headers float above the tiles. Tiles stay within the grid's
  /// bounds; mid-gesture paint is additionally clipped to them, so copies of
  /// items whose height is not proportional to their width (e.g. wrapping text)
  /// can momentarily cover trailing list content but never unrelated UI.
  final GridZoomStyle style;

  /// Whether pinch can actually change anything. A single allowed count leaves
  /// nothing to zoom between.
  bool get isEnabled => (zoomLevels?.length ?? (maxCrossAxisCount - minCrossAxisCount + 1)) > 1;

  @override
  bool operator ==(Object other) =>
      other is GridZoomConfig &&
      other.minCrossAxisCount == minCrossAxisCount &&
      other.maxCrossAxisCount == maxCrossAxisCount &&
      listEquals(other.zoomLevels, zoomLevels) &&
      other.rubberBandFactor == rubberBandFactor &&
      other.flingVelocityThreshold == flingVelocityThreshold &&
      other.switchThreshold == switchThreshold &&
      other.style == style;

  @override
  int get hashCode => Object.hash(
    minCrossAxisCount,
    maxCrossAxisCount,
    zoomLevels == null ? null : Object.hashAll(zoomLevels!),
    rubberBandFactor,
    flingVelocityThreshold,
    switchThreshold,
    style,
  );
}
