import 'dart:ui' as ui;

import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:fluid_grid/src/zoom/zoom_cell_offset_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// What a child contributes to the layout.
enum GridChildRole {
  header,
  item,

  /// A removed item, painted at its frozen rect while it fades out. Excluded
  /// from the masonry flow so surviving items immediately reflow into its gap.
  ghost,
  footer,
}

/// The normalised identity of one grid child, independent of how the concrete
/// render object tracks it (the box's `GridChildParentData` vs the sliver's
/// `FluidChildKey`).
///
/// Contract, relied on by every shared paint/hit-test path:
/// - A crossfade overlay copy normalises to `role: item, isOverlay: true`
///   (the sliver's `itemOverlay` kind carries no separate role here).
/// - `slot` is [ZoomSlot.none] whenever the frame is not building dual
///   renditions — resting items, ghosts, and chrome never carry a slot.
/// - `id` is the item id (or ghost id); `sectionId` is the owning section for
///   chrome. The box supplies both from its parent data; the sliver's key id
///   doubles as both (its chrome keys are section ids).
typedef GridChildFacts = ({
  Object? id,
  Object? sectionId,
  GridChildRole role,
  ZoomSlot slot,
  bool isOverlay,
});

/// The render-object glue shared by the box (`RenderMasonryGrid`) and sliver
/// (`RenderSliverFluidGrid`) masonry grids: the zoom-anchor and crossfade
/// state, the photos fixed-point bookkeeping, and the paint / hit-test /
/// geometry plumbing, all written once over [GridChildFacts]. Child
/// bookkeeping and measurement stay per class — they genuinely differ.
mixin MasonryRenderCore on RenderObject {
  // --- Provided by the concrete render object ---

  @protected
  GridAnimator get animator;

  @protected
  ZoomCellOffsetStore get cellOffsets;

  @protected
  GridZoomStyle get zoomStyle;

  @protected
  double get liftScale;

  /// The shift between the incoming paint offset and grid-local coordinates:
  /// zero for the box, `Offset(0, -scrollOffset)` for the sliver.
  @protected
  Offset get childPaintShift;

  /// Every live child, in paint order (bottom-most first).
  @protected
  Iterable<RenderBox> get gridChildren;

  @protected
  GridChildFacts factsOf(RenderBox child);

  // --- Shared state ---

  /// True until the first layout has run, so initial positions are jumped to
  /// rather than sprung from zero.
  @protected
  bool isFirstLayout = true;

  /// Whether the previous layout ran with the zoom in flight. Paint follows
  /// the frame-exact lerped rects during a zoom while the item springs merely
  /// track; on the collapse frame the springs must jump to the endpoint rects
  /// (exactly where the copies were painting) or a fast release hands paint
  /// over to lagging springs — a one-frame scatter that then glides back.
  @protected
  bool wasZoomActive = false;

  /// The photos canvases' shared horizontal fixed point — the anchor's
  /// fraction-matching abscissa ([photosPairFixedX]) — frozen for the lifetime
  /// of one morph pair so mid-morph reanchors (and, on the sliver, measure
  /// passes) never move a painting canvas sideways. Recomputed on a pair
  /// rollover (the fading canvas is at alpha 0 there, so the recompute is
  /// invisible) and cleared when the zoom settles. Null falls back to
  /// [zoomFocalX].
  @protected
  double? photosFixedX;
  @protected
  (int, int)? photosFixedPair;

  /// The last committed solve (satisfies `GridHost.lastLayout`).
  GridLayoutResult? lastLayout;

  /// Width the items were last laid out at, used to detect resizes mid-drag
  /// (satisfies `GridHost.contentWidth`).
  @protected
  double lastContentWidth = 0;

  double get contentWidth => lastContentWidth;

  /// Crossfade values stashed at layout time for paint. Paint-only frames must
  /// stay coherent with [lastLayout], so paint never re-reads the zoom spring.
  @protected
  double lastT = 0;
  @protected
  double lastLowWidth = 0;
  @protected
  double lastHighWidth = 0;
  @protected
  double lastItemWidth = 0;
  @protected
  int lastLowCount = 1;
  @protected
  int lastHighCount = 1;

  /// The two endpoint solves' item rects, kept for [GridZoomStyle.photos],
  /// whose rigid canvases map each rendition through its own column-count
  /// position. Both point at the single solve on the integer fast path.
  @protected
  Map<Object, Rect> lastLowRects = const {};
  @protected
  Map<Object, Rect> lastHighRects = const {};

  /// Measured chrome extents, before any collapse factor is applied. The drag
  /// resolver replays the solver with collapse suppressed, so it wants these.
  @protected
  final Map<Object, double> headerHeights = {};
  @protected
  final Map<Object, double> footerHeights = {};

  double headerHeightOf(Object sectionId) => headerHeights[sectionId] ?? 0;
  double footerHeightOf(Object sectionId) => footerHeights[sectionId] ?? 0;

  /// The item the pinch's scroll pinning is anchored on, and the (unclamped)
  /// fractional point inside it that the widget keeps under the fingers by
  /// adjusting the ancestor scroll offset each frame. Purely a scroll concern:
  /// paint positions every copy from the lerped layout regardless of the
  /// anchor. No invalidation is needed on assignment.
  Object? zoomAnchorId;
  Offset zoomAnchorFraction = Offset.zero;
  double zoomFocalX = 0;

  Rect? endpointRectOf(int count, Object id) {
    if (count == lastLowCount) return lastLowRects[id];
    if (count == lastHighCount) return lastHighRects[id];
    return null;
  }

  /// Re-targets the scroll anchor onto [newId] without moving the pinned
  /// point: the new fraction reproduces the old anchor's grid position exactly
  /// (both axes — [GridZoomStyle.photos] anchors its canvases on x too), so
  /// the scroll correction stays continuous. Used when the anchor item leaves
  /// the data mid-zoom.
  void reanchor(Object newId) {
    final oldId = zoomAnchorId;
    final oldRect = oldId == null ? null : lastLayout?.itemRects[oldId];
    final newRect = lastLayout?.itemRects[newId];
    if (oldRect != null &&
        newRect != null &&
        newRect.width != 0 &&
        newRect.height != 0) {
      final invariant =
          oldRect.topLeft +
          Offset(
            zoomAnchorFraction.dx * oldRect.width,
            zoomAnchorFraction.dy * oldRect.height,
          );
      zoomAnchorFraction = Offset(
        (invariant.dx - newRect.left) / newRect.width,
        (invariant.dy - newRect.top) / newRect.height,
      );
    }
    zoomAnchorId = newId;
  }

  void markNeedsGridLayout() => markNeedsLayout();
  void markNeedsGridPaint() => markNeedsPaint();

  @override
  bool get isRepaintBoundary => true;

  // --- Debug hooks (read directly by tests; names and shapes are pinned) ---

  /// The crossfade state of the last layout pass, for tests.
  @visibleForTesting
  ({
    int low,
    int high,
    double t,
    double lowWidth,
    double highWidth,
    double itemWidth,
    Object? anchorId,
    Map<Object, int> lowOffsets,
    Map<Object, int> highOffsets,
  })
  get debugCrossfade => (
    low: lastLowCount,
    high: lastHighCount,
    t: lastT,
    lowWidth: lastLowWidth,
    highWidth: lastHighWidth,
    itemWidth: lastItemWidth,
    anchorId: zoomAnchorId,
    lowOffsets: cellOffsets.forCount(lastLowCount),
    highOffsets: cellOffsets.forCount(lastHighCount),
  );

  /// The last solve's endpoint rects, for tests asserting the photos-canvas
  /// geometry.
  @visibleForTesting
  Map<Object, Rect> get debugLowRects => lastLowRects;
  @visibleForTesting
  Map<Object, Rect> get debugHighRects => lastHighRects;

  /// The photos canvases' frozen shared horizontal fixed point, for tests.
  @visibleForTesting
  double? get debugPhotosFixedX => photosFixedX;

  // --- Layout-tail helpers (called by each performLayout) ---

  /// The horizontal fixed point the photos canvases expand about this frame.
  @protected
  double get photosFocalX => photosFixedX ?? zoomFocalX;

  /// Freezes the photos pair's shared fixed point on first sight of [pair]:
  /// the fraction-matching abscissa is t-independent, so holding it for the
  /// whole morph keeps both canvases pinned while making the anchor's two
  /// renditions coincide horizontally. Each class calls this under its own
  /// style/anchor guard.
  @protected
  void maybeFreezePhotosFixedX({
    required Rect? anchorLowRect,
    required Rect? anchorHighRect,
    required double lowWidth,
    required double highWidth,
    required double gridWidth,
    required (int, int) pair,
  }) {
    if (photosFixedX != null && photosFixedPair == pair) return;
    final fixedX = photosPairFixedX(
      anchorLowRect: anchorLowRect,
      anchorHighRect: anchorHighRect,
      lowWidth: lowWidth,
      highWidth: highWidth,
      gridWidth: gridWidth,
    );
    if (fixedX != null) {
      photosFixedX = fixedX;
      photosFixedPair = pair;
    }
  }

  /// Commits one solve's crossfade values, which paint-only frames re-read.
  @protected
  void commitZoomFrame({
    required GridLayoutResult result,
    required double contentWidth,
    required double t,
    required double lowWidth,
    required double highWidth,
    required double itemWidth,
    required int lowCount,
    required int highCount,
    required Map<Object, Rect> lowRects,
    required Map<Object, Rect> highRects,
  }) {
    lastLayout = result;
    lastContentWidth = contentWidth;
    lastT = t;
    lastLowWidth = lowWidth;
    lastHighWidth = highWidth;
    lastItemWidth = itemWidth;
    lastLowCount = lowCount;
    lastHighCount = highCount;
    lastLowRects = lowRects;
    lastHighRects = highRects;
  }

  /// The end of every layout pass: records first-layout / zoom-activity state
  /// and drops the photos fixed point once the zoom has settled.
  @protected
  void finishGridLayout({required bool zoomActive}) {
    isFirstLayout = false;
    wasZoomActive = zoomActive;
    if (!zoomActive) {
      photosFixedX = null;
      photosFixedPair = null;
    }
  }

  // --- Geometry shared by paint and hit test (grid-local coordinates) ---

  /// Where a child should paint at rest: its animated offset, falling back to
  /// the freshly solved rect for children that have no spring yet.
  @protected
  Offset restingOffsetOf(GridChildFacts facts) {
    final layout = lastLayout;
    switch (facts.role) {
      case GridChildRole.header:
        return layout?.sections[facts.sectionId]?.headerRect.topLeft ??
            Offset.zero;
      case GridChildRole.footer:
        return layout?.sections[facts.sectionId]?.footerRect.topLeft ??
            Offset.zero;
      case GridChildRole.ghost:
        final id = facts.id;
        return (id == null ? null : animator.ghostRects[id]?.topLeft) ??
            Offset.zero;
      case GridChildRole.item:
        final id = facts.id;
        if (id == null) return Offset.zero;
        return animator.offsetOf(id) ??
            layout?.itemRects[id]?.topLeft ??
            Offset.zero;
    }
  }

  /// Where and how big a child paints, in grid-local coordinates.
  ///
  /// Under [GridZoomStyle.morph], slot-tagged crossfade copies ride the item's
  /// own lerped-layout rect, scaled from their endpoint width to the
  /// interpolated width — so an item's two renditions coincide and every tile
  /// reads as one element travelling from its old slot to its new slot,
  /// iOS-Photos style. The rect is the frame-exact lerp (not the tracking
  /// springs, which lag a fast pinch by tens of pixels and would break the
  /// finger pinning that predicts this exact layout).
  ///
  /// Under [GridZoomStyle.photos] each copy rides its endpoint layout through a
  /// rigid canvas transform, falling back to the travelling-morph geometry when
  /// the anchor data is incomplete.
  ///
  /// Everyone else paints at the animated offset. Shared by paint, hit testing,
  /// and `applyPaintTransform` so pixels and pointer/semantics geometry agree
  /// mid-morph.
  @protected
  ({Offset offset, double scale}) effectiveGeometryOf(GridChildFacts facts) {
    final id = facts.id;
    if (facts.slot != ZoomSlot.none &&
        facts.role == GridChildRole.item &&
        id != null) {
      final isLow = facts.slot == ZoomSlot.low;
      final endpointRects = isLow ? lastLowRects : lastHighRects;
      final endpointWidth = isLow ? lastLowWidth : lastHighWidth;

      // Photos: the whole rendition rides one rigid canvas transform anchored
      // at the pinch focal point. Falls through to the travelling-morph
      // geometry when no anchor is available (e.g. anchor data incomplete).
      if (zoomStyle == GridZoomStyle.photos) {
        final anchorId = zoomAnchorId;
        final canvas = photosCanvasGeometry(
          endpointRect: endpointRects[id],
          anchorEndpointRect: anchorId == null ? null : endpointRects[anchorId],
          anchorLerpedRect: anchorId == null
              ? null
              : lastLayout?.itemRects[anchorId],
          anchorFraction: zoomAnchorFraction,
          endpointWidth: endpointWidth,
          itemWidth: lastItemWidth,
          focalX: photosFocalX,
        );
        if (canvas != null) return canvas;
      }

      return crossfadeRenditionGeometry(
        lerpedRect: lastLayout?.itemRects[id],
        endpointWidth: endpointWidth,
        itemWidth: lastItemWidth,
        fallback: restingOffsetOf(facts),
      );
    }
    return (offset: restingOffsetOf(facts), scale: 1);
  }

  /// [effectiveGeometryOf] keyed by the child itself, for the sliver's
  /// child-position callbacks.
  @protected
  ({Offset offset, double scale}) effectiveGeometryOfChild(RenderBox child) =>
      effectiveGeometryOf(factsOf(child));

  // --- Paint ---

  /// Paints every child: ghosts and resting items first, then the crossfade
  /// slot groups, then chrome (so section labels float above the morphing
  /// canvases, as in Photos — at rest chrome never overlaps items, so the
  /// output is unchanged), then the dragged item on top.
  @protected
  void paintGridContents(PaintingContext context, Offset offset) {
    final origin = offset + childPaintShift;

    RenderBox? dragged;
    final lowSlot = <RenderBox>[];
    final highSlot = <RenderBox>[];
    final chrome = <RenderBox>[];

    for (final child in gridChildren) {
      final facts = factsOf(child);
      if (facts.role == GridChildRole.item &&
          !facts.isOverlay &&
          facts.id != null &&
          facts.id == animator.draggedId) {
        // Painted last so it floats above its neighbours.
        dragged = child;
      } else if (facts.slot == ZoomSlot.low) {
        lowSlot.add(child);
      } else if (facts.slot == ZoomSlot.high) {
        highSlot.add(child);
      } else if (facts.role == GridChildRole.header ||
          facts.role == GridChildRole.footer) {
        chrome.add(child);
      } else {
        // Ghosts and single-mode items paint here, beneath the canvases.
        paintGridChild(context, origin, child);
      }
    }

    // Crossfade layering. The incoming (high) renditions paint first, below,
    // ramping to solid within the first fifth of the morph; the outgoing (low)
    // renditions ghost out linearly above the whole way. Under
    // GridZoomStyle.morph an item's two renditions coincide, so each tile stays
    // near-opaque throughout (combined opacity dips no lower than ~0.955,
    // around t ≈ 0.09, for a couple of frames before the incoming is solid),
    // so the background never washes through; both alphas are pure functions
    // of t, so a reversed pinch scrubs back through the same frames; and at
    // each endpoint exactly one rendition paints solid and direct, keeping
    // enter/leave/collapse pixel-identical.
    final alphas = crossfadeSlotAlphas(lastT);
    paintSlotGroup(context, origin, highSlot, alphas.high);
    paintSlotGroup(context, origin, lowSlot, alphas.low);

    for (final child in chrome) {
      paintGridChild(context, origin, child);
    }

    if (dragged != null) {
      paintGridChild(
        context,
        origin,
        dragged,
        scale: 1 + (liftScale - 1) * animator.lift.value,
      );
    }
  }

  /// Paints one crossfade rendition group at [groupAlpha]: direct when opaque,
  /// under one shared opacity layer when translucent, skipped when invisible.
  @protected
  void paintSlotGroup(
    PaintingContext context,
    Offset offset,
    List<RenderBox> group,
    double groupAlpha,
  ) {
    if (group.isEmpty || groupAlpha <= 0) return;

    void paintFaded(PaintingContext ctx, Offset off) {
      void copies(PaintingContext c, Offset o) {
        for (final copy in group) {
          paintGridChild(c, o, copy);
        }
      }

      if (groupAlpha >= 1) {
        copies(ctx, off);
      } else {
        ctx.pushOpacity(off, (groupAlpha * 255).round(), copies);
      }
    }

    // Under morph, a fading rendition also dissolves through a blur (crisp at
    // both resting levels). A sub-pixel sigma isn't worth a compositing layer.
    final sigma = morphBlurSigma(zoomStyle, groupAlpha);
    if (sigma < 0.3) {
      paintFaded(context, offset);
      return;
    }
    context.pushLayer(
      ImageFilterLayer(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      ),
      paintFaded,
      offset,
    );
  }

  /// Paints one child at its effective geometry, applying enter/exit fade,
  /// chrome collapse fade, the lift [scale], and the slot's
  /// endpoint-to-interpolated-width scale.
  @protected
  void paintGridChild(
    PaintingContext context,
    Offset offset,
    RenderBox child, {
    double scale = 1,
  }) {
    final facts = factsOf(child);
    final id = facts.id;
    final geometry = effectiveGeometryOf(facts);
    final childOffset = geometry.offset + offset;
    final slotScale = geometry.scale;

    final isItemLike =
        facts.role == GridChildRole.item || facts.role == GridChildRole.ghost;
    final isChrome =
        facts.role == GridChildRole.header ||
        facts.role == GridChildRole.footer;

    final fade = isItemLike && id != null ? animator.fadeOf(id) : 1.0;

    // Collapsing sections fade their chrome out as it shrinks to nothing.
    final sectionId = facts.sectionId;
    final chromeFade = isChrome && sectionId != null
        ? (1 - animator.collapseOf(sectionId)).clamp(0.0, 1.0)
        : 1.0;

    final opacity = (fade * chromeFade).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    // Entering and exiting items scale slightly toward their centre.
    final fadeScale = isItemLike ? 0.92 + 0.08 * fade : 1.0;
    final totalScale = scale * fadeScale;

    void core(PaintingContext innerContext, Offset innerOffset) {
      if (totalScale == 1) {
        innerContext.paintChild(child, innerOffset);
        return;
      }
      final centre = child.size.center(innerOffset);
      final transform = Matrix4.identity()
        ..translateByDouble(centre.dx, centre.dy, 0, 1)
        ..scaleByDouble(totalScale, totalScale, 1, 1)
        ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
      innerContext.pushTransform(
        needsCompositing,
        Offset.zero,
        transform,
        (ctx, _) => ctx.paintChild(child, innerOffset),
      );
    }

    void painter(PaintingContext innerContext, Offset innerOffset) {
      if (slotScale == 1) {
        core(innerContext, innerOffset);
        return;
      }
      // The endpoint-to-interpolated-width scale, anchored at the copy's own
      // top-left so the pair shares its painted origin.
      final transform = Matrix4.identity()
        ..translateByDouble(innerOffset.dx, innerOffset.dy, 0, 1)
        ..scaleByDouble(slotScale, slotScale, 1, 1)
        ..translateByDouble(-innerOffset.dx, -innerOffset.dy, 0, 1);
      innerContext.pushTransform(
        needsCompositing,
        Offset.zero,
        transform,
        (ctx, _) => core(ctx, innerOffset),
      );
    }

    if (opacity < 1) {
      context.pushOpacity(childOffset, (opacity * 255).round(), painter);
    } else {
      painter(context, childOffset);
    }
  }

  // --- Hit test ---

  /// Hit-tests the children in reverse paint order (so the visually topmost
  /// child wins), skipping ghosts and crossfade overlay copies. [position] is
  /// in grid-local coordinates.
  @protected
  bool hitTestGridChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in gridChildren.toList().reversed) {
      final facts = factsOf(child);
      if (facts.role == GridChildRole.ghost || facts.isOverlay) continue;

      final geometry = effectiveGeometryOf(facts);
      final bool hit;
      if (geometry.scale == 1) {
        hit = result.addWithPaintOffset(
          offset: geometry.offset,
          position: position,
          hitTest: (innerResult, transformed) =>
              child.hitTest(innerResult, position: transformed),
        );
      } else {
        final transform = Matrix4.identity()
          ..translateByDouble(geometry.offset.dx, geometry.offset.dy, 0, 1)
          ..scaleByDouble(geometry.scale, geometry.scale, 1, 1);
        hit = result.addWithPaintTransform(
          transform: transform,
          position: position,
          hitTest: (innerResult, transformed) =>
              child.hitTest(innerResult, position: transformed),
        );
      }
      if (hit) return true;
    }
    return false;
  }

  /// The shared body of `applyPaintTransform`: the child's effective geometry
  /// shifted into paint coordinates via [childPaintShift].
  @protected
  void applyGridPaintTransform(RenderBox child, Matrix4 transform) {
    final geometry = effectiveGeometryOfChild(child);
    final shifted = geometry.offset + childPaintShift;
    transform.translateByDouble(shifted.dx, shifted.dy, 0, 1);
    if (geometry.scale != 1) {
      transform.scaleByDouble(geometry.scale, geometry.scale, 1, 1);
    }
  }
}
