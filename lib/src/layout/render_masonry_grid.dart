// Render object fields are private and exposed through setters that invalidate
// layout or paint, so they cannot be initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The zoom fraction by which the incoming rendition has ramped to full opacity.
/// Kept small so the new grid materialises almost immediately, like Photos,
/// rather than staying hidden behind the old one for the first stretch of the
/// morph; the outgoing rendition ghosts out linearly above it the whole way.
const double _kIncomingSolidAt = 0.18;

/// What a child contributes to the layout.
enum GridChildRole {
  header,
  item,

  /// A removed item, painted at its frozen rect while it fades out. Excluded
  /// from the masonry flow so surviving items immediately reflow into its gap.
  ghost,
  footer,
}

/// Which end of the zoom morph an item copy renders during a crossfade.
///
/// The slot is *relative* to the animated zoom level: `low` renders the
/// `floor(zoom)`-column layout, `high` the `ceil(zoom)` one. When the zoom
/// crosses an integer, the pair rolls over and the copies are simply
/// re-measured at their slot's new width — no rebuild is needed.
enum ZoomSlot { none, low, high }

class GridChildParentData extends ContainerBoxParentData<RenderBox> {
  Object? id;
  Object? sectionId;
  GridChildRole role = GridChildRole.item;

  /// Set for [GridChildRole.ghost] children: the size they had when removed.
  Size? ghostSize;

  /// Which crossfade rendering this item copy belongs to.
  ZoomSlot zoomSlot = ZoomSlot.none;

  /// True for the transient second copy created during a crossfade. It is
  /// excluded from hit testing and never populates the item-size caches.
  bool isZoomOverlay = false;
}

/// Attaches identity and role to a child of [RenderMasonryGrid].
class GridChild extends ParentDataWidget<GridChildParentData> {
  const GridChild({
    required this.id,
    required this.sectionId,
    required this.role,
    required super.child,
    this.ghostSize,
    this.zoomSlot = ZoomSlot.none,
    this.isZoomOverlay = false,
    super.key,
  });

  final Object id;
  final Object sectionId;
  final GridChildRole role;
  final Size? ghostSize;
  final ZoomSlot zoomSlot;
  final bool isZoomOverlay;

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData! as GridChildParentData;
    var needsLayout = false;

    if (parentData.id != id) {
      parentData.id = id;
      needsLayout = true;
    }
    if (parentData.sectionId != sectionId) {
      parentData.sectionId = sectionId;
      needsLayout = true;
    }
    if (parentData.role != role) {
      parentData.role = role;
      needsLayout = true;
    }
    if (parentData.ghostSize != ghostSize) {
      parentData.ghostSize = ghostSize;
      needsLayout = true;
    }
    if (parentData.zoomSlot != zoomSlot) {
      parentData.zoomSlot = zoomSlot;
      needsLayout = true;
    }
    if (parentData.isZoomOverlay != isZoomOverlay) {
      parentData.isZoomOverlay = isZoomOverlay;
      needsLayout = true;
    }

    if (needsLayout) {
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => MasonryGridBody;
}

/// The per-section knobs the render object needs but that live outside the
/// child list.
@immutable
class SectionLayoutConfig {
  const SectionLayoutConfig({
    required this.id,
    required this.collapseWhenEmpty,
    required this.emptyDropExtent,
  });

  final Object id;
  final bool collapseWhenEmpty;
  final double emptyDropExtent;

  @override
  bool operator ==(Object other) =>
      other is SectionLayoutConfig && other.id == id && other.collapseWhenEmpty == collapseWhenEmpty && other.emptyDropExtent == emptyDropExtent;

  @override
  int get hashCode => Object.hash(id, collapseWhenEmpty, emptyDropExtent);
}

class MasonryGridBody extends MultiChildRenderObjectWidget {
  const MasonryGridBody({
    required this.animator,
    required this.sectionConfigs,
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.padding,
    required this.textDirection,
    required this.isDragging,
    required this.liftScale,
    required super.children,
    super.key,
  });

  final GridAnimator animator;
  final List<SectionLayoutConfig> sectionConfigs;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets padding;
  final TextDirection textDirection;
  final bool isDragging;
  final double liftScale;

  @override
  RenderMasonryGrid createRenderObject(BuildContext context) => RenderMasonryGrid(
    animator: animator,
    sectionConfigs: sectionConfigs,
    crossAxisCount: crossAxisCount,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
    padding: padding,
    textDirection: textDirection,
    isDragging: isDragging,
    liftScale: liftScale,
  );

  @override
  void updateRenderObject(BuildContext context, RenderMasonryGrid renderObject) {
    renderObject
      ..animator = animator
      ..sectionConfigs = sectionConfigs
      ..crossAxisCount = crossAxisCount
      ..crossAxisSpacing = crossAxisSpacing
      ..mainAxisSpacing = mainAxisSpacing
      ..padding = padding
      ..textDirection = textDirection
      ..isDragging = isDragging
      ..liftScale = liftScale;
  }
}

/// Lays every child out in one pass — children report their intrinsic heights
/// at a fixed column width, the masonry solver turns those heights into rects,
/// and the box sizes itself to the exact result. No estimation, no post-frame
/// measurement, so the first frame is already correct.
///
/// Springs never invalidate layout: item offsets are applied at paint time.
/// Only the animated total height and section collapse feed back into layout.
class RenderMasonryGrid extends RenderBox with ContainerRenderObjectMixin<RenderBox, GridChildParentData>, RenderBoxContainerDefaultsMixin<RenderBox, GridChildParentData> {
  RenderMasonryGrid({
    required GridAnimator animator,
    required List<SectionLayoutConfig> sectionConfigs,
    required int crossAxisCount,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required EdgeInsets padding,
    required TextDirection textDirection,
    required bool isDragging,
    required double liftScale,
  }) : _animator = animator,
       _sectionConfigs = sectionConfigs,
       _crossAxisCount = crossAxisCount,
       _crossAxisSpacing = crossAxisSpacing,
       _mainAxisSpacing = mainAxisSpacing,
       _padding = padding,
       _textDirection = textDirection,
       _isDragging = isDragging,
       _liftScale = liftScale;

  GridAnimator _animator;
  GridAnimator get animator => _animator;
  set animator(GridAnimator value) {
    if (_animator == value) return;
    _animator = value;
    markNeedsLayout();
  }

  List<SectionLayoutConfig> _sectionConfigs;
  set sectionConfigs(List<SectionLayoutConfig> value) {
    if (listEquals(_sectionConfigs, value)) return;
    _sectionConfigs = value;
    markNeedsLayout();
  }

  int _crossAxisCount;
  set crossAxisCount(int value) {
    if (_crossAxisCount == value) return;
    _crossAxisCount = value;
    markNeedsLayout();
  }

  double _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing == value) return;
    _crossAxisSpacing = value;
    markNeedsLayout();
  }

  double _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing == value) return;
    _mainAxisSpacing = value;
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  bool _isDragging;
  set isDragging(bool value) {
    if (_isDragging == value) return;
    _isDragging = value;
    markNeedsLayout();
  }

  double _liftScale;
  set liftScale(double value) {
    if (_liftScale == value) return;
    _liftScale = value;
    markNeedsPaint();
  }

  /// True until the first layout has run, so initial positions are jumped to
  /// rather than sprung from zero.
  bool _isFirstLayout = true;

  /// Whether the previous layout ran with the zoom in flight. Paint follows
  /// the frame-exact lerped rects during a zoom while the item springs merely
  /// track; on the collapse frame the springs must jump to the endpoint rects
  /// (exactly where the copies were painting) or a fast release hands paint
  /// over to lagging springs — a one-frame scatter that then glides back.
  bool _wasZoomActive = false;

  GridLayoutResult? _lastLayout;
  GridLayoutResult? get lastLayout => _lastLayout;

  final Map<Object, Size> _itemSizes = {};
  Map<Object, Size> get itemSizes => Map.unmodifiable(_itemSizes);

  /// Per-slot measured item heights. During a crossfade the low solve must use
  /// heights measured at the low-count column width and the high solve heights
  /// measured at the high-count width; the anchor predictor mirrors the same
  /// split. In single mode both maps hold the one measured height.
  final Map<Object, double> _lowSlotHeights = {};
  final Map<Object, double> _highSlotHeights = {};
  Map<Object, double> get lowSlotItemHeights => Map.unmodifiable(_lowSlotHeights);
  Map<Object, double> get highSlotItemHeights => Map.unmodifiable(_highSlotHeights);

  /// The column counts the per-slot height maps were measured at in the last
  /// layout pass. The anchor predictor keys its height lookup by count, so a
  /// pair rollover between layouts never feeds a solve heights measured at a
  /// neighbouring count's width.
  ({int low, int high}) get measuredPair => (low: _lastLowCount, high: _lastHighCount);

  /// Measured chrome extents, before any collapse factor is applied. The drag
  /// resolver replays the solver with collapse suppressed, so it wants these.
  final Map<Object, double> _headerHeights = {};
  final Map<Object, double> _footerHeights = {};
  double headerHeightOf(Object sectionId) => _headerHeights[sectionId] ?? 0;
  double footerHeightOf(Object sectionId) => _footerHeights[sectionId] ?? 0;

  /// Width the items were last laid out at, used to detect resizes mid-drag.
  double get lastContentWidth => _lastContentWidth;
  double _lastContentWidth = 0;

  /// Crossfade values stashed at layout time for paint. Paint-only frames must
  /// stay coherent with [_lastLayout], so paint never re-reads the zoom spring.
  double _lastT = 0;
  double _lastLowWidth = 0;
  double _lastHighWidth = 0;
  double _lastItemWidth = 0;
  int _lastLowCount = 1;
  int _lastHighCount = 1;

  /// The item the pinch's scroll pinning is anchored on, and the (unclamped)
  /// fractional point inside it that the widget keeps under the fingers by
  /// adjusting the ancestor scroll offset each frame. Purely a scroll concern:
  /// paint positions every copy from the lerped layout regardless of the
  /// anchor. No invalidation is needed on assignment.
  Object? zoomAnchorId;
  Offset zoomAnchorFraction = Offset.zero;

  /// Re-targets the scroll anchor onto [newId] without moving the pinned
  /// point: the new fraction reproduces the old anchor's screen y exactly, so
  /// the scroll correction stays continuous. Used when the anchor item leaves
  /// the data mid-zoom.
  void reanchor(Object newId) {
    final oldId = zoomAnchorId;
    final oldRect = oldId == null ? null : _lastLayout?.itemRects[oldId];
    final newRect = _lastLayout?.itemRects[newId];
    if (oldRect != null && newRect != null && newRect.height != 0) {
      final invariantY = oldRect.top + zoomAnchorFraction.dy * oldRect.height;
      zoomAnchorFraction = Offset(0, (invariantY - newRect.top) / newRect.height);
    }
    zoomAnchorId = newId;
  }

  /// The crossfade state of the last layout pass, for tests.
  @visibleForTesting
  ({int low, int high, double t, double lowWidth, double highWidth, double itemWidth, Object? anchorId}) get debugCrossfade => (
    low: _lastLowCount,
    high: _lastHighCount,
    t: _lastT,
    lowWidth: _lastLowWidth,
    highWidth: _lastHighWidth,
    itemWidth: _lastItemWidth,
    anchorId: zoomAnchorId,
  );

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! GridChildParentData) {
      child.parentData = GridChildParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : constraints.minWidth;

    // Geometry is driven by the animated zoom level, not the committed count, so
    // a pinch or a settle morphs continuously between two integer layouts.
    final zoom = _animator.zoomLevel.value;
    final lowCount = zoom.floor() < 1 ? 1 : zoom.floor();
    final highCount = zoom.ceil() < 1 ? 1 : zoom.ceil();
    final t = lowCount == highCount ? 0.0 : zoom - lowCount;

    final probe = GridLayoutSpec(
      width: width,
      sections: const [],
      crossAxisSpacing: _crossAxisSpacing,
      mainAxisSpacing: _mainAxisSpacing,
      padding: _padding,
      textDirection: _textDirection,
    );
    final lowWidth = probe.columnWidthFor(lowCount);
    final highWidth = probe.columnWidthFor(highCount);
    // The visual column width mid-morph. Slot-tagged copies are measured at
    // their own endpoint width and only scaled toward this; untagged items
    // (live-reflow mode) are measured directly at it. Both agree exactly at the
    // endpoints because it lerps between the two slot widths.
    final itemWidth = lowWidth + (highWidth - lowWidth) * t;

    final measured = _measureSections(lowWidth: lowWidth, highWidth: highWidth, itemWidth: itemWidth, contentWidth: probe.contentWidth);

    final specLow = GridLayoutSpec(
      width: width,
      sections: measured.low,
      crossAxisCount: lowCount,
      crossAxisSpacing: _crossAxisSpacing,
      mainAxisSpacing: _mainAxisSpacing,
      padding: _padding,
      textDirection: _textDirection,
    );

    // Fast path: at an integer zoom the two endpoints coincide, so solve once.
    final GridLayoutResult result;
    if (lowCount == highCount) {
      result = computeMasonryLayout(specLow);
    } else {
      final lowResult = computeMasonryLayout(specLow);
      final highResult = computeMasonryLayout(
        GridLayoutSpec(
          width: width,
          sections: measured.high,
          crossAxisCount: highCount,
          crossAxisSpacing: _crossAxisSpacing,
          mainAxisSpacing: _mainAxisSpacing,
          padding: _padding,
          textDirection: _textDirection,
        ),
      );
      result = lerpGridLayoutResult(lowResult, highResult, t);
    }

    _lastLayout = result;
    _lastContentWidth = probe.contentWidth;
    _lastT = t;
    _lastLowWidth = lowWidth;
    _lastHighWidth = highWidth;
    _lastItemWidth = itemWidth;
    _lastLowCount = lowCount;
    _lastHighCount = highCount;

    // Ghosts sit outside the flow; give them the size they had when removed.
    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as GridChildParentData;
      if (parentData.role == GridChildRole.ghost) {
        final ghostSize = parentData.ghostSize ?? Size(itemWidth, 0);
        child.layout(BoxConstraints.tight(ghostSize));
      }
      child = parentData.nextSibling;
    }

    final zoomActive = _animator.zoomActive;
    _animator
      ..syncTargets(
        rects: result.itemRects,
        totalHeight: result.totalHeight,
        // On the collapse frame (zoom just ended) the springs jump to the
        // endpoint rects the rigid canvases were painting — pixel-identical
        // hand-off instead of a lagging-spring scatter.
        jump: _isFirstLayout || (_wasZoomActive && !zoomActive),
        zoomActive: zoomActive,
      )
      ..clearNeedsLayout();

    size = constraints.constrain(Size(width, _isFirstLayout ? result.totalHeight : _animator.height));
    _isFirstLayout = false;
    _wasZoomActive = zoomActive;
  }

  /// Lays out every child at its role's (and zoom slot's) constraints, reads
  /// back the measured heights, and assembles per-slot section specs (with
  /// collapse and empty-drop extents applied) for the two endpoint solves.
  ///
  /// Untagged items measure at [itemWidth] and feed both slots identically —
  /// the single-mode and live-reflow paths. Slot-tagged crossfade copies
  /// measure at their own endpoint width and feed only their slot, so each
  /// endpoint solve uses heights measured at that endpoint's exact width.
  ({List<GridSectionSpec> low, List<GridSectionSpec> high}) _measureSections({
    required double lowWidth,
    required double highWidth,
    required double itemWidth,
    required double contentWidth,
  }) {
    final headerHeights = _headerHeights;
    final footerHeights = _footerHeights;
    final lowItemsBySection = <Object, List<GridItemSpec>>{};
    final highItemsBySection = <Object, List<GridItemSpec>>{};
    for (final config in _sectionConfigs) {
      lowItemsBySection[config.id] = [];
      highItemsBySection[config.id] = [];
    }

    _itemSizes.clear();
    _lowSlotHeights.clear();
    _highSlotHeights.clear();
    headerHeights.clear();
    footerHeights.clear();

    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as GridChildParentData;
      final sectionId = parentData.sectionId;
      final id = parentData.id;

      switch (parentData.role) {
        case GridChildRole.header:
        case GridChildRole.footer:
          child.layout(BoxConstraints.tightFor(width: contentWidth), parentUsesSize: true);
          final height = child.size.height;
          if (sectionId != null) {
            if (parentData.role == GridChildRole.header) {
              headerHeights[sectionId] = height;
            } else {
              footerHeights[sectionId] = height;
            }
          }
        case GridChildRole.item:
          final measureWidth = switch (parentData.zoomSlot) {
            ZoomSlot.none => itemWidth,
            ZoomSlot.low => lowWidth,
            ZoomSlot.high => highWidth,
          };
          child.layout(BoxConstraints.tightFor(width: measureWidth), parentUsesSize: true);
          if (id != null && sectionId != null) {
            if (!parentData.isZoomOverlay) {
              _itemSizes[id] = child.size;
            }
            final spec = GridItemSpec(id: id, height: child.size.height);
            if (parentData.zoomSlot != ZoomSlot.high) {
              _lowSlotHeights[id] = child.size.height;
              lowItemsBySection[sectionId]?.add(spec);
            }
            if (parentData.zoomSlot != ZoomSlot.low) {
              _highSlotHeights[id] = child.size.height;
              highItemsBySection[sectionId]?.add(spec);
            }
          }
        case GridChildRole.ghost:
          break;
      }

      child = parentData.nextSibling;
    }

    assert(
      () {
        for (final config in _sectionConfigs) {
          final lowIds = lowItemsBySection[config.id]!.map((item) => item.id).toSet();
          final highIds = highItemsBySection[config.id]!.map((item) => item.id).toSet();
          if (!setEquals(lowIds, highIds)) return false;
          if (lowIds.length != lowItemsBySection[config.id]!.length) return false;
        }
        return true;
      }(),
      'each item id must appear exactly once per zoom slot',
    );

    final lowSections = <GridSectionSpec>[];
    final highSections = <GridSectionSpec>[];
    for (final config in _sectionConfigs) {
      final lowItems = lowItemsBySection[config.id] ?? const <GridItemSpec>[];
      final highItems = highItemsBySection[config.id] ?? const <GridItemSpec>[];
      final isEmpty = lowItems.isEmpty;

      // Collapse is suppressed during a drag so a section that just lost its
      // last item stays on screen as a drop target.
      final wantsCollapse = isEmpty && config.collapseWhenEmpty && !_isDragging;
      _animator.setCollapseTarget(config.id, wantsCollapse ? 1 : 0, jump: _isFirstLayout);
      final collapse = _animator.collapseOf(config.id).clamp(0.0, 1.0);
      final expansion = 1 - collapse;

      final headerHeight = (headerHeights[config.id] ?? 0) * expansion;
      final footerHeight = (footerHeights[config.id] ?? 0) * expansion;
      final emptyExtent = isEmpty && _isDragging ? config.emptyDropExtent : 0.0;

      lowSections.add(
        GridSectionSpec(id: config.id, items: lowItems, headerHeight: headerHeight, footerHeight: footerHeight, emptyExtent: emptyExtent),
      );
      highSections.add(
        GridSectionSpec(id: config.id, items: highItems, headerHeight: headerHeight, footerHeight: footerHeight, emptyExtent: emptyExtent),
      );
    }

    return (low: lowSections, high: highSections);
  }

  /// Where a child should paint: its animated offset, falling back to the
  /// freshly solved rect for children that have no spring yet.
  Offset _offsetOf(GridChildParentData parentData) {
    final layout = _lastLayout;
    final id = parentData.id;
    final sectionId = parentData.sectionId;

    switch (parentData.role) {
      case GridChildRole.header:
        return layout?.sections[sectionId]?.headerRect.topLeft ?? Offset.zero;
      case GridChildRole.footer:
        return layout?.sections[sectionId]?.footerRect.topLeft ?? Offset.zero;
      case GridChildRole.ghost:
        return (id == null ? null : _animator.ghostRects[id]?.topLeft) ?? Offset.zero;
      case GridChildRole.item:
        if (id == null) return Offset.zero;
        return _animator.offsetOf(id) ?? layout?.itemRects[id]?.topLeft ?? Offset.zero;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_animator.zoomActive) {
      // Scaled copies of non-aspect-preserving items can overhang the lerped
      // total height mid-morph, and the ancestor viewport only pushes its clip
      // when it has visual overflow of its own — a short, unscrolled grid
      // would bleed over trailing UI. The grid owns the clip while a zoom is
      // in flight; at rest the layer tree is unchanged.
      context.pushClipRect(needsCompositing, offset, Offset.zero & size, _paintContents);
    } else {
      _paintContents(context, offset);
    }
  }

  void _paintContents(PaintingContext context, Offset offset) {
    RenderBox? dragged;
    GridChildParentData? draggedData;
    final lowSlot = <RenderBox>[];
    final highSlot = <RenderBox>[];
    final chrome = <RenderBox>[];

    var child = firstChild;
    while (child != null) {
      final parentData = child.parentData! as GridChildParentData;
      if (parentData.role == GridChildRole.item && parentData.id == _animator.draggedId && !parentData.isZoomOverlay) {
        // Painted last so it floats above its neighbours.
        dragged = child;
        draggedData = parentData;
      } else if (parentData.zoomSlot == ZoomSlot.low) {
        lowSlot.add(child);
      } else if (parentData.zoomSlot == ZoomSlot.high) {
        highSlot.add(child);
      } else if (parentData.role == GridChildRole.header || parentData.role == GridChildRole.footer) {
        // Deferred so section labels float above the morphing canvases, as in
        // Photos. At rest chrome never overlaps items, so the output is
        // unchanged.
        chrome.add(child);
      } else {
        // Ghosts and single-mode items paint here, beneath the canvases.
        _paintChild(context, offset, child, parentData);
      }
      child = parentData.nextSibling;
    }

    // Crossfade layering, iOS-Photos style: the incoming (high) renditions
    // paint first, below, ramping to solid within the first fifth of the
    // morph; the outgoing (low) renditions ghost out linearly above the whole
    // way. Because an item's two renditions coincide, each tile stays
    // near-opaque throughout (combined opacity dips no lower than ~0.955,
    // around t ≈ 0.09, for a couple of frames before the incoming is solid),
    // so the background never washes through; both alphas are pure functions
    // of t, so a reversed pinch scrubs back through the same frames; and at
    // each endpoint exactly one rendition paints solid and direct, keeping
    // enter/leave/collapse pixel-identical.
    final t = _lastT.clamp(0.0, 1.0);
    _paintSlotGroup(context, offset, highSlot, (t / _kIncomingSolidAt).clamp(0.0, 1.0));
    _paintSlotGroup(context, offset, lowSlot, 1 - t);

    for (final header in chrome) {
      _paintChild(context, offset, header, header.parentData! as GridChildParentData);
    }

    if (dragged != null && draggedData != null) {
      _paintChild(context, offset, dragged, draggedData, scale: 1 + (_liftScale - 1) * _animator.lift.value);
    }
  }

  /// Paints one crossfade rendition group at [groupAlpha]: direct when opaque,
  /// under one shared opacity layer when translucent, skipped when invisible.
  void _paintSlotGroup(PaintingContext context, Offset offset, List<RenderBox> group, double groupAlpha) {
    if (group.isEmpty || groupAlpha <= 0) return;
    if (groupAlpha >= 1) {
      for (final copy in group) {
        _paintChild(context, offset, copy, copy.parentData! as GridChildParentData);
      }
      return;
    }
    context.pushOpacity(offset, (groupAlpha * 255).round(), (groupContext, groupOffset) {
      for (final copy in group) {
        _paintChild(groupContext, groupOffset, copy, copy.parentData! as GridChildParentData);
      }
    });
  }

  /// Where and how big a child paints, in grid-local coordinates.
  ///
  /// Slot-tagged crossfade copies ride the item's own lerped-layout rect,
  /// scaled from their endpoint width to the interpolated width — so an item's
  /// two renditions coincide and every tile reads as one element travelling
  /// from its old slot to its new slot, iOS-Photos style. The rect is the
  /// frame-exact lerp (not the tracking springs, which lag a fast pinch by
  /// tens of pixels and would break the finger pinning that predicts this
  /// exact layout). Everyone else paints at the animated offset. Shared by
  /// paint, hit testing, and [applyPaintTransform] so pixels and
  /// pointer/semantics geometry agree mid-morph.
  ({Offset offset, double scale}) _effectiveGeometryOf(GridChildParentData parentData) {
    final id = parentData.id;
    if (parentData.zoomSlot != ZoomSlot.none && parentData.role == GridChildRole.item && id != null) {
      final copyWidth = parentData.zoomSlot == ZoomSlot.low ? _lastLowWidth : _lastHighWidth;
      return (
        offset: _lastLayout?.itemRects[id]?.topLeft ?? _offsetOf(parentData),
        scale: copyWidth > 0 ? _lastItemWidth / copyWidth : 1.0,
      );
    }
    return (offset: _offsetOf(parentData), scale: 1);
  }

  void _paintChild(
    PaintingContext context,
    Offset offset,
    RenderBox child,
    GridChildParentData parentData, {
    double scale = 1,
  }) {
    final id = parentData.id;
    final geometry = _effectiveGeometryOf(parentData);
    final childOffset = geometry.offset + offset;
    final slotScale = geometry.scale;

    final isItemLike = parentData.role == GridChildRole.item || parentData.role == GridChildRole.ghost;
    final isChrome = parentData.role == GridChildRole.header || parentData.role == GridChildRole.footer;

    final fade = isItemLike && id != null ? _animator.fadeOf(id) : 1.0;

    // Collapsing sections fade their chrome out as it shrinks to nothing.
    final sectionId = parentData.sectionId;
    final chromeFade = isChrome && sectionId != null ? (1 - _animator.collapseOf(sectionId)).clamp(0.0, 1.0) : 1.0;

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
      innerContext.pushTransform(needsCompositing, Offset.zero, transform, (ctx, _) => ctx.paintChild(child, innerOffset));
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
      innerContext.pushTransform(needsCompositing, Offset.zero, transform, (ctx, _) => core(ctx, innerOffset));
    }

    if (opacity < 1) {
      context.pushOpacity(childOffset, (opacity * 255).round(), painter);
    } else {
      painter(context, childOffset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // Reverse order so the visually topmost child wins.
    var child = lastChild;
    while (child != null) {
      final currentChild = child;
      final parentData = currentChild.parentData! as GridChildParentData;
      if (parentData.role != GridChildRole.ghost && !parentData.isZoomOverlay) {
        final geometry = _effectiveGeometryOf(parentData);
        final bool hit;
        if (geometry.scale == 1) {
          hit = result.addWithPaintOffset(
            offset: geometry.offset,
            position: position,
            hitTest: (innerResult, transformed) => currentChild.hitTest(innerResult, position: transformed),
          );
        } else {
          final transform = Matrix4.identity()
            ..translateByDouble(geometry.offset.dx, geometry.offset.dy, 0, 1)
            ..scaleByDouble(geometry.scale, geometry.scale, 1, 1);
          hit = result.addWithPaintTransform(
            transform: transform,
            position: position,
            hitTest: (innerResult, transformed) => currentChild.hitTest(innerResult, position: transformed),
          );
        }
        if (hit) return true;
      }
      child = parentData.previousSibling;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final parentData = child.parentData! as GridChildParentData;
    final geometry = _effectiveGeometryOf(parentData);
    transform.translateByDouble(geometry.offset.dx, geometry.offset.dy, 0, 1);
    if (geometry.scale != 1) {
      transform.scaleByDouble(geometry.scale, geometry.scale, 1, 1);
    }
  }

  @override
  bool get isRepaintBoundary => true;
}
