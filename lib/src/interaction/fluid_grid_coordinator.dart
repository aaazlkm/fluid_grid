import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/drag/drag_session.dart';
import 'package:fluid_grid/src/drag/insertion_resolver.dart';
import 'package:fluid_grid/src/interaction/fluid_grid_view.dart';
import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:fluid_grid/src/layout/grid_render_host.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/model/grid_reorder_result.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:fluid_grid/src/zoom/zoom_cell_offset_store.dart';
import 'package:fluid_grid/src/zoom/zoom_math.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Owns every piece of interaction state for a fluid grid — the animator, the
/// drag session, the pinch session, the ghost set, the pending pinch count, and
/// the single ticker that advances them — independent of whether the grid is a
/// box or a sliver. The hosting widget drives it through [FluidGridView] and
/// reads back a small render-model for its `build`.
class FluidGridCoordinator<T> {
  FluidGridCoordinator({required this.view, required TickerProvider vsync})
    : animator = GridAnimator(
        springs: view.springs,
        initialZoomLevel: view.crossAxisCount.toDouble(),
      ) {
    _ticker = vsync.createTicker(_onTick);
    _prevCrossAxisCount = view.crossAxisCount;
    _prevZoomLevels = view.zoomConfig?.zoomLevels;
    _pairCounts = {view.crossAxisCount};
    _committedCount = view.crossAxisCount;
    _indexItems();
  }

  final FluidGridView<T> view;

  final GridAnimator animator;

  /// The photos zoom's persistent cell alignment (iOS-style grid re-anchoring
  /// on the pinched item). Owned here, shared by identity with the render
  /// objects, which stamp it into their solver specs; see [ZoomCellOffsetStore].
  final ZoomCellOffsetStore cellOffsets = ZoomCellOffsetStore();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  DragSession<T>? _drag;
  EdgeDraggingAutoScroller? _autoScroller;
  ScrollableState? _scrollable;

  int _prevCrossAxisCount = 1;
  List<int>? _prevZoomLevels;

  /// The column counts of the morph pair the zoom currently sits in. A count
  /// ENTERING the pair for the first time gets its cell offsets assigned once,
  /// finger-aligned; re-entries keep their stored alignment and follow the
  /// fingers only through the hysteresis-gated live retargeting.
  Set<int> _pairCounts = const {};

  /// Whether the previous tick saw the zoom active, for detecting the settle's
  /// completion frame (the cell-offset commit point).
  bool _wasTickZoomActive = false;

  /// The column count whose cell alignment is the COMMITTED resting one — the
  /// grid the user is actually looking at between gestures. Its canvas must
  /// never live-retarget (re-flowing the resting grid mid-gesture), unlike
  /// [effectiveCrossAxisCount], which flips to the tentative settle target the
  /// moment a pinch is released.
  int _committedCount = 1;

  /// The column count resolved by a pinch but not yet echoed back through the
  /// widget's crossAxisCount. Held so the round-trip is a no-op, exactly like
  /// the reorder optimistic update.
  int? _pendingCount;

  int get effectiveCrossAxisCount => _pendingCount ?? view.crossAxisCount;

  _PinchSession? _pinch;

  /// The frozen focal point (global) the scroll pinning keeps targeting while
  /// the zoom settles after the fingers lift. Vertical only — the horizontal
  /// fixed point is the render host's zoomFocalX, frozen separately.
  Offset? _settleFocal;

  /// Pointers currently down on the grid. A drag must not start once a second
  /// finger lands, even if the scale recognizer has not yet claimed the arena.
  int _activePointers = 0;

  ZoomBuild _builtZoom = (dual: false, primarySlot: ZoomSlot.none);

  final Map<Object, GridGhost<T>> _ghosts = {};
  final Map<Object, T> _itemsById = {};

  GridHost? get _host => view.host;

  // --- Read-model for the hosting widget's build ---

  DragSession<T>? get drag => _drag;
  bool get isDragging => _drag?.isActive ?? false;
  T? itemFor(Object id) => _itemsById[id];
  T? ghostItemFor(Object id) => _ghosts[id]?.item;

  /// The removed-but-fading items, for ghost children.
  Iterable<({Object id, T item, Size size})> get ghosts => _ghosts.entries.map(
    (entry) => (id: entry.key, item: entry.value.item, size: entry.value.size),
  );

  /// During a crossfade every item is emitted twice; the primary copy sits on
  /// the committed-count side of the (floor, ceil) pair so its element — and the
  /// user state inside it — survives the release commit.
  ZoomBuild expectedZoomBuild() {
    // Every remaining zoom style (morph, photos) builds each item twice; a
    // config-less grid never activates the zoom, so this stays false at rest.
    if (!animator.zoomActive) return (dual: false, primarySlot: ZoomSlot.none);
    final low = levelNeighbors(
      animator.zoomLevel.value,
      view.zoomConfig?.zoomLevels,
    ).low;
    return (
      dual: true,
      primarySlot: effectiveCrossAxisCount > low ? ZoomSlot.high : ZoomSlot.low,
    );
  }

  /// Records what the current build emitted, so [_syncZoomBuild] can tell when
  /// the child list must change shape.
  set builtZoom(ZoomBuild value) => _builtZoom = value;

  /// Rebuilds when the crossfade shape drifted from what the last build emitted:
  /// session start/end, the release settle finishing, or the zoom crossing the
  /// committed count. Ordinary pair rollovers change nothing here.
  void _syncZoomBuild() {
    if (!view.isMounted) return;
    if (expectedZoomBuild() != _builtZoom) view.requestRebuild();
  }

  // --- Lifecycle, driven by the hosting State ---

  void attachScrollable(ScrollableState? scrollable) {
    if (scrollable == _scrollable) return;
    _scrollable = scrollable;
    _autoScroller = scrollable == null
        ? null
        : EdgeDraggingAutoScroller(
            scrollable,
            onScrollViewScrolled: _onScrollViewScrolled,
            velocityScalar: view.autoScrollVelocityScalar,
          );
  }

  void didUpdateWidget() {
    animator.springs = view.springs;
    // The allowed levels changed at rest: the stored alignments were derived
    // against pairs that no longer exist.
    final levels = view.zoomConfig?.zoomLevels;
    if (!listEquals(levels, _prevZoomLevels)) {
      _prevZoomLevels = levels == null ? null : List.of(levels);
      if (!animator.zoomActive) {
        cellOffsets.clear();
        _committedCount = view.crossAxisCount;
      }
    }
    if (view.crossAxisCount != _prevCrossAxisCount) {
      _onCrossAxisCountUpdated();
    }
    _prevCrossAxisCount = view.crossAxisCount;
    _reconcile();
  }

  /// Reconciles an incoming crossAxisCount with the pending pinch result.
  void _onCrossAxisCountUpdated() {
    if (_pendingCount == view.crossAxisCount) {
      // Our own pinch result echoed back; the layout is already there.
      _pendingCount = null;
      return;
    }

    // An external change always wins. Morph to it when zoom is enabled (so the
    // change animates), or jump when it is not (preserving the plain behavior).
    _pendingCount = null;
    if (view.zoomConfig != null) {
      _morphToExternalCount();
    } else {
      _jumpToExternalCount();
    }
  }

  /// Animates an externally set crossAxisCount into place through the morph.
  void _morphToExternalCount() {
    // The photos canvases need a fixed point even for a programmatic morph;
    // an anchor left over from an old pinch may be far off-screen and would
    // sweep both canvases across the viewport. Recapture at the viewport
    // centre (a live pinch or an in-flight settle keeps its own anchor —
    // replacing it mid-settle would break the focal pinning's continuity).
    final host = _host;
    if (view.zoomConfig!.style == GridZoomStyle.photos &&
        host != null &&
        _gestureIdle) {
      _captureProgrammaticAnchor(host);
    }
    animator.zoomLevel.retarget(
      view.crossAxisCount.toDouble(),
      view.springs.zoomSettle,
    );
    // A programmatic morph has no fingers to serve: entering endpoints get
    // canonical alignment, so external count changes are also the natural
    // path back to an un-shifted grid.
    _syncPairOffsets();
    _startTicker();
  }

  /// Applies an externally set crossAxisCount instantly (zoom disabled).
  void _jumpToExternalCount() {
    animator.zoomLevel.jumpTo(view.crossAxisCount.toDouble());
    cellOffsets.commit(view.crossAxisCount);
    _pairCounts = {view.crossAxisCount};
    _committedCount = view.crossAxisCount;
    _host?.markNeedsGridLayout();
  }

  /// Captures a zoom anchor for a morph that has no fingers on the screen:
  /// the item nearest the visible viewport's centre, or the grid's top centre
  /// when no scrollable is attached.
  void _captureProgrammaticAnchor(GridHost host) {
    final scrollBox = _scrollable?.context.findRenderObject();
    final globalFocal = scrollBox is RenderBox && scrollBox.hasSize
        ? scrollBox.localToGlobal(scrollBox.size.center(Offset.zero))
        : host.gridLocalToGlobal(Offset(host.gridWidth / 2, 0));
    _captureAnchor(host, globalFocal);
  }

  void dispose() {
    _ticker.dispose();
  }

  // --- Data reconciliation ---

  void _indexItems() {
    _itemsById
      ..clear()
      ..addEntries([
        for (final section in view.sections)
          for (final item in section.items) MapEntry(view.idOf(item), item),
      ]);
  }

  /// Diff by identity: survivors spring to their new slots, arrivals fade in,
  /// departures become ghosts pinned at their last rect.
  void _reconcile() {
    final previous = Map<Object, T>.of(_itemsById);
    _indexItems();

    _cancelGhostsForReturningIds();

    // Cell alignments persist across data changes (iOS-like); only sections
    // that left the data lose theirs.
    final liveSectionIds = {for (final section in view.sections) section.id};
    cellOffsets.retainSections(liveSectionIds.contains);

    _spawnGhostsForDepartures(previous);
    _clampActiveDrag();
    _rehomeZoomAnchor();

    _startTicker();
  }

  /// An id that comes back before its exit fade finished must stop being a
  /// ghost, else the build emits both the ghost and the live tile for it.
  void _cancelGhostsForReturningIds() {
    for (final id in _itemsById.keys) {
      if (_ghosts.remove(id) != null) animator.cancelExit(id);
    }
  }

  /// Items that left the data become ghosts pinned at their last rect.
  void _spawnGhostsForDepartures(Map<Object, T> previous) {
    final host = _host;
    for (final entry in previous.entries) {
      final id = entry.key;
      if (_itemsById.containsKey(id) || _ghosts.containsKey(id)) continue;

      final size = host?.itemSizeOf(id);
      final offset = animator.offsetOf(id);
      if (size == null || offset == null) {
        animator.remove(id);
        continue;
      }

      _ghosts[id] = GridGhost(item: entry.value, size: size);
      animator.beginExit(id, offset & size);
    }
  }

  /// Aborts the drag when its item left the data, else keeps its hypothesis
  /// valid against the incoming sections.
  void _clampActiveDrag() {
    final drag = _drag;
    if (drag == null) return;
    if (!_itemsById.containsKey(drag.id)) {
      _abortDrag(notify: true);
    } else {
      drag.hypothesis = _clampHypothesis(drag.hypothesis);
    }
  }

  /// The scroll anchor left the data mid-morph: hand it to the nearest survivor.
  void _rehomeZoomAnchor() {
    final host = _host;
    if (host == null || !animator.zoomActive) return;
    final anchorId = host.zoomAnchorId;
    if (anchorId == null || _itemsById.containsKey(anchorId)) return;

    final anchorRect = host.lastLayout?.itemRects[anchorId];
    Object? nearest;
    var nearestDistance = double.infinity;
    for (final entry
        in host.lastLayout?.itemRects.entries ??
            const Iterable<MapEntry<Object, Rect>>.empty()) {
      if (!_itemsById.containsKey(entry.key)) continue;
      final distance = anchorRect == null
          ? 0.0
          : (entry.value.center - anchorRect.center).distanceSquared;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = entry.key;
      }
    }
    if (nearest == null) {
      host.zoomAnchorId = null;
      return;
    }

    // dy-only is deliberate: the y fraction re-pins to the focal against
    // the predicted layout, while dx continuity carries over via
    // reanchor's carriedDx (x only feeds the entry-offset chooser — the
    // canvases' horizontal fixed point is the frozen zoomFocalX).
    final focalGlobalY = _activeFocalGlobal?.dy;
    final predicted = focalGlobalY == null
        ? null
        : _predictLayout(
            host,
            animator.zoomLevel.value,
          )?.itemRects[nearest];
    if (predicted != null && predicted.height != 0) {
      final focalLocalY = host
          .globalToGridLocal(Offset(0, focalGlobalY!))
          .dy;
      // reanchor first so the x fraction carries the old anchor's grid
      // position over (the photos canvases are anchored on x too), then
      // pin dy to the focal against the predicted post-change layout.
      host.reanchor(nearest);
      final carriedDx = host.zoomAnchorFraction.dx;
      host.zoomAnchorFraction = Offset(
        carriedDx,
        (focalLocalY - predicted.top) / predicted.height,
      );
    } else {
      host.reanchor(nearest);
    }
  }

  /// Keeps the drag hypothesis valid against the incoming sections.
  InsertionCandidate _clampHypothesis(InsertionCandidate hypothesis) {
    for (final section in view.sections) {
      if (section.id != hypothesis.sectionId) continue;
      final limit = section.items
          .where((item) => view.idOf(item) != _drag?.id)
          .length;
      if (hypothesis.index <= limit) return hypothesis;
      return InsertionCandidate(sectionId: hypothesis.sectionId, index: limit);
    }

    final fallback =
        view.sections
            .where((section) => section.id == _drag?.fromSectionId)
            .firstOrNull ??
        view.sections.firstOrNull;
    if (fallback == null) return hypothesis;
    final limit = fallback.items
        .where((item) => view.idOf(item) != _drag?.id)
        .length;
    return InsertionCandidate(sectionId: fallback.id, index: limit);
  }

  // --- Ordering ---

  List<SectionOrder> _baseOrder() => [
    for (final section in view.sections)
      SectionOrder(
        id: section.id,
        itemIds: [
          for (final item in section.items)
            if (view.idOf(item) != _drag?.id) view.idOf(item),
        ],
      ),
  ];

  List<SectionOrder> displayOrder() {
    final drag = _drag;
    if (drag == null) {
      return [
        for (final section in view.sections)
          SectionOrder(
            id: section.id,
            itemIds: [for (final item in section.items) view.idOf(item)],
          ),
      ];
    }

    return [
      for (final order in _baseOrder())
        SectionOrder(
          id: order.id,
          itemIds: order.id == drag.hypothesis.sectionId
              ? ([...order.itemIds]..insert(
                  drag.hypothesis.index.clamp(0, order.itemIds.length),
                  drag.id,
                ))
              : order.itemIds,
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
    final dt = _tickDelta(elapsed);

    // The tick runs FIRST so everything below — most importantly the anchor
    // correction — sees exactly the zoom this frame's layout will use.
    final result = animator.tick(dt);

    _commitCellOffsetsOnSettle();

    final drag = _drag;
    if (drag != null && drag.isActive) {
      _applyPointer();
    }

    _tickAnchorScroll();
    _syncZoomBuild();
    _evictExitedGhosts(result.exited);
    _invalidateHost();

    if (drag != null &&
        drag.phase == DragPhase.settling &&
        !animator.isSettling) {
      _finishSettle();
      return;
    }

    if (!result.active && _drag == null && _gestureIdle) {
      _ticker.stop();
    }
  }

  double _tickDelta(Duration elapsed) {
    final dtRaw = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    return dtRaw.clamp(0.0, 1 / 30);
  }

  /// Cell-offset bookkeeping, BEFORE the anchor correction and this frame's
  /// layout invalidation. On the settle's completion frame the committed
  /// level's alignment becomes the resting one (every other count's tentative
  /// entry is dropped), so the collapse-frame solve — and the spring jump it
  /// feeds — lands on exactly the offset layout the canvases were painting.
  void _commitCellOffsetsOnSettle() {
    final tickZoomActive = animator.zoomActive;
    if (_wasTickZoomActive && !tickZoomActive) {
      cellOffsets.commit(effectiveCrossAxisCount);
      _pairCounts = {effectiveCrossAxisCount};
      _committedCount = effectiveCrossAxisCount;
    } else {
      // A settle can sweep through pairs on its own (external count changes
      // morph across several levels): keep entering endpoints assigned.
      _syncPairOffsets();
    }
    _wasTickZoomActive = tickZoomActive;
  }

  /// The one scroll correction per frame. See the note on _anchorScroll: two
  /// corrections in one frame oscillate; here pixels and transforms are in sync.
  void _tickAnchorScroll() {
    final anchorHost = _host;
    if (anchorHost == null) return;
    final anchorId = anchorHost.zoomAnchorId;
    final pinch = _pinch;
    if (pinch != null) {
      final focalGlobal = pinch.lastFocalGlobal;
      if (anchorId != null && focalGlobal != null) {
        // Live pinch: pin the fingers vertically via the ancestor scroll.
        // Horizontally the canvases expand about the frozen zoomFocalX; the
        // fingers' x is not tracked, so the grid never slides sideways.
        _anchorScroll(
          host: anchorHost,
          anchorId: anchorId,
          fraction: anchorHost.zoomAnchorFraction,
          focalGlobal: focalGlobal,
          zoom: animator.zoomLevel.value,
        );
      }
    } else if (_settleFocal case final settleFocal?) {
      if (anchorId != null) {
        // Settle: keep pinning the frozen focal vertically while the
        // canvases finish contracting/expanding about zoomFocalX.
        _anchorScroll(
          host: anchorHost,
          anchorId: anchorId,
          fraction: anchorHost.zoomAnchorFraction,
          focalGlobal: settleFocal,
          zoom: animator.zoomLevel.value,
        );
      }
      if (!animator.zoomLevel.isAnimating) {
        _settleFocal = null;
      }
    }
  }

  /// Drops finished exit fades and rebuilds so their ghost tiles disappear.
  void _evictExitedGhosts(List<Object> exited) {
    if (exited.isEmpty) return;
    for (final id in exited) {
      _ghosts.remove(id);
    }
    view.requestRebuild();
  }

  /// One invalidation per tick: layout when geometry moved, else paint only.
  void _invalidateHost() {
    final host = _host;
    if (host == null) return;
    if (animator.needsLayout) {
      host.markNeedsGridLayout();
    } else {
      host.markNeedsGridPaint();
    }
  }

  // --- Drag ---

  Drag? onDragStart(Object id, Offset globalPosition) {
    if (!view.reorderEnabled ||
        _drag != null ||
        _pinch != null ||
        animator.zoomActive ||
        _activePointers >= 2) {
      return null;
    }

    final host = _host;
    final item = _itemsById[id];
    if (host == null || item == null) return null;

    final topLeft = animator.offsetOf(id);
    final size = host.itemSizeOf(id);
    if (topLeft == null || size == null) return null;

    final (sectionId, index) = _locate(id);
    if (sectionId == null) return null;

    final local = host.globalToGridLocal(globalPosition);

    _drag = DragSession<T>(
      id: id,
      item: item,
      fromSectionId: sectionId,
      fromIndex: index,
      grabOffset: local - topLeft,
      pointer: globalPosition,
      contentWidth: host.contentWidth,
      crossAxisCount: effectiveCrossAxisCount,
      hypothesis: InsertionCandidate(sectionId: sectionId, index: index),
    );

    animator
      ..draggedId = id
      ..lift.retarget(1, view.springs.settle);

    _startTicker();
    view.onReorderStarted?.call(item);
    view.requestRebuild();

    return GridDrag(
      onUpdate: _onDragUpdate,
      onEnd: _onDragEnd,
      onCancel: () => _abortDrag(notify: true),
    );
  }

  (Object?, int) _locate(Object id) {
    for (final section in view.sections) {
      final index = section.items.indexWhere((item) => view.idOf(item) == id);
      if (index >= 0) return (section.id, index);
    }
    return (null, -1);
  }

  void _onDragUpdate(Offset globalPosition) {
    final drag = _drag;
    final host = _host;
    if (drag == null || host == null) return;

    if ((host.contentWidth - drag.contentWidth).abs() > 0.5 ||
        effectiveCrossAxisCount != drag.crossAxisCount) {
      _abortDrag(notify: true);
      return;
    }

    drag.pointer = globalPosition;
    _applyPointer();

    final size = host.itemSizeOf(drag.id);
    if (size != null) {
      final topLeft = host.gridLocalToGlobal(
        animator.offsetOf(drag.id) ?? Offset.zero,
      );
      _autoScroller?.startAutoScrollIfNecessary(topLeft & size);
    }
  }

  void _onScrollViewScrolled() {
    if (_drag?.isActive ?? false) _applyPointer();
  }

  void _applyPointer() {
    final drag = _drag;
    final host = _host;
    if (drag == null || host == null) return;

    final topLeft = host.globalToGridLocal(drag.pointer) - drag.grabOffset;
    animator.setDragOffset(topLeft);
    host.markNeedsGridPaint();

    final heights = host.itemHeights();
    if (!heights.containsKey(drag.id)) return;

    final candidate = resolveInsertion(
      sections: _baseOrder(),
      chrome: [
        for (final section in view.sections)
          SectionChrome(
            id: section.id,
            headerHeight: host.headerHeightOf(section.id),
            footerHeight: host.footerHeightOf(section.id),
            emptyExtent: section.emptyDropExtent,
            leadingCells: cellOffsets.of(effectiveCrossAxisCount, section.id),
          ),
      ],
      heights: heights,
      draggedId: drag.id,
      draggedTopLeft: topLeft,
      template: _specFor(
        host.gridWidth,
        crossAxisCount: effectiveCrossAxisCount,
      ),
      current: drag.hypothesis,
    );

    if (candidate != null && candidate != drag.hypothesis) {
      drag.hypothesis = candidate;
      view.requestRebuild();
    }
  }

  /// A [GridLayoutSpec] carrying the view's spacing, padding, and direction.
  /// Callers that only need count-independent geometry (like
  /// [GridLayoutSpec.columnWidthFor]) can leave the defaults in place.
  GridLayoutSpec _specFor(
    double width, {
    int crossAxisCount = 2,
    List<GridSectionSpec> sections = const [],
  }) => GridLayoutSpec(
    width: width,
    sections: sections,
    crossAxisCount: crossAxisCount,
    crossAxisSpacing: view.crossAxisSpacing,
    mainAxisSpacing: view.mainAxisSpacing,
    padding: view.resolvedPadding,
    textDirection: view.textDirection,
  );

  void _onDragEnd() {
    final drag = _drag;
    final host = _host;
    if (drag == null) return;

    _autoScroller?.stopAutoScroll();

    final target = host?.lastLayout?.itemRects[drag.id]?.topLeft;
    if (target != null) {
      animator.settleDragged(target);
    }
    animator.lift.retarget(0, view.springs.reflow);

    drag.phase = DragPhase.settling;
    view.requestRebuild();

    final order = displayOrder();
    view.onReorderFinished?.call(
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

  void _abortDrag({required bool notify}) {
    final drag = _drag;
    if (drag == null) return;

    _autoScroller?.stopAutoScroll();
    animator.lift.retarget(0, view.springs.reflow);

    if (notify) view.onReorderCanceled?.call(drag.item);

    animator.draggedId = null;
    _drag = null;
    if (view.isMounted) view.requestRebuild();
    _startTicker();
  }

  void _finishSettle() {
    animator.draggedId = null;
    _drag = null;
    if (view.isMounted) view.requestRebuild();
  }

  // --- Pinch zoom ---

  /// No pinch in flight and no settle still pinning its release focal.
  bool get _gestureIdle => _pinch == null && _settleFocal == null;

  /// The focal point the current gesture serves: the live pinch fingers, or
  /// the frozen release focal while the settle finishes.
  Offset? get _activeFocalGlobal => _pinch?.lastFocalGlobal ?? _settleFocal;

  bool canStartPinch() =>
      (view.zoomConfig?.isEnabled ?? false) && _drag == null;

  void onPointerDown() => _activePointers++;
  void onPointerUp() =>
      _activePointers = _activePointers > 0 ? _activePointers - 1 : 0;

  void onScaleStart(ScaleStartDetails details) {
    // A genuine pinch has two fingers. The scale recognizer RESTARTS after its
    // first end when the trailing finger moves while lifting (staggered lift,
    // which real hardware produces almost every time): that phantom session
    // would begin AT the released zoom, so its own end re-resolves by
    // nearest-level and overwrites the travel-threshold commit the real
    // release just made. Ignoring sub-two-pointer starts keeps [_pinch] null,
    // so the phantom update/end pair is inert and the first resolution stands.
    if (details.pointerCount < 2) return;
    final config = view.zoomConfig;
    final host = _host;
    if (config == null || host == null || _drag != null) return;

    _pinch = _PinchSession(
      baseCount: effectiveCrossAxisCount,
      baseZoom: animator.zoomLevel.value,
      contentWidth: host.contentWidth,
    )..lastFocalGlobal = details.focalPoint;
    _settleFocal = null;
    _captureAnchor(host, details.focalPoint);
    animator.zoomSessionActive = true;
    _startTicker();
    view.requestRebuild();
  }

  void _captureAnchor(GridHost host, Offset globalFocal) {
    final layout = host.lastLayout;
    if (layout == null) return;

    final localFocal = host.globalToGridLocal(globalFocal);

    // The fallback horizontal fixed point of the photos canvases (the render
    // objects prefer the anchor's fraction-matching abscissa, photosPairFixedX,
    // which makes the anchor's two renditions coincide). Frozen for the whole
    // morph: a re-pinch while a morph is still painting keeps the old focal,
    // because moving the fixed point of an in-flight (s != 1) transform would
    // snap every painted tile sideways. From rest the transform is the
    // identity, so capturing there is snap-free by construction.
    if (!animator.zoomActive) {
      host.zoomFocalX = localFocal.dx.clamp(0.0, host.gridWidth);
    }

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
      host
        ..zoomAnchorId = bestId
        ..zoomAnchorFraction = anchorFractionForPoint(
          anchorRect: layout.itemRects[bestId]!,
          localPoint: localFocal,
        );
    } else {
      host.zoomAnchorId = null;
    }
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    final pinch = _pinch;
    final config = view.zoomConfig;
    final host = _host;
    if (pinch == null || config == null || host == null) return;

    if ((host.contentWidth - pinch.contentWidth).abs() > 0.5) {
      _endPinch(scaleVelocity: 0);
      return;
    }

    final zoom = zoomLevelForScale(
      scale: details.scale,
      baseZoom: pinch.baseZoom,
      config: config,
    );
    animator.zoomLevel.jumpTo(zoom);
    _syncZoomBuild();
    pinch.lastFocalGlobal = details.focalPoint;
    // The zoom may have entered a new morph pair: give the entering endpoint
    // its finger-aligned cell offsets before this frame's solve reads them.
    _syncPairOffsets();
    host.markNeedsGridLayout();
    _startTicker();
  }

  // --- Cell offsets (iOS-style grid re-anchoring) ---

  /// Keeps [cellOffsets] in step with the morph pair: a column count entering
  /// the pair for the FIRST time gets its alignment assigned once — the cell
  /// delta that lands the anchor in the column nearest the fingers when a photos
  /// pinch is in flight, canonical otherwise (programmatic morphs have no
  /// fingers to serve). The alignment is chosen a SINGLE time, as the endpoint
  /// enters (and is still fading in), so it never re-flows a visible grid: the
  /// pinched tile stays put horizontally for the rest of the gesture. (There is
  /// no live finger-following: the canvases expand about the frozen zoomFocalX,
  /// and nothing could absorb a mid-morph cell re-flow — it would snap the
  /// grid sideways.)
  ///
  /// Runs at every zoom-mutation site (scale updates, ticker frames, external
  /// count changes) — idempotent while the pair and fingers are unchanged.
  void _syncPairOffsets() {
    final neighbors = levelNeighbors(
      animator.zoomLevel.value,
      view.zoomConfig?.zoomLevels,
    );
    final pair = {neighbors.low, neighbors.high};

    final entering = pair.difference(_pairCounts);
    _pairCounts = pair;

    final host = _host;
    final anchorId = host?.zoomAnchorId;
    final focalGlobal = _activeFocalGlobal;
    final photosPinch =
        view.zoomConfig?.style == GridZoomStyle.photos &&
        host != null &&
        anchorId != null &&
        focalGlobal != null;

    for (final count in entering) {
      // Per-pointer scale updates make the zoom (and so the pair) flap within
      // a single frame, bouncing counts out of and back into the pair. The
      // committed count must come back exactly as committed, and any count
      // still holding this gesture's alignment keeps it — a re-entry must never
      // re-flow a visible canvas with a fresh entry delta.
      if (count == _committedCount || cellOffsets.contains(count)) continue;
      if (!photosPinch || count <= 1) {
        cellOffsets.assignCanonical(count);
        continue;
      }
      final delta = _chooseCellDelta(
        host,
        count,
        anchorId: anchorId,
        fraction: host.zoomAnchorFraction,
        focalGlobal: focalGlobal,
      );
      if (delta == null || delta == 0) {
        cellOffsets.assignCanonical(count);
      } else {
        cellOffsets.assignUniform(
          count,
          delta,
          view.sections.map((section) => section.id),
        );
      }
    }
  }

  /// The number of cells to shift the [count]-column layout so the anchor's
  /// cell lands nearest the fingers.
  ///
  /// The target column comes from the anchor's FRACTION point (the grabbed
  /// point inside the tile), clamped to the column range BEFORE the mod —
  /// without the clamp, an edge finger paired with an opposite-edge anchor
  /// wraps to the wrong side of the screen. One delta is broadcast to every
  /// section so all sections rest mutually aligned, matching iOS.
  int? _chooseCellDelta(
    GridHost host,
    int count, {
    required Object anchorId,
    required Offset fraction,
    required Offset focalGlobal,
  }) {
    final padding = view.resolvedPadding;
    final columnWidth = _specFor(host.gridWidth).columnWidthFor(count);
    final stride = columnWidth + view.crossAxisSpacing;
    if (stride <= 0) return null;

    final canonicalRect = _solveCountLayout(
      host,
      count,
      canonical: true,
    ).itemRects[anchorId];
    if (canonicalRect == null) return null;

    final isRtl = view.textDirection == TextDirection.rtl;
    int columnOf(double left) {
      final x = isRtl
          ? host.gridWidth - padding.right - columnWidth - left
          : left - padding.left;
      return (x / stride).round();
    }

    final canonicalColumn = columnOf(canonicalRect.left);
    final desiredLeft =
        host.globalToGridLocal(focalGlobal).dx - fraction.dx * columnWidth;
    final targetColumn = columnOf(desiredLeft).clamp(0, count - 1);
    return (targetColumn - canonicalColumn) % count;
  }

  /// Solves the full grid at [count] columns from the last known heights,
  /// without re-laying-out children. Stamps this count's cell offsets from
  /// [cellOffsets] (the SAME store the render solve reads — the anti-
  /// oscillation invariant) unless [canonical] forces offset-0 (used by the
  /// delta chooser to find the anchor's canonical column).
  GridLayoutResult _solveCountLayout(
    GridHost host,
    int count, {
    bool canonical = false,
  }) {
    final heights =
        host.itemHeightsForColumns(count) ??
        host.nearestItemHeightsForColumns(count);
    return computeMasonryLayout(
      _specFor(
        host.gridWidth,
        crossAxisCount: count,
        sections: [
          for (final section in view.sections)
            GridSectionSpec(
              id: section.id,
              items: [
                for (final item in section.items)
                  GridItemSpec(
                    id: view.idOf(item),
                    height: heights[view.idOf(item)] ?? 0,
                  ),
              ],
              headerHeight:
                  host.headerHeightOf(section.id) *
                  (1 - animator.collapseOf(section.id)),
              footerHeight:
                  host.footerHeightOf(section.id) *
                  (1 - animator.collapseOf(section.id)),
              leadingCells: canonical ? 0 : cellOffsets.of(count, section.id),
            ),
        ],
      ),
    );
  }

  /// Predicts the grid layout at [zoom] from the last known heights, without
  /// re-laying-out children. Heights are keyed by column count, so a pair
  /// rollover between layouts still feeds each solve the right measurements.
  GridLayoutResult? _predictLayout(GridHost host, double zoom) {
    if (host.lastLayout == null) return null;

    // The same neighbor pair and span-normalized t as the render solve, or the
    // anchor-scroll correction would predict a different layout than the one
    // painted — a visible oscillation under the fingers.
    final neighbors = levelNeighbors(zoom, view.zoomConfig?.zoomLevels);
    final low = neighbors.low;
    final high = neighbors.high;
    final t = neighbors.t;

    final lowHeights = host.itemHeightsForColumns(low);
    final highHeights = host.itemHeightsForColumns(high);
    final dominantMeasured = t < 0.5 ? lowHeights != null : highHeights != null;
    if (!dominantMeasured) return null;

    final lowLayout = _solveCountLayout(host, low);
    if (low == high) return lowLayout;
    return lerpGridLayoutResult(lowLayout, _solveCountLayout(host, high), t);
  }

  /// Pins the anchor point to [focalGlobal] on the y axis only, by adjusting
  /// the ancestor scroll. The x axis is not pinned to the fingers — the photos
  /// canvases expand about the frozen [GridHost.zoomFocalX] instead, so the
  /// grid never slides horizontally during a zoom.
  void _anchorScroll({
    required GridHost host,
    required Object anchorId,
    required Offset fraction,
    required Offset focalGlobal,
    required double zoom,
  }) {
    final rect = _predictLayout(host, zoom)?.itemRects[anchorId];
    // Skip the frame on a transient prediction failure rather than snapping.
    if (rect == null) return;

    final scrollable = _scrollable;
    if (scrollable == null) return;

    final predictedLocalY = rect.top + rect.height * fraction.dy;
    final predictedGlobalY = host
        .gridLocalToGlobal(Offset(0, predictedLocalY))
        .dy;

    final position = scrollable.position;
    final target = (position.pixels + (predictedGlobalY - focalGlobal.dy))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() > 0.01) {
      position.jumpTo(target);
    }
  }

  void onScaleEnd(ScaleEndDetails details) =>
      _endPinch(scaleVelocity: details.scaleVelocity);

  void _endPinch({required double scaleVelocity}) {
    final pinch = _pinch;
    final config = view.zoomConfig;
    final host = _host;
    if (pinch == null || config == null) return;

    final releaseZoom = animator.zoomLevel.value;
    final resolved = resolveZoomRelease(
      zoomLevel: releaseZoom,
      scaleVelocity: scaleVelocity,
      config: config,
      baseZoom: pinch.baseZoom,
    );

    animator
      ..zoomSessionActive = false
      ..zoomLevel.retarget(resolved.toDouble(), view.springs.zoomSettle);

    _settleFocal = host?.zoomAnchorId != null ? pinch.lastFocalGlobal : null;
    _pinch = null;

    if (resolved != pinch.baseCount) {
      _pendingCount = resolved;
      view.onCrossAxisCountChanged?.call(resolved);
    }

    _startTicker();
    view.requestRebuild();
  }
}

/// A pinch in flight: what count it started from, and the content width at the
/// time (a resize invalidates the cached geometry).
class _PinchSession {
  _PinchSession({
    required this.baseCount,
    required this.baseZoom,
    required this.contentWidth,
  });

  final int baseCount;
  final double baseZoom;
  final double contentWidth;

  /// The fingers' latest focal point (global). Its y drives the scroll
  /// pinning; its x only seeds the entry-offset chooser for entering counts.
  Offset? lastFocalGlobal;
}
