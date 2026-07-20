import 'dart:ui' show Offset, Rect;

import 'package:fluid_grid/src/model/grid_zoom_style.dart';

/// The zoom fraction by which the incoming rendition has ramped to full opacity.
/// Kept small so the new grid materialises almost immediately, like Photos,
/// rather than staying hidden behind the old one for the first stretch of the
/// morph; the outgoing rendition ghosts out linearly above it the whole way.
const double kIncomingSolidAt = 0.18;

/// Which end of the zoom morph an item copy renders during a crossfade.
///
/// The slot is *relative* to the animated zoom level: `low` renders the
/// `floor(zoom)`-column layout, `high` the `ceil(zoom)` one. When the zoom
/// crosses an integer, the pair rolls over and the copies are simply
/// re-measured at their slot's new width — no rebuild is needed.
enum ZoomSlot { none, low, high }

/// The opacity of the low and high crossfade rendition groups at morph position
/// [t].
///
/// The incoming (high) renditions ramp to solid within the first fifth of the
/// morph while the outgoing (low) renditions ghost out linearly the whole way.
/// Under [GridZoomStyle.morph] an item's two renditions coincide, so each tile
/// stays near-opaque throughout; under [GridZoomStyle.photos] the two endpoint
/// canvases crossfade the same way. A pure, reversible function of [t].
({double low, double high}) crossfadeSlotAlphas(double t) {
  final tc = t.clamp(0.0, 1.0);
  return (
    low: 1 - tc,
    high: (tc / kIncomingSolidAt).clamp(0.0, 1.0),
  );
}

/// The peak Gaussian blur, in logical pixels, a crossfade rendition reaches at
/// full transparency under [GridZoomStyle.morph].
const double kMorphBlurMaxSigma = 8;

/// The blur sigma applied to a [GridZoomStyle.morph] crossfade rendition given
/// its own opacity [groupAlpha], so the morph **dissolves through blur**: a
/// rendition is blurred exactly in proportion to how transparent it is (sigma
/// `kMorphBlurMaxSigma·(1 − alpha)`), so the outgoing copy blurs as it fades
/// out and the incoming copy sharpens as it solidifies. Zero for a fully
/// opaque rendition — the resting grid at either level is always crisp — and
/// zero for every non-morph style. Pure function of the style and alpha.
double morphBlurSigma(GridZoomStyle style, double groupAlpha) {
  if (style != GridZoomStyle.morph) return 0;
  return kMorphBlurMaxSigma * (1 - groupAlpha.clamp(0.0, 1.0));
}

/// The shared horizontal fixed point of a [GridZoomStyle.photos] canvas pair:
/// the unique grid-local x whose FRACTIONAL position inside the anchor tile is
/// identical in both endpoint layouts.
///
/// Anchoring both canvases at this abscissa (instead of the raw finger x) makes
/// the anchor tile's two renditions coincide exactly at every morph position —
/// each canvas paints the anchor's x-interval as the same lerped interval — so
/// the incoming copy of the pinched photo never ghosts sideways from the
/// outgoing one. Setting the two canvases' mappings of the anchor's left edge
/// equal and solving for the fixed point gives
/// `F = (lowLeft·highWidth − highLeft·lowWidth) / (highWidth − lowWidth)`,
/// which is independent of the morph position, so it can be frozen for the
/// whole pair exactly like the old finger-x was.
///
/// Clamped to `[0, gridWidth]` so the covering canvas always spans the full
/// viewport width (the fixed point staying inside the grid is what guarantees
/// no blank edge strip). Null when an anchor rect is missing or the endpoint
/// widths are degenerate; callers fall back to the finger x captured at
/// gesture start.
double? photosPairFixedX({
  required Rect? anchorLowRect,
  required Rect? anchorHighRect,
  required double lowWidth,
  required double highWidth,
  required double gridWidth,
}) {
  if (anchorLowRect == null || anchorHighRect == null) return null;
  if (lowWidth <= 0 || highWidth <= 0 || lowWidth == highWidth) return null;
  final fixedX =
      (anchorLowRect.left * highWidth - anchorHighRect.left * lowWidth) /
      (highWidth - lowWidth);
  return fixedX.clamp(0.0, gridWidth);
}

/// The rigid transform one [GridZoomStyle.photos] canvas paints under: every
/// grid-local point `p` of endpoint layout K maps to
/// `anchorStar + scale · (p − anchorK)`.
///
/// The two axes anchor differently:
///
/// - **x** is anchored at [focalX], the frozen grid-local fixed point shared by
///   both canvases (`T(focalX) = focalX` at every morph position), so the zoom
///   reads as a pure expansion/contraction with zero sideways translation — the
///   grid can never drift horizontally. Callers pass [photosPairFixedX] (the
///   anchor's fraction-matching abscissa) so the anchor tile's two renditions
///   also coincide horizontally throughout the morph, falling back to the
///   finger x captured at gesture start when it is unavailable. Because the
///   covering (high-count) canvas has `scale >= 1` mid-morph and focalX lies
///   inside the viewport, it always spans the full width: no blank edge strip,
///   no clamp needed.
/// - **y** is anchored on the pinched tile: `anchorK.y` is the anchor point
///   inside endpoint layout K ([anchorEndpointRect] with [anchorFraction]
///   applied) and `anchorStar.y` the same point on the interpolated anchor rect
///   — the point the vertical scroll pinning keeps under the fingers.
///
/// `scale` is `itemWidth / endpointWidth`: both canvases show tiles at the
/// interpolated width, and at each end of the morph the winning canvas is
/// exactly the identity, so every resting level is pixel-flush.
///
/// Returns null when the anchor data is incomplete (no anchor captured, or its
/// rects are missing); callers fall back to the travelling-morph geometry.
({Offset anchorK, Offset anchorStar, double scale})? photosCanvasTransform({
  required Rect? anchorEndpointRect,
  required Rect? anchorLerpedRect,
  required Offset anchorFraction,
  required double endpointWidth,
  required double itemWidth,
  required double focalX,
}) {
  if (anchorEndpointRect == null ||
      anchorLerpedRect == null ||
      endpointWidth <= 0) {
    return null;
  }
  final anchorK = Offset(
    focalX,
    anchorEndpointRect.top + anchorFraction.dy * anchorEndpointRect.height,
  );
  final anchorStar = Offset(
    focalX,
    anchorLerpedRect.top + anchorFraction.dy * anchorLerpedRect.height,
  );
  return (
    anchorK: anchorK,
    anchorStar: anchorStar,
    scale: itemWidth / endpointWidth,
  );
}

/// Maps a grid-local [rect] of an endpoint layout through a photos [canvas]
/// transform, yielding the rect it actually paints at mid-morph.
Rect mapRectByCanvas(
  ({Offset anchorK, Offset anchorStar, double scale}) canvas,
  Rect rect,
) {
  final topLeft =
      canvas.anchorStar + (rect.topLeft - canvas.anchorK) * canvas.scale;
  return Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy,
    rect.width * canvas.scale,
    rect.height * canvas.scale,
  );
}

/// Per-item [GridZoomStyle.photos] geometry: where one rendition of the item
/// paints under its canvas transform, in the same `(offset, scale)` form the
/// render objects' paint/hit-test use (scale anchored at the painted top-left).
///
/// Null when the anchor data or the item's own endpoint rect is missing —
/// callers fall back to [crossfadeRenditionGeometry], whose non-fade branch is
/// the coherent travelling-morph geometry.
({Offset offset, double scale})? photosCanvasGeometry({
  required Rect? endpointRect,
  required Rect? anchorEndpointRect,
  required Rect? anchorLerpedRect,
  required Offset anchorFraction,
  required double endpointWidth,
  required double itemWidth,
  required double focalX,
}) {
  if (endpointRect == null) return null;
  final canvas = photosCanvasTransform(
    anchorEndpointRect: anchorEndpointRect,
    anchorLerpedRect: anchorLerpedRect,
    anchorFraction: anchorFraction,
    endpointWidth: endpointWidth,
    itemWidth: itemWidth,
    focalX: focalX,
  );
  if (canvas == null) return null;
  return (
    offset:
        canvas.anchorStar +
        (endpointRect.topLeft - canvas.anchorK) * canvas.scale,
    scale: canvas.scale,
  );
}

/// Where and at what scale one crossfade rendition paints, in grid-local
/// coordinates.
///
/// The copy rides the item's own lerped-layout rect ([lerpedRect]), scaled from
/// its endpoint width to the interpolated width — so under [GridZoomStyle.morph]
/// an item's two renditions coincide and every tile reads as one element
/// travelling from its old slot to its new slot; [GridZoomStyle.photos] also
/// falls back here when its rigid-canvas anchor data is missing.
///
/// [fallback] is used when the lerped rect is missing (a copy with no solved
/// position yet).
({Offset offset, double scale}) crossfadeRenditionGeometry({
  required Rect? lerpedRect,
  required double endpointWidth,
  required double itemWidth,
  required Offset fallback,
}) => (
  offset: lerpedRect?.topLeft ?? fallback,
  scale: endpointWidth > 0 ? itemWidth / endpointWidth : 1.0,
);
