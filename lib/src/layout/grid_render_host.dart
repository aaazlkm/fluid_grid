import 'dart:ui' show Offset, Rect, Size;

import 'package:fluid_grid/src/layout/grid_layout.dart';

/// The narrow surface the interaction state machine (`FluidGridCoordinator`)
/// needs from whichever render object is laying the grid out — the box
/// `RenderMasonryGrid` or the sliver render object.
///
/// Both implement this so the drag, pinch, ghost, and scroll-anchoring logic is
/// written once. The box implements every member against its own measured
/// caches; the sliver computes the same values from its height callback (so
/// heights are known for items that were never built) and folds the scroll
/// offset into the coordinate conversions.
abstract interface class GridHost {
  /// The last solved layout of every item. Never partial, even for the lazy
  /// sliver — the solver runs over all items from data.
  GridLayoutResult? get lastLayout;

  /// The natural size of item [id] at the committed column width, or null if it
  /// is unknown. The sliver answers for items that were never materialised.
  Size? itemSizeOf(Object id);

  /// Every item's natural height at the committed column width, keyed by id.
  /// Fed to the reorder resolver.
  Map<Object, double> itemHeights();

  /// Item heights measured/known for a [count]-column layout, or null when that
  /// column count's heights are not available (the box only keeps the two
  /// endpoints it last measured; the sliver can compute any count and never
  /// returns null).
  Map<Object, double>? itemHeightsForColumns(int count);

  /// The best available height map to stand in for an unmeasured [count]. Only
  /// consulted on the box path, where a pinch can outrun measurement.
  Map<Object, double> nearestItemHeightsForColumns(int count);

  /// Measured chrome extents, before any collapse factor is applied.
  double headerHeightOf(Object sectionId);
  double footerHeightOf(Object sectionId);

  /// Width the items were last laid out at (the cross-axis extent minus
  /// padding). Used to detect resizes mid-gesture.
  double get contentWidth;

  /// Full cross-axis extent of the grid (box width / sliver crossAxisExtent).
  double get gridWidth;

  /// The item the pinch's scroll pinning is anchored on, and the (unclamped)
  /// fractional point inside it kept under the fingers.
  Object? get zoomAnchorId;
  set zoomAnchorId(Object? value);
  Offset get zoomAnchorFraction;
  set zoomAnchorFraction(Offset value);

  /// The frozen grid-local x of the zoom focal — the horizontal FIXED point of
  /// both photos canvases (`T(zoomFocalX) = zoomFocalX` at every morph
  /// position), so the zoom expands about the fingers with zero sideways
  /// translation. Captured once by the coordinator when a gesture (or
  /// programmatic morph) starts from rest; a re-pinch mid-morph keeps the old
  /// value so the painted mapping stays continuous. Only read while a photos
  /// morph paints.
  double get zoomFocalX;
  set zoomFocalX(double value);

  /// Item [id]'s rect in the last solved [count]-column endpoint layout of the
  /// active zoom morph (offsets included), or null when that count is not one
  /// of the two endpoints the render object last solved. Lets the coordinator
  /// read the cell an endpoint actually paints the anchor in, without a solve.
  Rect? endpointRectOf(int count, Object id);

  /// Re-target the scroll anchor onto [newId] without moving the pinned point.
  void reanchor(Object newId);

  /// Convert a global point to grid-local layout coordinates and back. The box
  /// is the identity via its render transform; the sliver additionally folds in
  /// the sliver scroll offset so layout coordinates stay viewport-
  /// independent.
  Offset globalToGridLocal(Offset global);
  Offset gridLocalToGlobal(Offset local);

  void markNeedsGridLayout();
  void markNeedsGridPaint();
}
