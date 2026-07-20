// Render object fields are private and exposed through setters that invalidate
// layout or paint, so they cannot be initializing formals.
// ignore_for_file: prefer_initializing_formals

import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:fluid_grid/src/layout/grid_render_host.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/layout/masonry_render_core.dart';
import 'package:fluid_grid/src/layout/masonry_zoom_solve.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:fluid_grid/src/zoom/zoom_cell_offset_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// [ZoomSlot], the crossfade alpha curves, and the rendition-geometry math are
// shared with the sliver render object, so they live in masonry_paint_math.dart;
// [GridChildRole] and the shared render-object glue live in
// masonry_render_core.dart.
export 'package:fluid_grid/src/layout/masonry_paint_math.dart' show ZoomSlot;
export 'package:fluid_grid/src/layout/masonry_render_core.dart'
    show GridChildRole;

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
      other is SectionLayoutConfig &&
      other.id == id &&
      other.collapseWhenEmpty == collapseWhenEmpty &&
      other.emptyDropExtent == emptyDropExtent;

  @override
  int get hashCode => Object.hash(id, collapseWhenEmpty, emptyDropExtent);
}

class MasonryGridBody extends MultiChildRenderObjectWidget {
  const MasonryGridBody({
    required this.animator,
    required this.cellOffsets,
    required this.sectionConfigs,
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.padding,
    required this.textDirection,
    required this.isDragging,
    required this.liftScale,
    required this.zoomStyle,
    required this.zoomLevels,
    required super.children,
    super.key,
  });

  final GridAnimator animator;

  /// The photos zoom's persistent cell alignment (see [ZoomCellOffsetStore]).
  /// Shared by identity with the coordinator, like [animator].
  final ZoomCellOffsetStore cellOffsets;

  final List<SectionLayoutConfig> sectionConfigs;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets padding;
  final TextDirection textDirection;
  final bool isDragging;
  final double liftScale;
  final GridZoomStyle zoomStyle;
  final List<int>? zoomLevels;

  @override
  RenderMasonryGrid createRenderObject(BuildContext context) =>
      RenderMasonryGrid(
        animator: animator,
        cellOffsets: cellOffsets,
        sectionConfigs: sectionConfigs,
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        padding: padding,
        textDirection: textDirection,
        isDragging: isDragging,
        liftScale: liftScale,
        zoomStyle: zoomStyle,
        zoomLevels: zoomLevels,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMasonryGrid renderObject,
  ) {
    renderObject
      ..animator = animator
      ..cellOffsets = cellOffsets
      ..sectionConfigs = sectionConfigs
      ..crossAxisCount = crossAxisCount
      ..crossAxisSpacing = crossAxisSpacing
      ..mainAxisSpacing = mainAxisSpacing
      ..padding = padding
      ..textDirection = textDirection
      ..isDragging = isDragging
      ..liftScale = liftScale
      ..zoomStyle = zoomStyle
      ..zoomLevels = zoomLevels;
  }
}

/// Lays every child out in one pass — children report their intrinsic heights
/// at a fixed column width, the masonry solver turns those heights into rects,
/// and the box sizes itself to the exact result. No estimation, no post-frame
/// measurement, so the first frame is already correct.
///
/// Springs never invalidate layout: item offsets are applied at paint time.
/// Only the animated total height and section collapse feed back into layout.
class RenderMasonryGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, GridChildParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, GridChildParentData>,
        MasonryRenderCore
    implements GridHost {
  RenderMasonryGrid({
    required GridAnimator animator,
    required ZoomCellOffsetStore cellOffsets,
    required List<SectionLayoutConfig> sectionConfigs,
    required int crossAxisCount,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required EdgeInsets padding,
    required TextDirection textDirection,
    required bool isDragging,
    required double liftScale,
    required GridZoomStyle zoomStyle,
    required List<int>? zoomLevels,
  }) : _animator = animator,
       _cellOffsets = cellOffsets,
       _sectionConfigs = sectionConfigs,
       _crossAxisCount = crossAxisCount,
       _crossAxisSpacing = crossAxisSpacing,
       _mainAxisSpacing = mainAxisSpacing,
       _padding = padding,
       _textDirection = textDirection,
       _isDragging = isDragging,
       _liftScale = liftScale,
       _zoomStyle = zoomStyle,
       _zoomLevels = zoomLevels;

  GridAnimator _animator;
  @override
  GridAnimator get animator => _animator;
  set animator(GridAnimator value) {
    if (_animator == value) return;
    _animator = value;
    markNeedsLayout();
  }

  /// The photos zoom's persistent cell alignment. Identity-shared with the
  /// coordinator, which mutates it and marks layout — no per-frame push.
  ZoomCellOffsetStore _cellOffsets;
  @override
  ZoomCellOffsetStore get cellOffsets => _cellOffsets;
  set cellOffsets(ZoomCellOffsetStore value) {
    if (identical(_cellOffsets, value)) return;
    _cellOffsets = value;
    markNeedsLayout();
  }

  /// The allowed zoom levels; the morph endpoints step between adjacent
  /// members. Null means every integer.
  List<int>? _zoomLevels;
  set zoomLevels(List<int>? value) {
    if (listEquals(_zoomLevels, value)) return;
    _zoomLevels = value;
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
  @override
  double get liftScale => _liftScale;
  set liftScale(double value) {
    if (_liftScale == value) return;
    _liftScale = value;
    markNeedsPaint();
  }

  /// How item copies are placed and blended during a zoom morph. Position of
  /// the slot copies is paint/hit-test geometry, not layout, so a change only
  /// repaints.
  GridZoomStyle _zoomStyle;
  @override
  GridZoomStyle get zoomStyle => _zoomStyle;
  set zoomStyle(GridZoomStyle value) {
    if (_zoomStyle == value) return;
    _zoomStyle = value;
    markNeedsPaint();
  }

  @override
  Offset get childPaintShift => Offset.zero;

  @override
  Iterable<RenderBox> get gridChildren sync* {
    var child = firstChild;
    while (child != null) {
      yield child;
      child = (child.parentData! as GridChildParentData).nextSibling;
    }
  }

  @override
  GridChildFacts factsOf(RenderBox child) {
    final parentData = child.parentData! as GridChildParentData;
    return (
      id: parentData.id,
      sectionId: parentData.sectionId,
      role: parentData.role,
      slot: parentData.zoomSlot,
      isOverlay: parentData.isZoomOverlay,
    );
  }

  final Map<Object, Size> _itemSizes = {};

  @override
  Size? itemSizeOf(Object id) => _itemSizes[id];

  @override
  Map<Object, double> itemHeights() => {
    for (final entry in _itemSizes.entries) entry.key: entry.value.height,
  };

  /// Per-slot measured item heights. During a crossfade the low solve must use
  /// heights measured at the low-count column width and the high solve heights
  /// measured at the high-count width; the anchor predictor mirrors the same
  /// split. In single mode both maps hold the one measured height.
  final Map<Object, double> _lowSlotHeights = {};
  final Map<Object, double> _highSlotHeights = {};

  @override
  Map<Object, double>? itemHeightsForColumns(int count) {
    if (count == lastLowCount) return _lowSlotHeights;
    if (count == lastHighCount) return _highSlotHeights;
    return null;
  }

  @override
  Map<Object, double> nearestItemHeightsForColumns(int count) =>
      (count - lastLowCount).abs() <= (count - lastHighCount).abs()
      ? _lowSlotHeights
      : _highSlotHeights;

  @override
  double get gridWidth => hasSize ? size.width : lastContentWidth;

  @override
  Offset globalToGridLocal(Offset global) => globalToLocal(global);

  @override
  Offset gridLocalToGlobal(Offset local) => localToGlobal(local);

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! GridChildParentData) {
      child.parentData = GridChildParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;

    // Geometry is driven by the animated zoom level, not the committed count, so
    // a pinch or a settle morphs continuously between two integer layouts.
    final endpoints = zoomEndpoints(
      zoom: _animator.zoomLevel.value,
      width: width,
      crossAxisSpacing: _crossAxisSpacing,
      mainAxisSpacing: _mainAxisSpacing,
      padding: _padding,
      textDirection: _textDirection,
      levels: _zoomLevels,
    );
    final lowCount = endpoints.lowCount;
    final highCount = endpoints.highCount;
    final t = endpoints.t;
    final lowWidth = endpoints.lowWidth;
    final highWidth = endpoints.highWidth;
    final itemWidth = endpoints.itemWidth;

    final contentWidth = (width - _padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final measured = _measureSections(
      lowWidth: lowWidth,
      highWidth: highWidth,
      itemWidth: itemWidth,
      contentWidth: contentWidth,
      lowCount: lowCount,
      highCount: highCount,
    );

    final solved = solveZoomAware(
      width: width,
      lowSections: measured.low,
      highSections: measured.high,
      lowCount: lowCount,
      highCount: highCount,
      t: t,
      crossAxisSpacing: _crossAxisSpacing,
      mainAxisSpacing: _mainAxisSpacing,
      padding: _padding,
      textDirection: _textDirection,
    );
    final result = solved.result;
    commitZoomFrame(
      result: result,
      contentWidth: contentWidth,
      t: t,
      lowWidth: lowWidth,
      highWidth: highWidth,
      itemWidth: itemWidth,
      lowCount: lowCount,
      highCount: highCount,
      lowRects: solved.lowRects,
      highRects: solved.highRects,
    );

    final anchorId = zoomAnchorId;
    if (_zoomStyle == GridZoomStyle.photos &&
        lowCount != highCount &&
        anchorId != null) {
      maybeFreezePhotosFixedX(
        anchorLowRect: solved.lowRects[anchorId],
        anchorHighRect: solved.highRects[anchorId],
        lowWidth: lowWidth,
        highWidth: highWidth,
        gridWidth: width,
        pair: (lowCount, highCount),
      );
    }

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
        jump: isFirstLayout || (wasZoomActive && !zoomActive),
        zoomActive: zoomActive,
      )
      ..clearNeedsLayout();

    size = constraints.constrain(
      Size(width, isFirstLayout ? result.totalHeight : _animator.height),
    );
    finishGridLayout(zoomActive: zoomActive);
  }

  /// Lays out every child at its role's (and zoom slot's) constraints, reads
  /// back the measured heights, and assembles per-slot section specs (with
  /// collapse and empty-drop extents applied) for the two endpoint solves.
  ///
  /// Untagged items measure at [itemWidth] and feed both slots identically —
  /// the single-mode (resting) path. Slot-tagged crossfade copies measure at
  /// their own endpoint width and feed only their slot, so each endpoint solve
  /// uses heights measured at that endpoint's exact width.
  ({List<GridSectionSpec> low, List<GridSectionSpec> high}) _measureSections({
    required double lowWidth,
    required double highWidth,
    required double itemWidth,
    required double contentWidth,
    required int lowCount,
    required int highCount,
  }) {
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
          child.layout(
            BoxConstraints.tightFor(width: contentWidth),
            parentUsesSize: true,
          );
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
          child.layout(
            BoxConstraints.tightFor(width: measureWidth),
            parentUsesSize: true,
          );
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
          final lowIds = lowItemsBySection[config.id]!
              .map((item) => item.id)
              .toSet();
          final highIds = highItemsBySection[config.id]!
              .map((item) => item.id)
              .toSet();
          if (!setEquals(lowIds, highIds)) return false;
          if (lowIds.length != lowItemsBySection[config.id]!.length) {
            return false;
          }
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
      _animator.setCollapseTarget(
        config.id,
        wantsCollapse ? 1 : 0,
        jump: isFirstLayout,
      );
      final collapse = _animator.collapseOf(config.id).clamp(0.0, 1.0);
      final expansion = 1 - collapse;

      final headerHeight = (headerHeights[config.id] ?? 0) * expansion;
      final footerHeight = (footerHeights[config.id] ?? 0) * expansion;
      final emptyExtent = isEmpty && _isDragging ? config.emptyDropExtent : 0.0;

      lowSections.add(
        GridSectionSpec(
          id: config.id,
          items: lowItems,
          headerHeight: headerHeight,
          footerHeight: footerHeight,
          emptyExtent: emptyExtent,
          leadingCells: _cellOffsets.of(lowCount, config.id),
        ),
      );
      highSections.add(
        GridSectionSpec(
          id: config.id,
          items: highItems,
          headerHeight: headerHeight,
          footerHeight: footerHeight,
          emptyExtent: emptyExtent,
          leadingCells: _cellOffsets.of(highCount, config.id),
        ),
      );
    }

    return (low: lowSections, high: highSections);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_animator.zoomActive) {
      // Scaled copies of non-aspect-preserving items can overhang the lerped
      // total height mid-morph, and the ancestor viewport only pushes its clip
      // when it has visual overflow of its own — a short, unscrolled grid
      // would bleed over trailing UI. The grid owns the clip while a zoom is
      // in flight; at rest the layer tree is unchanged.
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        paintGridContents,
      );
    } else {
      paintGridContents(context, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      hitTestGridChildren(result, position: position);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      applyGridPaintTransform(child, transform);
}
