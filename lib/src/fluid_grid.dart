import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/drag/drag_session.dart';
import 'package:fluid_grid/src/drag/insertion_resolver.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:fluid_grid/src/model/grid_reorder_result.dart';
import 'package:fluid_grid/src/model/grid_section.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:fluid_grid/src/model/grid_zoom_config.dart';
import 'package:fluid_grid/src/zoom/zoom_math.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget shown for an item while it is held by the pointer.
typedef LiftedItemBuilder<T> = Widget Function(BuildContext context, T item, Widget child);

/// Matches `SliverReorderableList`'s autoscroll speed.
const double _kDefaultAutoScrollVelocityScalar = 50;

/// A masonry grid whose items animate implicitly and can be dragged to reorder,
/// including from one section into another.
///
/// The grid is not lazy: every item is laid out on every pass. That keeps the
/// geometry exact — heights are measured rather than estimated — at the cost of
/// scaling. It is intended for collections in the tens, not thousands.
///
/// The widget is uncontrolled: dropping an item reports the new ordering
/// through [onReorderFinished] and expects the caller to feed that ordering
/// back in as [sections]. Until the caller does, the drop position is held.
class FluidGrid<T> extends StatefulWidget {
  const FluidGrid({
    required this.sections,
    required this.idOf,
    required this.itemBuilder,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.padding = EdgeInsets.zero,
    this.springs = const GridSprings(),
    this.reorderEnabled = true,
    this.dragStartDelay = kLongPressTimeout,
    this.liftScale = 1.03,
    this.autoScrollVelocityScalar = _kDefaultAutoScrollVelocityScalar,
    this.zoomConfig,
    this.liftedBuilder,
    this.onReorderStarted,
    this.onReorderFinished,
    this.onReorderCanceled,
    this.onCrossAxisCountChanged,
    super.key,
  }) : assert(crossAxisCount > 0, 'crossAxisCount must be positive');

  final List<GridSection<T>> sections;

  /// Stable identity for an item. Must be unique across every section.
  final Object Function(T item) idOf;

  final Widget Function(BuildContext context, T item) itemBuilder;

  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsetsGeometry padding;
  final GridSprings springs;

  final bool reorderEnabled;
  final Duration dragStartDelay;

  /// How much the held item grows while lifted.
  final double liftScale;

  /// Speed of the autoscroll when the held item nears a viewport edge.
  final double autoScrollVelocityScalar;

  /// Enables pinch-to-zoom column switching. Null (the default) disables it and
  /// leaves the grid at [crossAxisCount].
  final GridZoomConfig? zoomConfig;

  /// Decorates the held item, e.g. with a shadow.
  final LiftedItemBuilder<T>? liftedBuilder;

  final void Function(T item)? onReorderStarted;
  final void Function(GridReorderResult<T> result)? onReorderFinished;
  final void Function(T item)? onReorderCanceled;

  /// Fired when a pinch settles on a new column count. Like reorder, the widget
  /// is uncontrolled: feed the reported count back in as [crossAxisCount].
  final ValueChanged<int>? onCrossAxisCountChanged;

  @override
  State<FluidGrid<T>> createState() => _FluidGridState<T>();
}

class _Ghost<T> {
  const _Ghost({required this.item, required this.size});

  final T item;
  final Size size;
}

class _FluidGridState<T> extends State<FluidGrid<T>> with SingleTickerProviderStateMixin {
  final GlobalKey _bodyKey = GlobalKey();

  late final GridAnimator _animator = GridAnimator(
    springs: widget.springs,
    initialZoomLevel: widget.crossAxisCount.toDouble(),
  );
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  DragSession<T>? _drag;
  EdgeDraggingAutoScroller? _autoScroller;
  ScrollableState? _scrollable;

  /// The column count resolved by a pinch but not yet echoed back through
  /// [FluidGrid.crossAxisCount]. Held so the round-trip is a
  /// no-op, exactly like the reorder optimistic update.
  int? _pendingCount;

  /// The committed count the layout is settling toward: the pending pinch
  /// result if there is one, otherwise the widget's own count.
  int get _effectiveCrossAxisCount => _pendingCount ?? widget.crossAxisCount;

  /// The pinch in flight, if any.
  _PinchSession? _pinch;

  /// The frozen focal y (global) the scroll pinning keeps targeting while the
  /// zoom settles after the fingers lift. The anchor item and fraction are
  /// read live from the render box each tick, so a mid-settle re-anchor (the
  /// anchor item left the data) keeps the pinning seamless.
  double? _settleFocalY;

  /// Pointers currently down on the grid. A drag must not start once a second
  /// finger lands, even if the scale recognizer has not yet claimed the arena.
  int _activePointers = 0;

  /// What the last build emitted for the crossfade, so [_syncZoomBuild] can
  /// tell when the child list must change shape.
  ({bool dual, ZoomSlot primarySlot}) _builtZoom = (dual: false, primarySlot: ZoomSlot.none);

  /// What the child list should look like right now.
  ///
  /// During a crossfade every item is emitted twice; the primary copy sits on
  /// the committed-count side of the (floor, ceil) pair so its element — and
  /// the user state inside it — survives the release commit.
  ({bool dual, ZoomSlot primarySlot}) _expectedZoomBuild() {
    final dual = _animator.zoomActive && (widget.zoomConfig?.crossfade ?? false);
    if (!dual) return (dual: false, primarySlot: ZoomSlot.none);
    final zoom = _animator.zoomLevel.value;
    final low = zoom.floor() < 1 ? 1 : zoom.floor();
    return (dual: true, primarySlot: _effectiveCrossAxisCount > low ? ZoomSlot.high : ZoomSlot.low);
  }

  /// Rebuilds when the crossfade shape drifted from what the last build
  /// emitted: session start/end, the release settle finishing, or the zoom
  /// crossing the committed count. Ordinary pair rollovers change nothing here
  /// — the render object just re-measures the copies at their new widths.
  void _syncZoomBuild() {
    if (!mounted) return;
    if (_expectedZoomBuild() != _builtZoom) setState(() {});
  }

  /// Items that left the data but are still fading out.
  final Map<Object, _Ghost<T>> _ghosts = {};

  /// The item behind each live id, refreshed from the incoming sections.
  final Map<Object, T> _itemsById = {};

  RenderMasonryGrid? get _renderBox => _bodyKey.currentContext?.findRenderObject() as RenderMasonryGrid?;

  @override
  void initState() {
    super.initState();
    assert(
      widget.zoomConfig == null || (widget.crossAxisCount >= widget.zoomConfig!.minCrossAxisCount && widget.crossAxisCount <= widget.zoomConfig!.maxCrossAxisCount),
      'crossAxisCount must fall within the zoom range',
    );
    // Eagerly, so a grid that never animates still has a ticker to dispose
    // rather than creating one during teardown.
    _ticker = createTicker(_onTick);
    _indexItems();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable != _scrollable) {
      _scrollable = scrollable;
      _autoScroller = scrollable == null
          ? null
          : EdgeDraggingAutoScroller(
              scrollable,
              onScrollViewScrolled: _onScrollViewScrolled,
              velocityScalar: widget.autoScrollVelocityScalar,
            );
    }
  }

  @override
  void didUpdateWidget(covariant FluidGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animator.springs = widget.springs;
    if (widget.crossAxisCount != oldWidget.crossAxisCount) {
      _onCrossAxisCountUpdated();
    }
    _reconcile();
  }

  /// Reconciles an incoming [FluidGrid.crossAxisCount] with the
  /// pending pinch result.
  void _onCrossAxisCountUpdated() {
    if (_pendingCount == widget.crossAxisCount) {
      // Our own pinch result echoed back; the layout is already there.
      _pendingCount = null;
      return;
    }

    // An external change always wins. Morph to it when zoom is enabled (so the
    // change animates), or jump when it is not (preserving the plain behavior).
    // A programmatic morph needs no anchor: paint follows each item's lerped
    // rect, and only finger pinches pin the scroll.
    _pendingCount = null;
    if (widget.zoomConfig != null) {
      _animator.zoomLevel.retarget(widget.crossAxisCount.toDouble(), widget.springs.zoomSettle);
      _startTicker();
    } else {
      _animator.zoomLevel.jumpTo(widget.crossAxisCount.toDouble());
      _renderBox?.markNeedsLayout();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // --- Data reconciliation ---

  void _indexItems() {
    _itemsById
      ..clear()
      ..addEntries([
        for (final section in widget.sections)
          for (final item in section.items) MapEntry(widget.idOf(item), item),
      ]);
  }

  /// Diff by identity: survivors spring to their new slots, arrivals fade in,
  /// departures become ghosts pinned at their last rect. A keyed, non-lazy grid
  /// needs no edit-script diff — set arithmetic already names every change.
  void _reconcile() {
    final previous = Map<Object, T>.of(_itemsById);
    _indexItems();

    // An id that comes back before its exit fade finished must stop being a
    // ghost: otherwise the build emits both the ghost and the live tile for it,
    // and the live tile keeps fading out under the stale exiting phase.
    for (final id in _itemsById.keys) {
      if (_ghosts.remove(id) != null) _animator.cancelExit(id);
    }

    final box = _renderBox;
    for (final entry in previous.entries) {
      final id = entry.key;
      if (_itemsById.containsKey(id) || _ghosts.containsKey(id)) continue;

      final size = box?.itemSizes[id];
      final offset = _animator.offsetOf(id);
      if (size == null || offset == null) {
        _animator.remove(id);
        continue;
      }

      _ghosts[id] = _Ghost(item: entry.value, size: size);
      _animator.beginExit(id, offset & size);
    }

    final drag = _drag;
    if (drag != null) {
      if (!_itemsById.containsKey(drag.id)) {
        // The item under the finger disappeared from the data.
        _abortDrag(notify: true);
      } else {
        drag.hypothesis = _clampHypothesis(drag.hypothesis);
      }
    }

    // The scroll anchor left the data mid-morph: hand the anchor to the
    // nearest survivor. The removal reflows the grid this very frame, so the
    // fraction must be derived against the PREDICTED post-change layout —
    // pinning the point currently under the fingers to the survivor's new
    // rect makes the next scroll correction a no-op instead of a jolt.
    if (box != null && _animator.zoomActive) {
      final anchorId = box.zoomAnchorId;
      if (anchorId != null && !_itemsById.containsKey(anchorId)) {
        final anchorRect = box.lastLayout?.itemRects[anchorId];
        Object? nearest;
        var nearestDistance = double.infinity;
        for (final entry in box.lastLayout?.itemRects.entries ?? const Iterable<MapEntry<Object, Rect>>.empty()) {
          if (!_itemsById.containsKey(entry.key)) continue;
          final distance = anchorRect == null ? 0.0 : (entry.value.center - anchorRect.center).distanceSquared;
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearest = entry.key;
          }
        }
        if (nearest == null) {
          box.zoomAnchorId = null;
        } else {
          final focalGlobalY = _pinch?.lastFocalGlobalY ?? _settleFocalY;
          final predicted = focalGlobalY == null ? null : _predictLayout(box, _animator.zoomLevel.value)?.itemRects[nearest];
          if (predicted != null && predicted.height != 0) {
            final focalLocalY = box.globalToLocal(Offset(0, focalGlobalY!)).dy;
            box
              ..zoomAnchorId = nearest
              ..zoomAnchorFraction = Offset(0, (focalLocalY - predicted.top) / predicted.height);
          } else {
            // No pinning in flight (nothing to keep still): a plain hand-off
            // preserving the current screen y is enough.
            box.reanchor(nearest);
          }
        }
      }
    }

    _startTicker();
  }

  /// Keeps the drag hypothesis valid against the incoming sections: its slot
  /// may exceed a section that shrank under it, or its whole section may have
  /// disappeared. In the latter case it falls back to the end of the item's
  /// origin section (or the first section), so the lifted item is never
  /// stranded pointing at a section that no longer exists.
  InsertionCandidate _clampHypothesis(InsertionCandidate hypothesis) {
    for (final section in widget.sections) {
      if (section.id != hypothesis.sectionId) continue;
      final limit = section.items.where((item) => widget.idOf(item) != _drag?.id).length;
      if (hypothesis.index <= limit) return hypothesis;
      return InsertionCandidate(sectionId: hypothesis.sectionId, index: limit);
    }

    // The hypothesis section is gone; re-home to the origin section if it
    // survives, else the first remaining section.
    final fallback = widget.sections.where((section) => section.id == _drag?.fromSectionId).firstOrNull ?? widget.sections.firstOrNull;
    if (fallback == null) return hypothesis;
    final limit = fallback.items.where((item) => widget.idOf(item) != _drag?.id).length;
    return InsertionCandidate(sectionId: fallback.id, index: limit);
  }

  // --- Ordering ---

  /// Section orders straight from the data, with the dragged item taken out.
  List<SectionOrder> _baseOrder() => [
    for (final section in widget.sections)
      SectionOrder(
        id: section.id,
        itemIds: [
          for (final item in section.items)
            if (widget.idOf(item) != _drag?.id) widget.idOf(item),
        ],
      ),
  ];

  /// What is actually rendered: the base order with the dragged item spliced
  /// into its current hypothesis, so the gap opens where it would land.
  List<SectionOrder> _displayOrder() {
    final drag = _drag;
    if (drag == null) {
      return [
        for (final section in widget.sections) SectionOrder(id: section.id, itemIds: [for (final item in section.items) widget.idOf(item)]),
      ];
    }

    return [
      for (final order in _baseOrder())
        SectionOrder(
          id: order.id,
          itemIds: order.id == drag.hypothesis.sectionId ? ([...order.itemIds]..insert(drag.hypothesis.index.clamp(0, order.itemIds.length), drag.id)) : order.itemIds,
        ),
    ];
  }

  // --- Ticker ---

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastTick = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dtRaw = _lastTick == Duration.zero ? 1 / 60 : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    // A long frame must not fling the springs across the screen.
    final dt = dtRaw.clamp(0.0, 1 / 30);

    // The tick runs FIRST so everything below — most importantly the anchor
    // correction — sees exactly the zoom this frame's layout will use.
    final result = _animator.tick(dt);

    final drag = _drag;
    if (drag != null && drag.isActive) {
      _applyPointer();
    }

    // The one scroll correction per frame. Scroll writes must not happen per
    // pointer event: `jumpTo` moves pixels immediately while paint transforms
    // only refresh at the next layout, so a second same-frame correction
    // re-applies the first one — a sign-alternating oscillation. Here, at
    // ticker time, pixels and transforms are in sync (the previous frame
    // consumed the single write), so the correction converges in one step.
    final anchorBox = _renderBox;
    if (anchorBox != null) {
      final anchorId = anchorBox.zoomAnchorId;
      final pinch = _pinch;
      if (pinch != null) {
        // Live pinch: pin to the fingers' latest focal.
        final focalGlobalY = pinch.lastFocalGlobalY;
        if (anchorId != null && focalGlobalY != null) {
          _anchorScroll(
            box: anchorBox,
            anchorId: anchorId,
            fraction: anchorBox.zoomAnchorFraction.dy,
            focalGlobalY: focalGlobalY,
            zoom: _animator.zoomLevel.value,
          );
        }
      } else if (_settleFocalY case final settleFocalY?) {
        // Settle: keep pinning to the frozen focal, including one final
        // correction on the very frame the spring rests — the terminal snap
        // (and a release already within the spring's rest tolerance) would
        // otherwise never be corrected.
        if (anchorId != null) {
          _anchorScroll(
            box: anchorBox,
            anchorId: anchorId,
            fraction: anchorBox.zoomAnchorFraction.dy,
            focalGlobalY: settleFocalY,
            zoom: _animator.zoomLevel.value,
          );
        }
        if (!_animator.zoomLevel.isAnimating) {
          _settleFocalY = null;
        }
      }
    }

    // Collapse the crossfade copies the moment the zoom spring rests (and catch
    // a primary-slot flip during the settle).
    _syncZoomBuild();

    if (result.exited.isNotEmpty) {
      setState(() {
        for (final id in result.exited) {
          _ghosts.remove(id);
        }
      });
    }

    final box = _renderBox;
    if (box != null) {
      if (_animator.needsLayout) {
        box.markNeedsLayout();
      } else {
        box.markNeedsPaint();
      }
    }

    if (drag != null && drag.phase == DragPhase.settling && !_animator.isSettling) {
      _finishSettle();
      return;
    }

    if (!result.active && _drag == null && _pinch == null && _settleFocalY == null) {
      _ticker.stop();
    }
  }

  // --- Drag ---

  Drag? _onDragStart(Object id, Offset globalPosition) {
    // Never begin a drag once a pinch owns the pointers, while a second finger
    // is down (a pinch the scale recognizer has not yet claimed), or while the
    // zoom is still morphing the layout (a long-press can mature mid-settle).
    if (!widget.reorderEnabled || _drag != null || _pinch != null || _animator.zoomActive || _activePointers >= 2) return null;

    final box = _renderBox;
    final item = _itemsById[id];
    if (box == null || item == null) return null;

    final topLeft = _animator.offsetOf(id);
    final size = box.itemSizes[id];
    if (topLeft == null || size == null) return null;

    final (sectionId, index) = _locate(id);
    if (sectionId == null) return null;

    final local = box.globalToLocal(globalPosition);

    _drag = DragSession<T>(
      id: id,
      item: item,
      fromSectionId: sectionId,
      fromIndex: index,
      grabOffset: local - topLeft,
      pointer: globalPosition,
      contentWidth: box.lastContentWidth,
      crossAxisCount: _effectiveCrossAxisCount,
      hypothesis: InsertionCandidate(sectionId: sectionId, index: index),
    );

    _animator
      ..draggedId = id
      ..lift.retarget(1, widget.springs.settle);

    _startTicker();
    widget.onReorderStarted?.call(item);
    setState(() {});

    return GridDrag(
      onUpdate: _onDragUpdate,
      onEnd: _onDragEnd,
      onCancel: () => _abortDrag(notify: true),
    );
  }

  (Object?, int) _locate(Object id) {
    for (final section in widget.sections) {
      final index = section.items.indexWhere((item) => widget.idOf(item) == id);
      if (index >= 0) return (section.id, index);
    }
    return (null, -1);
  }

  void _onDragUpdate(Offset globalPosition) {
    final drag = _drag;
    final box = _renderBox;
    if (drag == null || box == null) return;

    // A resize or a column-count change invalidates every cached rect; bail out
    // rather than drop into the wrong slot.
    if ((box.lastContentWidth - drag.contentWidth).abs() > 0.5 || _effectiveCrossAxisCount != drag.crossAxisCount) {
      _abortDrag(notify: true);
      return;
    }

    drag.pointer = globalPosition;
    _applyPointer();

    final size = box.itemSizes[drag.id];
    if (size != null) {
      final topLeft = box.localToGlobal(_animator.offsetOf(drag.id) ?? Offset.zero);
      _autoScroller?.startAutoScrollIfNecessary(topLeft & size);
    }
  }

  void _onScrollViewScrolled() {
    if (_drag?.isActive ?? false) _applyPointer();
  }

  /// Pin the item under the finger and re-resolve where it would land. Runs on
  /// pointer moves and every frame, so autoscrolling keeps the gap in step even
  /// while the finger is still.
  void _applyPointer() {
    final drag = _drag;
    final box = _renderBox;
    if (drag == null || box == null) return;

    final topLeft = box.globalToLocal(drag.pointer) - drag.grabOffset;
    _animator.setDragOffset(topLeft);
    box.markNeedsPaint();

    final heights = {for (final entry in box.itemSizes.entries) entry.key: entry.value.height};
    if (!heights.containsKey(drag.id)) return;

    final candidate = resolveInsertion(
      sections: _baseOrder(),
      chrome: [
        for (final section in widget.sections)
          SectionChrome(
            id: section.id,
            headerHeight: box.headerHeightOf(section.id),
            footerHeight: box.footerHeightOf(section.id),
            emptyExtent: section.emptyDropExtent,
          ),
      ],
      heights: heights,
      draggedId: drag.id,
      draggedTopLeft: topLeft,
      template: _template(box.size.width),
      current: drag.hypothesis,
    );

    if (candidate != null && candidate != drag.hypothesis) {
      setState(() => drag.hypothesis = candidate);
    }
  }

  GridLayoutSpec _template(double width) => GridLayoutSpec(
    width: width,
    sections: const [],
    crossAxisCount: _effectiveCrossAxisCount,
    crossAxisSpacing: widget.crossAxisSpacing,
    mainAxisSpacing: widget.mainAxisSpacing,
    padding: widget.padding.resolve(Directionality.of(context)),
    textDirection: Directionality.of(context),
  );

  void _onDragEnd() {
    final drag = _drag;
    final box = _renderBox;
    if (drag == null) return;

    _autoScroller?.stopAutoScroll();

    // The rendered layout already holds the dragged item at its hypothesis, so
    // its solved rect is exactly the slot to settle into.
    final target = box?.lastLayout?.itemRects[drag.id]?.topLeft;
    if (target != null) {
      _animator.settleDragged(target);
    }
    _animator.lift.retarget(0, widget.springs.reflow);

    setState(() => drag.phase = DragPhase.settling);

    final order = _displayOrder();
    widget.onReorderFinished?.call(
      GridReorderResult<T>(
        item: drag.item,
        fromSectionId: drag.fromSectionId,
        fromIndex: drag.fromIndex,
        toSectionId: drag.hypothesis.sectionId,
        toIndex: drag.hypothesis.index,
        sections: [
          for (final section in order)
            GridSectionItems<T>(
              sectionId: section.id,
              items: [
                for (final id in section.itemIds) ?_itemsById[id],
              ],
            ),
        ],
      ),
    );

    _startTicker();
  }

  /// Return the item to where it came from, then release the session.
  void _abortDrag({required bool notify}) {
    final drag = _drag;
    if (drag == null) return;

    _autoScroller?.stopAutoScroll();
    _animator.lift.retarget(0, widget.springs.reflow);

    if (notify) widget.onReorderCanceled?.call(drag.item);

    _animator.draggedId = null;
    _drag = null;
    if (mounted) setState(() {});
    _startTicker();
  }

  void _finishSettle() {
    _animator.draggedId = null;
    _drag = null;
    if (mounted) setState(() {});
  }

  // --- Pinch zoom ---

  bool _canStartPinch() => (widget.zoomConfig?.isEnabled ?? false) && _drag == null;

  void _onScaleStart(ScaleStartDetails details) {
    final config = widget.zoomConfig;
    final box = _renderBox;
    if (config == null || box == null || _drag != null) return;

    _pinch = _PinchSession(
      baseCount: _effectiveCrossAxisCount,
      baseZoom: _animator.zoomLevel.value,
      contentWidth: box.lastContentWidth,
    )..lastFocalGlobalY = details.focalPoint.dy;
    // The live session owns the pinning now. Without this, a finger peel-off
    // (first finger lifts → onEnd → the survivor's next move restarts the
    // gesture) leaves the settle block and the new session fighting over the
    // scroll with different focals.
    _settleFocalY = null;
    _captureAnchor(box, details.focalPoint);
    _animator.zoomSessionActive = true;
    _startTicker();
    // Rebuild so drag-start gating and isDragging see the active pinch.
    setState(() {});
  }

  /// Records the item under the focal point (and the fractional point inside
  /// it) so the scroll pinning can keep that spot beneath the fingers as the
  /// grid grows or shrinks. Purely a scroll concern: paint follows each item's
  /// lerped rect regardless of the anchor.
  ///
  /// The fraction is deliberately unclamped: in the nearest-item fallback the
  /// focal point lies outside the anchor rect, and clamping would move the
  /// anchored point away from the fingers — the scroll would jump the moment
  /// the pinch starts.
  void _captureAnchor(RenderMasonryGrid box, Offset globalFocal) {
    final layout = box.lastLayout;
    if (layout == null) return;

    final localFocal = box.globalToLocal(globalFocal);

    Object? bestId;
    var bestDistance = double.infinity;
    for (final entry in layout.itemRects.entries) {
      final rect = entry.value;
      if (rect.contains(localFocal)) {
        bestId = entry.key;
        break;
      }
      final distance = (rect.center - localFocal).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        bestId = entry.key;
      }
    }

    if (bestId != null) {
      box
        ..zoomAnchorId = bestId
        ..zoomAnchorFraction = anchorFractionForPoint(anchorRect: layout.itemRects[bestId]!, localPoint: localFocal);
    } else {
      box.zoomAnchorId = null;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final pinch = _pinch;
    final config = widget.zoomConfig;
    final box = _renderBox;
    if (pinch == null || config == null || box == null) return;

    // A resize mid-pinch invalidates the cached geometry.
    if ((box.lastContentWidth - pinch.contentWidth).abs() > 0.5) {
      _endPinch(scaleVelocity: 0);
      return;
    }

    final zoom = zoomLevelForScale(scale: details.scale, baseZoom: pinch.baseZoom, config: config);
    _animator.zoomLevel.jumpTo(zoom);
    _syncZoomBuild();
    pinch.lastFocalGlobalY = details.focalPoint.dy;
    box.markNeedsLayout();
    // The scroll correction that keeps the content under the fingers happens
    // once per FRAME in the ticker, not here: pointer events arrive several
    // times per frame and a second same-frame `jumpTo` overcorrects against
    // the not-yet-relaid-out transforms. Ensure the ticker is alive to carry
    // it (it may have stopped mid-hold when every spring rested).
    _startTicker();
  }

  /// Predicts the grid layout at [zoom] from the last measured heights, without
  /// re-laying-out children — the render object does the real (measured) layout
  /// after this.
  ///
  /// Heights are keyed by COLUMN COUNT, not by slot label: when the integer
  /// pair rolls over between layouts, the old pair's other slot still holds
  /// the correct measurements for the shared count. An endpoint the box has
  /// not measured yet substitutes its nearest measured map — its lerp weight
  /// right after a rollover is at most the per-event zoom delta, so the
  /// residual is a couple of pixels instead of a full column-width error.
  /// Returns null (callers skip the correction for one frame) only when the
  /// DOMINANT endpoint is unmeasured — a teleport-speed pinch crossing more
  /// than one integer in a single event.
  GridLayoutResult? _predictLayout(RenderMasonryGrid box, double zoom) {
    if (box.lastLayout == null) return null;

    final direction = Directionality.of(context);
    final padding = widget.padding.resolve(direction);
    final low = zoom.floor() < 1 ? 1 : zoom.floor();
    final high = zoom.ceil() < 1 ? 1 : zoom.ceil();
    final t = low == high ? 0.0 : zoom - low;

    final measured = box.measuredPair;
    Map<Object, double>? heightsFor(int count) {
      if (count == measured.low) return box.lowSlotItemHeights;
      if (count == measured.high) return box.highSlotItemHeights;
      return null;
    }

    // Nearest measured map as a stand-in for an unmeasured endpoint.
    Map<Object, double> nearestTo(int count) => (count - measured.low).abs() <= (count - measured.high).abs() ? box.lowSlotItemHeights : box.highSlotItemHeights;

    final lowHeights = heightsFor(low);
    final highHeights = heightsFor(high);
    final dominantMeasured = t < 0.5 ? lowHeights != null : highHeights != null;
    if (!dominantMeasured) return null;

    List<GridSectionSpec> sectionsFrom(Map<Object, double> heights) => [
      for (final section in widget.sections)
        GridSectionSpec(
          id: section.id,
          items: [
            for (final item in section.items) GridItemSpec(id: widget.idOf(item), height: heights[widget.idOf(item)] ?? 0),
          ],
          headerHeight: box.headerHeightOf(section.id) * (1 - _animator.collapseOf(section.id)),
          footerHeight: box.footerHeightOf(section.id) * (1 - _animator.collapseOf(section.id)),
        ),
    ];

    GridLayoutSpec specFor(List<GridSectionSpec> sections, int count) => GridLayoutSpec(
      width: box.size.width,
      sections: sections,
      crossAxisCount: count,
      crossAxisSpacing: widget.crossAxisSpacing,
      mainAxisSpacing: widget.mainAxisSpacing,
      padding: padding,
      textDirection: direction,
    );

    final specLow = specFor(sectionsFrom(lowHeights ?? nearestTo(low)), low);
    if (low == high) return computeMasonryLayout(specLow);

    return lerpGridLayoutResult(
      computeMasonryLayout(specLow),
      computeMasonryLayout(specFor(sectionsFrom(highHeights ?? nearestTo(high)), high)),
      t,
    );
  }

  /// Adjusts the ancestor scroll so the anchor point sits at [focalGlobalY].
  void _anchorScroll({
    required RenderMasonryGrid box,
    required Object anchorId,
    required double fraction,
    required double focalGlobalY,
    required double zoom,
  }) {
    final scrollable = _scrollable;
    if (scrollable == null) return;

    final rect = _predictLayout(box, zoom)?.itemRects[anchorId];
    if (rect == null) return;

    final predictedLocalY = rect.top + rect.height * fraction;
    final predictedGlobalY = box.localToGlobal(Offset(0, predictedLocalY)).dy;

    final position = scrollable.position;
    final target = (position.pixels + (predictedGlobalY - focalGlobalY)).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() > 0.01) {
      position.jumpTo(target);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) => _endPinch(scaleVelocity: details.scaleVelocity);

  void _endPinch({required double scaleVelocity}) {
    final pinch = _pinch;
    final config = widget.zoomConfig;
    final box = _renderBox;
    if (pinch == null || config == null) return;

    final resolved = resolveZoomRelease(
      zoomLevel: _animator.zoomLevel.value,
      scaleVelocity: scaleVelocity,
      config: config,
    );

    _animator
      ..zoomSessionActive = false
      ..zoomLevel.retarget(resolved.toDouble(), widget.springs.zoomSettle);

    // Keep pinning the scroll to the last focal y while the settle spring
    // runs; the anchor item itself is read live from the render box each tick.
    _settleFocalY = box?.zoomAnchorId != null ? pinch.lastFocalGlobalY : null;
    _pinch = null;

    if (resolved != pinch.baseCount) {
      _pendingCount = resolved;
      widget.onCrossAxisCountChanged?.call(resolved);
    }

    _startTicker();
    setState(() {});
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final drag = _drag;
    final order = _displayOrder();
    final orderById = {for (final section in order) section.id: section.itemIds};

    // During a crossfade every item is emitted twice: the primary copy renders
    // the committed-count side of the morph, the overlay copy the other side.
    final zoomBuild = _expectedZoomBuild();
    _builtZoom = zoomBuild;
    final overlaySlot = zoomBuild.primarySlot == ZoomSlot.low ? ZoomSlot.high : ZoomSlot.low;

    final children = <Widget>[
      // Painted first so a fading item never covers a live one.
      for (final entry in _ghosts.entries)
        GridChild(
          key: ValueKey(('ghost', entry.key)),
          id: entry.key,
          sectionId: const Object(),
          role: GridChildRole.ghost,
          ghostSize: entry.value.size,
          child: IgnorePointer(child: widget.itemBuilder(context, entry.value.item)),
        ),
    ];

    for (final section in widget.sections) {
      if (section.header case final header?) {
        children.add(
          GridChild(
            key: ValueKey(('header', section.id)),
            id: section.id,
            sectionId: section.id,
            role: GridChildRole.header,
            child: header,
          ),
        );
      }

      for (final id in orderById[section.id] ?? const <Object>[]) {
        final item = _itemsById[id];
        if (item == null) continue;
        final isDragged = drag?.id == id;

        var child = widget.itemBuilder(context, item);
        if (isDragged && widget.liftedBuilder != null) {
          child = widget.liftedBuilder!(context, item, child);
        }

        children.add(
          GridChild(
            key: ValueKey(('item', id)),
            id: id,
            sectionId: section.id,
            role: GridChildRole.item,
            zoomSlot: zoomBuild.primarySlot,
            child: _DragStartListener(
              enabled: widget.reorderEnabled,
              delay: widget.dragStartDelay,
              onStart: (position) => _onDragStart(id, position),
              child: child,
            ),
          ),
        );

        if (zoomBuild.dual) {
          children.add(
            GridChild(
              key: ValueKey(('zoomOverlay', id)),
              id: id,
              sectionId: section.id,
              role: GridChildRole.item,
              zoomSlot: overlaySlot,
              isZoomOverlay: true,
              child: IgnorePointer(
                child: ExcludeSemantics(child: widget.itemBuilder(context, item)),
              ),
            ),
          );
        }
      }

      if (section.footer case final footer?) {
        children.add(
          GridChild(
            key: ValueKey(('footer', section.id)),
            id: section.id,
            sectionId: section.id,
            role: GridChildRole.footer,
            child: footer,
          ),
        );
      }
    }

    final Widget body = MasonryGridBody(
      key: _bodyKey,
      animator: _animator,
      sectionConfigs: [
        for (final section in widget.sections)
          SectionLayoutConfig(
            id: section.id,
            collapseWhenEmpty: section.collapseWhenEmpty,
            emptyDropExtent: section.emptyDropExtent,
          ),
      ],
      crossAxisCount: _effectiveCrossAxisCount,
      crossAxisSpacing: widget.crossAxisSpacing,
      mainAxisSpacing: widget.mainAxisSpacing,
      padding: widget.padding.resolve(Directionality.of(context)),
      textDirection: Directionality.of(context),
      isDragging: drag?.isActive ?? false,
      liftScale: widget.liftScale,
      children: children,
    );

    if (widget.zoomConfig == null) return body;
    return _wrapWithPinch(body);
  }

  Widget _wrapWithPinch(Widget body) => Listener(
    onPointerDown: (_) => _activePointers++,
    onPointerUp: (_) => _activePointers = _activePointers > 0 ? _activePointers - 1 : 0,
    onPointerCancel: (_) => _activePointers = _activePointers > 0 ? _activePointers - 1 : 0,
    child: RawGestureDetector(
      gestures: {
        _TwoFingerScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<_TwoFingerScaleGestureRecognizer>(
          () => _TwoFingerScaleGestureRecognizer(canStart: _canStartPinch),
          (instance) => instance
            ..onStart = _onScaleStart
            ..onUpdate = _onScaleUpdate
            ..onEnd = _onScaleEnd,
        ),
      },
      // Let the item drag recognizers and the ancestor scrollable also see the
      // pointers; the scale recognizer only wins for a real two-finger pinch.
      behavior: HitTestBehavior.translucent,
      child: body,
    ),
  );
}

/// A pinch in flight: what count it started from, and the content width at the
/// time (a resize invalidates the cached geometry).
class _PinchSession {
  _PinchSession({required this.baseCount, required this.baseZoom, required this.contentWidth});

  /// The committed column count at gesture start, for deciding whether the
  /// release resolved to a new count.
  final int baseCount;

  /// The live zoom level at gesture start — fractional when a new pinch begins
  /// mid-settle, so the first update continues from it instead of snapping.
  final double baseZoom;

  final double contentWidth;

  /// The most recent focal point in global coordinates. Frozen at this value
  /// for the release settle so the anchor keeps its place while the grid
  /// finishes morphing. (The anchor item and fraction live on the render box.)
  double? lastFocalGlobalY;
}

/// A [ScaleGestureRecognizer] that only claims the arena for a genuine
/// two-finger pinch.
///
/// The base recognizer aggressively claims on a one-finger pan too, which would
/// steal single-finger scrolling from an ancestor list. Declining the claim
/// while fewer than two pointers are down (or while pinch is disabled) leaves
/// that gesture to the list, exactly as iOS behaves.
class _TwoFingerScaleGestureRecognizer extends ScaleGestureRecognizer {
  _TwoFingerScaleGestureRecognizer({required this.canStart});

  final bool Function() canStart;

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && (pointerCount < 2 || !canStart())) {
      return;
    }
    super.resolve(disposition);
  }
}

/// Starts a drag after [delay], losing the pointer to an ancestor scrollable if
/// the user scrolls first and to a tap recognizer if they release first.
///
/// `RawGestureDetector` owns the recognizer's lifecycle, so this widget must
/// not dispose it.
class _DragStartListener extends StatelessWidget {
  const _DragStartListener({
    required this.child,
    required this.onStart,
    required this.delay,
    required this.enabled,
  });

  final Widget child;
  final Drag? Function(Offset globalPosition) onStart;
  final Duration delay;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return RawGestureDetector(
      gestures: {
        DelayedMultiDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<DelayedMultiDragGestureRecognizer>(
          () => DelayedMultiDragGestureRecognizer(delay: delay),
          (instance) => instance.onStart = onStart,
        ),
      },
      child: child,
    );
  }
}
