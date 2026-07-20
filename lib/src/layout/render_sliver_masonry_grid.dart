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

/// What a lazily-materialised child of the sliver grid represents. Together with
/// an id this is the child's stable identity — its element slot — so a child
/// survives reorders, zoom-pair rollovers, and scrolling without being rebuilt.
enum FluidChildKind { header, footer, item, itemOverlay, ghost }

/// The identity of one materialised child: its [kind] plus the id it renders
/// (an item id, or a section id for chrome).
@immutable
class FluidChildKey {
  const FluidChildKey(this.kind, this.id);

  final FluidChildKind kind;
  final Object id;

  @override
  bool operator ==(Object other) =>
      other is FluidChildKey && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'FluidChildKey(${kind.name}, $id)';
}

/// One section's content for the solver: its ordered item ids (with any drag
/// hypothesis already spliced in) and whether it carries chrome.
@immutable
class SliverSectionModel {
  const SliverSectionModel({
    required this.id,
    required this.itemIds,
    required this.hasHeader,
    required this.hasFooter,
    required this.collapseWhenEmpty,
    required this.emptyDropExtent,
  });

  final Object id;
  final List<Object> itemIds;
  final bool hasHeader;
  final bool hasFooter;
  final bool collapseWhenEmpty;
  final double emptyDropExtent;

  @override
  bool operator ==(Object other) =>
      other is SliverSectionModel &&
      other.id == id &&
      listEquals(other.itemIds, itemIds) &&
      other.hasHeader == hasHeader &&
      other.hasFooter == hasFooter &&
      other.collapseWhenEmpty == collapseWhenEmpty &&
      other.emptyDropExtent == emptyDropExtent;

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(itemIds),
    hasHeader,
    hasFooter,
    collapseWhenEmpty,
    emptyDropExtent,
  );
}

class SliverFluidGridChildParentData extends ParentData {
  FluidChildKey? key;
}

/// The lazy sliver counterpart to `MasonryGridBody`: it carries the section
/// content model, the height callback, ghost sizes, and per-key builders, and
/// wires up the custom keyed element and render object.
class SliverMasonryGridBody extends RenderObjectWidget {
  const SliverMasonryGridBody({
    required this.animator,
    required this.cellOffsets,
    required this.sections,
    required this.itemHeightOf,
    required this.ghostSizes,
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.padding,
    required this.textDirection,
    required this.isDragging,
    required this.liftScale,
    required this.zoomStyle,
    required this.zoomLevels,
    required this.dual,
    required this.primarySlot,
    required this.contentRevision,
    required this.pinchEnabled,
    required this.onPinchPointerDown,
    required this.onPinchPointerUp,
    required this.buildHeader,
    required this.buildFooter,
    required this.buildItem,
    required this.buildOverlay,
    required this.buildGhost,
    super.key,
  });

  final GridAnimator animator;

  /// The photos zoom's persistent cell alignment (see [ZoomCellOffsetStore]).
  /// Shared by identity with the coordinator, like [animator].
  final ZoomCellOffsetStore cellOffsets;

  final List<SliverSectionModel> sections;

  /// The natural height of the item with the given id, laid out at a given
  /// column width. When non-null the grid is in **exact** mode: this is the
  /// source of truth that lets the whole grid be solved without building a
  /// single child. When null the grid is in **measured** mode and heights come
  /// from the rendered children instead.
  final double Function(Object id, double itemWidth)? itemHeightOf;

  final Map<Object, Size> ghostSizes;

  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets padding;
  final TextDirection textDirection;
  final bool isDragging;
  final double liftScale;
  final GridZoomStyle zoomStyle;

  /// The allowed zoom levels; the morph endpoints step between adjacent
  /// members. Null means every integer.
  final List<int>? zoomLevels;

  /// Whether the crossfade builds each item twice this frame.
  final bool dual;

  /// Which zoom slot the primary (interactive) item copy renders.
  final ZoomSlot primarySlot;

  /// Bumped by the widget whenever the section order, ghosts, or drag hypothesis
  /// change, so the render object knows to re-solve rather than reuse its cache.
  final int contentRevision;

  final bool pinchEnabled;
  final void Function(PointerDownEvent event) onPinchPointerDown;
  final void Function(PointerEvent event) onPinchPointerUp;

  final Widget? Function(BuildContext context, Object sectionId) buildHeader;
  final Widget? Function(BuildContext context, Object sectionId) buildFooter;
  final Widget Function(BuildContext context, Object itemId) buildItem;
  final Widget Function(BuildContext context, Object itemId) buildOverlay;
  final Widget Function(BuildContext context, Object itemId) buildGhost;

  ZoomSlot get overlaySlot =>
      primarySlot == ZoomSlot.low ? ZoomSlot.high : ZoomSlot.low;

  @override
  SliverFluidGridElement createElement() => SliverFluidGridElement(this);

  @override
  RenderSliverFluidGrid createRenderObject(BuildContext context) =>
      RenderSliverFluidGrid(
          animator: animator,
          cellOffsets: cellOffsets,
          sections: sections,
          itemHeightOf: itemHeightOf,
          ghostSizes: ghostSizes,
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: crossAxisSpacing,
          mainAxisSpacing: mainAxisSpacing,
          padding: padding,
          textDirection: textDirection,
          isDragging: isDragging,
          liftScale: liftScale,
          zoomStyle: zoomStyle,
          zoomLevels: zoomLevels,
          dual: dual,
          primarySlot: primarySlot,
          contentRevision: contentRevision,
        )
        ..pinchEnabled = pinchEnabled
        ..onPinchPointerDown = onPinchPointerDown
        ..onPinchPointerUp = onPinchPointerUp;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverFluidGrid renderObject,
  ) {
    renderObject
      ..pinchEnabled = pinchEnabled
      ..onPinchPointerDown = onPinchPointerDown
      ..onPinchPointerUp = onPinchPointerUp
      ..animator = animator
      ..cellOffsets = cellOffsets
      ..sections = sections
      ..itemHeightOf = itemHeightOf
      ..ghostSizes = ghostSizes
      ..crossAxisCount = crossAxisCount
      ..crossAxisSpacing = crossAxisSpacing
      ..mainAxisSpacing = mainAxisSpacing
      ..padding = padding
      ..textDirection = textDirection
      ..isDragging = isDragging
      ..liftScale = liftScale
      ..zoomStyle = zoomStyle
      ..zoomLevels = zoomLevels
      ..dual = dual
      ..primarySlot = primarySlot
      ..contentRevision = contentRevision;
  }
}

/// The interface the render object uses to ask the element to materialise a set
/// of keyed children during layout.
abstract interface class FluidGridChildManager {
  /// Reconcile the live children to exactly [desired], inflating missing keys,
  /// updating survivors, and deactivating the rest. Only valid during layout.
  void syncChildren(Set<FluidChildKey> desired);
}

/// A [RenderObjectElement] that manages children by [FluidChildKey] in a map
/// rather than by contiguous index, so masonry ordering, per-item zoom overlay
/// copies, and ghosts all coexist. Modeled on `SliverMultiBoxAdaptorElement`,
/// minus the index/contiguity invariants.
class SliverFluidGridElement extends RenderObjectElement
    implements FluidGridChildManager {
  SliverFluidGridElement(SliverMasonryGridBody super.widget);

  @override
  SliverMasonryGridBody get widget => super.widget as SliverMasonryGridBody;

  @override
  RenderSliverFluidGrid get renderObject =>
      super.renderObject as RenderSliverFluidGrid;

  final Map<FluidChildKey, Element> _children = {};

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.childManager = this;
  }

  @override
  void update(SliverMasonryGridBody newWidget) {
    super.update(newWidget);
    renderObject.childManager = this;
    // performRebuild does the reconcile; the framework runs it inside a build
    // scope, so it must not open a nested one.
    performRebuild();
  }

  @override
  void performRebuild() {
    super.performRebuild();
    // Rebuild every live child against the new builders. No buildScope here —
    // performRebuild is already invoked within one.
    for (final key in _children.keys.toList()) {
      final built = updateChild(_children[key], _build(key), key);
      if (built != null) {
        _children[key] = built;
      } else {
        _children.remove(key);
      }
    }
    renderObject.markNeedsLayout();
  }

  @override
  void syncChildren(Set<FluidChildKey> desired) {
    owner!.buildScope(this, () {
      for (final key in _children.keys.toList()) {
        if (desired.contains(key)) continue;
        updateChild(_children[key], null, key);
        _children.remove(key);
      }
      for (final key in desired) {
        final built = updateChild(_children[key], _build(key), key);
        if (built != null) {
          _children[key] = built;
        } else {
          _children.remove(key);
        }
      }
    });
  }

  Widget? _build(FluidChildKey key) {
    switch (key.kind) {
      case FluidChildKind.header:
        return widget.buildHeader(this, key.id);
      case FluidChildKind.footer:
        return widget.buildFooter(this, key.id);
      case FluidChildKind.item:
        return widget.buildItem(this, key.id);
      case FluidChildKind.itemOverlay:
        return widget.buildOverlay(this, key.id);
      case FluidChildKind.ghost:
        return widget.buildGhost(this, key.id);
    }
  }

  @override
  void insertRenderObjectChild(RenderBox child, FluidChildKey slot) =>
      renderObject.insertChild(child, slot);

  @override
  void moveRenderObjectChild(
    RenderBox child,
    FluidChildKey oldSlot,
    FluidChildKey newSlot,
  ) => renderObject.moveChild(child, from: oldSlot, to: newSlot);

  @override
  void removeRenderObjectChild(RenderBox child, FluidChildKey slot) =>
      renderObject.removeChild(slot);

  @override
  void visitChildren(ElementVisitor visitor) =>
      _children.values.toList().forEach(visitor);

  @override
  void forgetChild(Element child) {
    _children.removeWhere((key, value) => value == child);
    super.forgetChild(child);
  }
}

/// Measured item heights for one column count (measured mode). Keyed by the
/// column width they were taken at, so a width change discards them. Keeps a
/// running sum so [estimate] is O(1).
class _MeasuredHeightStore {
  _MeasuredHeightStore(this.widthBasis);

  final double widthBasis;
  final Map<Object, double> heights = {};
  double _sum = 0;

  void record(Object id, double height) {
    final previous = heights[id];
    if (previous != null) _sum -= previous;
    heights[id] = height;
    _sum += height;
  }

  /// Drop ids that are no longer in the data (e.g. after a removal), keeping the
  /// running sum consistent.
  void retain(bool Function(Object id) keep) {
    heights.removeWhere((id, height) {
      if (keep(id)) return false;
      _sum -= height;
      return true;
    });
  }

  /// The height to assume for an item not yet measured: the running average of
  /// what has been measured, or [prior] before anything has.
  double estimate(double prior) =>
      heights.isEmpty ? prior : _sum / heights.length;
}

/// A fully lazy masonry sliver. The solver runs over every item from either a
/// height callback (exact mode — scroll extent and positions are exact) or the
/// rendered children's measured heights (measured mode — approximate until
/// content is visited), but only children whose animated rect intersects the
/// cache window are built, laid out, and painted.
class RenderSliverFluidGrid extends RenderSliver
    with MasonryRenderCore
    implements GridHost, FluidGridChildManager {
  RenderSliverFluidGrid({
    required GridAnimator animator,
    required ZoomCellOffsetStore cellOffsets,
    required List<SliverSectionModel> sections,
    required double Function(Object id, double itemWidth)? itemHeightOf,
    required Map<Object, Size> ghostSizes,
    required int crossAxisCount,
    required double crossAxisSpacing,
    required double mainAxisSpacing,
    required EdgeInsets padding,
    required TextDirection textDirection,
    required bool isDragging,
    required double liftScale,
    required GridZoomStyle zoomStyle,
    required List<int>? zoomLevels,
    required bool dual,
    required ZoomSlot primarySlot,
    required int contentRevision,
  }) : _animator = animator,
       _cellOffsets = cellOffsets,
       _sections = sections,
       _itemHeightOf = itemHeightOf,
       _ghostSizes = ghostSizes,
       _crossAxisCount = crossAxisCount,
       _crossAxisSpacing = crossAxisSpacing,
       _mainAxisSpacing = mainAxisSpacing,
       _padding = padding,
       _textDirection = textDirection,
       _isDragging = isDragging,
       _liftScale = liftScale,
       _zoomStyle = zoomStyle,
       _zoomLevels = zoomLevels,
       _dual = dual,
       _primarySlot = primarySlot,
       _contentRevision = contentRevision;

  late FluidGridChildManager childManager;

  final Map<FluidChildKey, RenderBox> _children = {};

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

  List<SliverSectionModel> _sections;
  set sections(List<SliverSectionModel> value) {
    if (listEquals(_sections, value)) return;
    _sections = value;
    _heightCache.clear();
    // A reorder or a data change must NOT throw away measured heights — only
    // drop ids that left the data.
    final liveIds = {
      for (final section in _sections)
        for (final id in section.itemIds) id,
    };
    for (final store in _measuredStores.values) {
      store.retain(liveIds.contains);
    }
    markNeedsLayout();
  }

  double Function(Object id, double itemWidth)? _itemHeightOf;
  set itemHeightOf(double Function(Object id, double itemWidth)? value) {
    if (_itemHeightOf == value) return;
    final modeFlipped = (_itemHeightOf == null) != (value == null);
    _itemHeightOf = value;
    _heightCache.clear();
    if (modeFlipped) _measuredStores.clear();
    markNeedsLayout();
  }

  /// True when no height callback is supplied: heights are measured from the
  /// rendered children rather than computed up front.
  bool get _measuredMode => _itemHeightOf == null;

  Map<Object, Size> _ghostSizes;
  set ghostSizes(Map<Object, Size> value) {
    if (mapEquals(_ghostSizes, value)) return;
    _ghostSizes = value;
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
    // Column width changes → measured heights (taken at the old width) are stale.
    _heightCache.clear();
    _measuredStores.clear();
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
    // Column width changes → measured heights (taken at the old width) are stale.
    _heightCache.clear();
    _measuredStores.clear();
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

  GridZoomStyle _zoomStyle;
  @override
  GridZoomStyle get zoomStyle => _zoomStyle;
  set zoomStyle(GridZoomStyle value) {
    if (_zoomStyle == value) return;
    _zoomStyle = value;
    // Under GridZoomStyle.photos the style feeds the materialisation window
    // (canvas-transformed visibility), which is a layout concern. Style changes
    // are rare, so the extra relayout costs nothing in practice.
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

  bool _dual;
  set dual(bool value) {
    if (_dual == value) return;
    _dual = value;
    markNeedsLayout();
  }

  ZoomSlot _primarySlot;
  set primarySlot(ZoomSlot value) {
    if (_primarySlot == value) return;
    _primarySlot = value;
    markNeedsLayout();
  }

  /// When true the sliver hit-tests itself (including on gaps and padding), so a
  /// two-finger pinch anywhere over the grid reaches the forwarded recognizer.
  bool pinchEnabled = false;

  /// Pointer-down / up forwarding for the widget-owned pinch recognizer. A
  /// sliver cannot be wrapped in a RawGestureDetector, so the render object
  /// routes pointers to the recognizer itself.
  void Function(PointerDownEvent event)? onPinchPointerDown;
  void Function(PointerEvent event)? onPinchPointerUp;

  int _contentRevision;
  set contentRevision(int value) {
    if (_contentRevision == value) return;
    _contentRevision = value;
    markNeedsLayout();
  }

  ZoomSlot get _overlaySlot =>
      _primarySlot == ZoomSlot.low ? ZoomSlot.high : ZoomSlot.low;

  // Exact mode: cached per-(column count) callback height maps for the current
  // width basis. Cleared whenever the content, callback, width, or spacing
  // change.
  final Map<int, Map<Object, double>> _heightCache = {};

  // Measured mode: real rendered heights per column count, persisted across
  // layouts (a reorder must not throw them away). Pruned, not cleared, when the
  // data changes.
  final Map<int, _MeasuredHeightStore> _measuredStores = {};

  // Measured mode: exactly the height map each column count's last solve
  // consumed, so `itemHeightsForColumns` (which the coordinator's focal-pinning
  // predictor reads) reproduces the solve rather than a fresher estimate.
  Map<int, Map<Object, double>> _lastSolveHeights = const {};

  /// Heights within this tolerance of the value the solve used don't trigger a
  /// re-solve pass.
  static const double _measureEpsilon = 0.5;

  /// Hard cap on measure→re-solve passes per layout, so a non-deterministic
  /// child (e.g. an image resolving mid-layout) can't spin forever.
  static const int _maxMeasurePasses = 8;

  /// Measure→re-solve passes the last layout took, for tests.
  @visibleForTesting
  int debugLastMeasurePasses = 0;

  @override
  Offset get childPaintShift => Offset(0, -constraints.scrollOffset);

  @override
  Iterable<RenderBox> get gridChildren => _children.values;

  @override
  GridChildFacts factsOf(RenderBox child) {
    final key = (child.parentData! as SliverFluidGridChildParentData).key!;
    final isOverlay = key.kind == FluidChildKind.itemOverlay;
    final role = switch (key.kind) {
      FluidChildKind.header => GridChildRole.header,
      FluidChildKind.footer => GridChildRole.footer,
      FluidChildKind.ghost => GridChildRole.ghost,
      FluidChildKind.item ||
      FluidChildKind.itemOverlay => GridChildRole.item,
    };
    // A slot is only carried while the crossfade builds dual renditions —
    // exactly the condition the shared geometry gate relies on.
    final slot = !_dual || role != GridChildRole.item
        ? ZoomSlot.none
        : (isOverlay ? _overlaySlot : _primarySlot);
    return (
      id: key.id,
      sectionId: key.id,
      role: role,
      slot: slot,
      isOverlay: isOverlay,
    );
  }

  /// The keys currently materialised, for tests asserting laziness.
  @visibleForTesting
  Iterable<FluidChildKey> get debugMaterialisedKeys => _children.keys;

  /// The anchor state the photos canvases are pinned on, for tests.
  @visibleForTesting
  (Object?, Offset) get debugZoomAnchor => (zoomAnchorId, zoomAnchorFraction);

  // --- Child bookkeeping (manual, since children are keyed not linked) ---

  void _setupParentData(RenderBox child, FluidChildKey key) {
    if (child.parentData is! SliverFluidGridChildParentData) {
      child.parentData = SliverFluidGridChildParentData();
    }
    (child.parentData! as SliverFluidGridChildParentData).key = key;
  }

  void insertChild(RenderBox child, FluidChildKey slot) {
    _setupParentData(child, slot);
    _children[slot] = child;
    adoptChild(child);
  }

  void moveChild(
    RenderBox child, {
    required FluidChildKey from,
    required FluidChildKey to,
  }) {
    if (_children[from] == child) _children.remove(from);
    _children[to] = child;
    (child.parentData! as SliverFluidGridChildParentData).key = to;
  }

  void removeChild(FluidChildKey slot) {
    final child = _children.remove(slot);
    if (child != null) dropChild(child);
  }

  @override
  void syncChildren(Set<FluidChildKey> desired) =>
      childManager.syncChildren(desired);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (final child in _children.values) {
      child.attach(owner);
    }
  }

  @override
  void detach() {
    super.detach();
    for (final child in _children.values) {
      child.detach();
    }
  }

  @override
  void redepthChildren() {
    for (final child in _children.values) {
      redepthChild(child);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    for (final child in _children.values) {
      visitor(child);
    }
  }

  // --- Height callback plumbing ---

  double _columnWidthFor(int count) {
    final contentWidth = (constraints.crossAxisExtent - _padding.horizontal)
        .clamp(0.0, double.infinity);
    if (count <= 0) return 0;
    final available = contentWidth - _crossAxisSpacing * (count - 1);
    return (available / count).clamp(0.0, double.infinity);
  }

  /// The heights the grid currently believes each item has, keyed by id. In
  /// exact mode this is the callback's output (memoized); in measured mode it is
  /// exactly what the last solve consumed (so the coordinator's focal-pinning
  /// predictor reproduces the solve), falling back to measured-or-estimate.
  Map<Object, double> _heightsFor(int count) {
    if (!_measuredMode) {
      return _heightCache.putIfAbsent(count, () {
        final width = _columnWidthFor(count);
        final callback = _itemHeightOf!;
        final map = <Object, double>{};
        for (final section in _sections) {
          for (final id in section.itemIds) {
            map[id] = callback(id, width);
          }
        }
        return map;
      });
    }
    return _lastSolveHeights[count] ?? _measuredOrEstimateMap(count);
  }

  /// Measured mode: each item's measured height if known, else the store's
  /// running-average estimate (or the column width — a square — before anything
  /// has been measured).
  Map<Object, double> _measuredOrEstimateMap(int count) {
    final store = _measuredStores[count];
    final width = _columnWidthFor(count);
    final estimate = store?.estimate(width) ?? width;
    return {
      for (final section in _sections)
        for (final id in section.itemIds) id: store?.heights[id] ?? estimate,
    };
  }

  List<GridSectionSpec> _sectionSpecsFor(
    int count,
    Map<Object, double> heights,
  ) => [
    for (final section in _sections)
      GridSectionSpec(
        id: section.id,
        items: [
          for (final id in section.itemIds)
            GridItemSpec(id: id, height: heights[id] ?? 0),
        ],
        headerHeight:
            (headerHeights[section.id] ?? 0) *
            (1 - _animator.collapseOf(section.id).clamp(0.0, 1.0)),
        footerHeight:
            (footerHeights[section.id] ?? 0) *
            (1 - _animator.collapseOf(section.id).clamp(0.0, 1.0)),
        emptyExtent: section.itemIds.isEmpty && _isDragging
            ? section.emptyDropExtent
            : 0.0,
        leadingCells: _cellOffsets.of(count, section.id),
      ),
  ];

  // --- Layout ---

  double _lastCrossAxisExtent = -1;

  @override
  void performLayout() {
    assert(
      constraints.axis == Axis.vertical,
      'SliverFluidGrid only supports a vertical CustomScrollView',
    );
    assert(
      constraints.growthDirection == GrowthDirection.forward,
      'SliverFluidGrid only supports forward growth',
    );

    if (constraints.crossAxisExtent != _lastCrossAxisExtent) {
      // Column widths change → both the callback memo and measured heights
      // (taken at the old width) are stale.
      _heightCache.clear();
      _measuredStores.clear();
      _lastCrossAxisExtent = constraints.crossAxisExtent;
    }

    final width = constraints.crossAxisExtent;

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

    // 1. Materialise + measure ALL chrome so header/footer extents feed the
    // solve. Sections are few, so this is cheap; a header far below the viewport
    // is still built (there is no other way to measure it).
    final chromeKeys = <FluidChildKey>{
      for (final section in _sections) ...[
        if (section.hasHeader) FluidChildKey(FluidChildKind.header, section.id),
        if (section.hasFooter) FluidChildKey(FluidChildKind.footer, section.id),
      ],
    };
    // Keep item/ghost children from last frame while we sync chrome, so they are
    // not churned; the real item sync happens after the solve.
    invokeLayoutCallback<SliverConstraints>((_) {
      childManager.syncChildren({..._children.keys, ...chromeKeys});
    });
    headerHeights.clear();
    footerHeights.clear();
    final contentWidth = (width - _padding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    for (final section in _sections) {
      final headerKey = FluidChildKey(FluidChildKind.header, section.id);
      final footerKey = FluidChildKey(FluidChildKind.footer, section.id);
      final header = _children[headerKey];
      if (header != null) {
        header.layout(
          BoxConstraints.tightFor(width: contentWidth),
          parentUsesSize: true,
        );
        headerHeights[section.id] = header.size.height;
      }
      final footer = _children[footerKey];
      if (footer != null) {
        footer.layout(
          BoxConstraints.tightFor(width: contentWidth),
          parentUsesSize: true,
        );
        footerHeights[section.id] = footer.size.height;
      }
    }

    // Collapse targets (drives header/footer shrink for empty sections).
    for (final section in _sections) {
      final wantsCollapse =
          section.itemIds.isEmpty && section.collapseWhenEmpty && !_isDragging;
      _animator.setCollapseTarget(
        section.id,
        wantsCollapse ? 1 : 0,
        jump: isFirstLayout,
      );
    }

    // 2. Solve → window → materialise → measure, until stable. In exact mode
    // the height maps are the callback's and never change, so the loop runs
    // once with the same tight constraints as before. In measured mode the
    // first solve uses estimates; measuring the materialised children can shift
    // the window, so it re-solves until measurements stop changing.
    final frozenEstimate = <int, double>{};
    if (_measuredMode) {
      // Drop stores whose width basis no longer matches (defensive; setters
      // already clear on width-affecting changes).
      _measuredStores.removeWhere(
        (count, store) =>
            (store.widthBasis - _columnWidthFor(count)).abs() > 0.01,
      );
      frozenEstimate[lowCount] =
          _measuredStores[lowCount]?.estimate(endpoints.lowWidth) ??
          endpoints.lowWidth;
      frozenEstimate[highCount] =
          _measuredStores[highCount]?.estimate(endpoints.highWidth) ??
          endpoints.highWidth;
    }

    // The height map to solve column [count] with this pass. Recorded verbatim
    // into solveHeightsUsed so re-measured children compare against exactly what
    // the solve consumed, and so the coordinator's predictor can reproduce it.
    Map<Object, double> heightsForSolve(int count) {
      if (!_measuredMode) return _heightsFor(count);
      final store = _measuredStores[count];
      final estimate = frozenEstimate[count]!;
      return {
        for (final section in _sections)
          for (final id in section.itemIds) id: store?.heights[id] ?? estimate,
      };
    }

    late ({
      GridLayoutResult result,
      Map<Object, Rect> lowRects,
      Map<Object, Rect> highRects,
    })
    solved;
    late Set<FluidChildKey> desired;
    var solveHeightsUsed = <int, Map<Object, double>>{};
    var syncedThisPass = <FluidChildKey>{..._children.keys};
    var passes = 0;
    final maxPasses = _measuredMode ? _maxMeasurePasses : 1;

    while (true) {
      passes++;
      final lowHeights = heightsForSolve(lowCount);
      final highHeights = lowCount == highCount
          ? lowHeights
          : heightsForSolve(highCount);
      solveHeightsUsed = {
        lowCount: lowHeights,
        if (highCount != lowCount) highCount: highHeights,
      };

      solved = solveZoomAware(
        width: width,
        lowSections: _sectionSpecsFor(lowCount, lowHeights),
        highSections: _sectionSpecsFor(highCount, highHeights),
        lowCount: lowCount,
        highCount: highCount,
        t: t,
        crossAxisSpacing: _crossAxisSpacing,
        mainAxisSpacing: _mainAxisSpacing,
        padding: _padding,
        textDirection: _textDirection,
      );

      // Under photos, an item's PAINTED rect is its endpoint rect mapped
      // through the rendition's rigid canvas transform; the materialisation
      // window must test that, or a compressing canvas would show holes at the
      // screen edges. Both canvases are computable here, before any child
      // exists, from the solve results plus the anchor state.
      ({Offset anchorK, Offset anchorStar, double scale})? lowCanvas;
      ({Offset anchorK, Offset anchorStar, double scale})? highCanvas;
      if (_zoomStyle == GridZoomStyle.photos && _dual) {
        final anchorId = zoomAnchorId;
        if (anchorId != null) {
          maybeFreezePhotosFixedX(
            anchorLowRect: solved.lowRects[anchorId],
            anchorHighRect: solved.highRects[anchorId],
            lowWidth: endpoints.lowWidth,
            highWidth: endpoints.highWidth,
            gridWidth: width,
            pair: (lowCount, highCount),
          );
          // Built over the pass-locals: the crossfade fields are not committed
          // until after the measure loop, and after the final pass these
          // coincide with the canvases paint uses.
          lowCanvas = photosCanvasTransform(
            anchorEndpointRect: solved.lowRects[anchorId],
            anchorLerpedRect: solved.result.itemRects[anchorId],
            anchorFraction: zoomAnchorFraction,
            endpointWidth: endpoints.lowWidth,
            itemWidth: endpoints.itemWidth,
            focalX: photosFocalX,
          );
          highCanvas = photosCanvasTransform(
            anchorEndpointRect: solved.highRects[anchorId],
            anchorLerpedRect: solved.result.itemRects[anchorId],
            anchorFraction: zoomAnchorFraction,
            endpointWidth: endpoints.highWidth,
            itemWidth: endpoints.itemWidth,
            focalX: photosFocalX,
          );
        }
      }

      desired = _desiredKeys(
        solved.result,
        chromeKeys,
        lowRects: solved.lowRects,
        highRects: solved.highRects,
        lowCanvas: lowCanvas,
        highCanvas: highCanvas,
      );

      // Sync to the monotone union while looping (never deactivate mid-loop,
      // else a key would be inflated then destroyed then re-inflated).
      final toSync = _measuredMode ? {...syncedThisPass, ...desired} : desired;
      if (!setEquals(toSync, _children.keys.toSet())) {
        invokeLayoutCallback<SliverConstraints>((_) {
          childManager.syncChildren(toSync);
        });
        syncedThisPass = toSync;
      }

      final changed = _layoutGridChildren(
        endpoints,
        lowCount: lowCount,
        highCount: highCount,
        solveHeightsUsed: solveHeightsUsed,
      );

      if (!_measuredMode || !changed || passes >= maxPasses) break;
    }
    debugLastMeasurePasses = passes;
    final result = solved.result;

    // Commit the layout results ONCE, capturing the previous layout for spring
    // seeding before overwriting it.
    final previousLayout = lastLayout;
    commitZoomFrame(
      result: result,
      contentWidth: contentWidth,
      t: t,
      lowWidth: endpoints.lowWidth,
      highWidth: endpoints.highWidth,
      itemWidth: endpoints.itemWidth,
      lowCount: lowCount,
      highCount: highCount,
      lowRects: solved.lowRects,
      highRects: solved.highRects,
    );
    _lastSolveHeights = solveHeightsUsed;

    // Prune any loop overshoot: keys synced in an early pass whose rects left
    // the final window. Their children stay laid out; only the extras go.
    if (_measuredMode && !setEquals(syncedThisPass, desired)) {
      invokeLayoutCallback<SliverConstraints>((_) {
        childManager.syncChildren(desired);
      });
    }

    final materialisedItemIds = <Object>{};
    for (final key in desired) {
      if (key.kind == FluidChildKind.item) materialisedItemIds.add(key.id);
    }

    // Seed springs for existing items that scrolled back into view, so they
    // slide from their previous position rather than fade in as new arrivals.
    for (final id in materialisedItemIds) {
      if (_animator.offsetOf(id) != null) continue;
      final prevRect = previousLayout?.itemRects[id];
      if (prevRect != null) _animator.ensureItem(id, prevRect.topLeft);
    }

    // Push targets into the springs (windowed) and prune the rest.
    final windowedRects = <Object, Rect>{
      for (final id in materialisedItemIds)
        if (result.itemRects[id] != null) id: result.itemRects[id]!,
    };
    final zoomActive = _animator.zoomActive;
    _animator
      ..syncTargets(
        rects: windowedRects,
        totalHeight: result.totalHeight,
        jump: isFirstLayout || (wasZoomActive && !zoomActive),
        zoomActive: zoomActive,
      )
      ..pruneItems(materialisedItemIds.contains)
      ..clearNeedsLayout();

    // Emit sliver geometry. Scroll extent tracks the animated height (parity
    // with the box's animated size); it is frame-exact during a zoom because
    // syncTargets jumps the height.
    final scrollExtent = isFirstLayout ? result.totalHeight : _animator.height;
    final paintExtent = calculatePaintOffset(
      constraints,
      from: 0,
      to: scrollExtent,
    );
    final cacheExtent = calculateCacheOffset(
      constraints,
      from: 0,
      to: scrollExtent,
    );
    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: scrollExtent,
      hasVisualOverflow: true,
    );

    finishGridLayout(zoomActive: zoomActive);
  }

  /// Lays out every materialised item/overlay/ghost child at its tight size.
  ///
  /// Exact mode uses the callback height (no measurement); measured mode lays
  /// the child out with `parentUsesSize` to read its real height, records it
  /// into the per-count store, and returns whether any fresh height differed
  /// from what the solve consumed — the signal to re-solve.
  bool _layoutGridChildren(
    ({
      int lowCount,
      int highCount,
      double t,
      double lowWidth,
      double highWidth,
      double itemWidth,
    })
    endpoints, {
    required int lowCount,
    required int highCount,
    required Map<int, Map<Object, double>> solveHeightsUsed,
  }) {
    var changed = false;
    for (final entry in _children.entries) {
      final key = entry.key;
      final child = entry.value;
      switch (key.kind) {
        case FluidChildKind.header:
        case FluidChildKind.footer:
          break; // already laid out
        case FluidChildKind.item:
        case FluidChildKind.itemOverlay:
          final slot = key.kind == FluidChildKind.itemOverlay
              ? _overlaySlot
              : _primarySlot;
          final slotCount = slot == ZoomSlot.high ? highCount : lowCount;
          final slotWidth = switch (slot) {
            ZoomSlot.low => endpoints.lowWidth,
            ZoomSlot.high => endpoints.highWidth,
            ZoomSlot.none => endpoints.itemWidth,
          };
          if (!_measuredMode) {
            final height = solveHeightsUsed[slotCount]?[key.id] ?? 0;
            child.layout(BoxConstraints.tight(Size(slotWidth, height)));
          } else {
            child.layout(
              BoxConstraints.tightFor(width: slotWidth),
              parentUsesSize: true,
            );
            final measured = child.size.height;
            final used = solveHeightsUsed[slotCount]?[key.id];
            if (used == null || (measured - used).abs() > _measureEpsilon) {
              changed = true;
            }
            (_measuredStores[slotCount] ??= _MeasuredHeightStore(
              slotWidth,
            )).record(key.id, measured);
          }
        case FluidChildKind.ghost:
          final ghostSize = _ghostSizes[key.id] ?? Size(endpoints.itemWidth, 0);
          child.layout(BoxConstraints.tight(ghostSize));
      }
    }
    return changed;
  }

  Set<FluidChildKey> _desiredKeys(
    GridLayoutResult result,
    Set<FluidChildKey> chromeKeys, {
    required Map<Object, Rect> lowRects,
    required Map<Object, Rect> highRects,
    ({Offset anchorK, Offset anchorStar, double scale})? lowCanvas,
    ({Offset anchorK, Offset anchorStar, double scale})? highCanvas,
  }) {
    final winTop = constraints.scrollOffset + constraints.cacheOrigin;
    final winBottom = winTop + constraints.remainingCacheExtent;
    bool intersects(Rect? rect) =>
        rect != null && rect.top < winBottom && rect.bottom > winTop;

    final desired = <FluidChildKey>{...chromeKeys};
    final draggedId = _animator.draggedId;

    for (final section in _sections) {
      for (final id in section.itemIds) {
        final target = result.itemRects[id];
        // Where each rendition actually paints: under photos the endpoint rect
        // rides its rigid canvas transform; otherwise it is the endpoint rect
        // itself (over-materialising is safe, under-materialising leaves holes).
        final lowRect = lowRects[id];
        final highRect = highRects[id];
        final lowPainted = lowRect == null
            ? null
            : (lowCanvas == null
                  ? lowRect
                  : mapRectByCanvas(lowCanvas, lowRect));
        final highPainted = highRect == null
            ? null
            : (highCanvas == null
                  ? highRect
                  : mapRectByCanvas(highCanvas, highRect));
        final animatedOffset = _animator.offsetOf(id);
        final animatedRect = animatedOffset == null || target == null
            ? null
            : animatedOffset & target.size;

        final visible =
            id == draggedId ||
            intersects(target) ||
            intersects(lowPainted) ||
            intersects(highPainted) ||
            intersects(animatedRect);
        if (!visible) continue;

        desired.add(FluidChildKey(FluidChildKind.item, id));
        if (_dual) desired.add(FluidChildKey(FluidChildKind.itemOverlay, id));
      }
    }

    // Ghosts that are still within the window.
    for (final entry in _animator.ghostRects.entries) {
      if (intersects(entry.value)) {
        desired.add(FluidChildKey(FluidChildKind.ghost, entry.key));
      }
    }

    return desired;
  }

  // --- Paint ---

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_children.isEmpty) return;
    if (_animator.zoomActive) {
      // Scaled morph copies can overhang; the viewport clip only guards its own
      // edge, so the grid clips to its paint extent while a zoom is in flight.
      final clip =
          offset & Size(constraints.crossAxisExtent, geometry!.paintExtent);
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & clip.size,
        (ctx, o) => paintGridContents(ctx, offset),
      );
    } else {
      paintGridContents(context, offset);
    }
  }

  // --- Hit test ---

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    // Convert from sliver hit coordinates to grid-local layout coordinates.
    final position = Offset(
      crossAxisPosition,
      mainAxisPosition + constraints.scrollOffset,
    );
    return hitTestGridChildren(
      BoxHitTestResult.wrap(result),
      position: position,
    );
  }

  @override
  bool hitTestSelf({
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) => pinchEnabled;

  @override
  void handleEvent(PointerEvent event, SliverHitTestEntry entry) {
    if (event is PointerDownEvent) {
      onPinchPointerDown?.call(event);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      onPinchPointerUp?.call(event);
    }
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      effectiveGeometryOfChild(child).offset.dy - constraints.scrollOffset;

  @override
  double childCrossAxisPosition(RenderBox child) =>
      effectiveGeometryOfChild(child).offset.dx;

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) =>
      applyGridPaintTransform(child as RenderBox, transform);

  // --- GridHost ---

  @override
  Size? itemSizeOf(Object id) {
    // Prefer the last solved rect: it holds the item's real size even after it
    // has left the data (needed to freeze a departing ghost), where neither the
    // callback nor a measurement can answer for it.
    final rect = lastLayout?.itemRects[id];
    if (rect != null) return rect.size;
    final width = _columnWidthFor(_crossAxisCount);
    final height = _heightsFor(_crossAxisCount)[id] ?? 0;
    return height > 0 ? Size(width, height) : null;
  }

  @override
  Map<Object, double> itemHeights() => Map.of(_heightsFor(_crossAxisCount));

  @override
  Map<Object, double>? itemHeightsForColumns(int count) => _heightsFor(count);

  @override
  Map<Object, double> nearestItemHeightsForColumns(int count) =>
      _heightsFor(count);

  @override
  double get gridWidth =>
      hasSize ? constraints.crossAxisExtent : lastContentWidth;

  bool get hasSize => geometry != null;

  /// Sliver-paint-local point to global. Unlike RenderBox a sliver has no
  /// built-in global/local conversion, so go through the paint transform.
  Offset _sliverLocalToGlobal(Offset point) =>
      MatrixUtils.transformPoint(getTransformTo(null), point);

  Offset _sliverGlobalToLocal(Offset point) {
    final transform = getTransformTo(null);
    if (transform.invert() == 0) return Offset.zero;
    return MatrixUtils.transformPoint(transform, point);
  }

  @override
  Offset globalToGridLocal(Offset global) {
    final local = _sliverGlobalToLocal(global);
    return Offset(local.dx, local.dy + constraints.scrollOffset);
  }

  @override
  Offset gridLocalToGlobal(Offset local) => _sliverLocalToGlobal(
    Offset(local.dx, local.dy - constraints.scrollOffset),
  );
}
