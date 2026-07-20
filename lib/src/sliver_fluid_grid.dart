import 'package:fluid_grid/src/fluid_grid.dart' show LiftedItemBuilder;
import 'package:fluid_grid/src/interaction/drag_start_listener.dart';
import 'package:fluid_grid/src/interaction/two_finger_scale_gesture_recognizer.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:fluid_grid/src/model/grid_item_height.dart';
import 'package:fluid_grid/src/model/grid_reorder_result.dart';
import 'package:fluid_grid/src/model/grid_section.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:fluid_grid/src/model/grid_zoom_config.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:fluid_grid/src/widget/fluid_grid_state_base.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// A fully lazy, sliver version of `FluidGrid` for use inside a
/// [CustomScrollView].
///
/// Unlike `FluidGrid` — which lays out every child on every pass and is meant
/// for collections in the tens — `SliverFluidGrid` builds only the children
/// whose (animated) position intersects the cache window, so it scales to
/// thousands of items. Heights come from [itemHeight]: either computed up front
/// from data ([GridItemHeight.builder], exact) or measured from the rendered
/// content ([GridItemHeight.measured]).
///
/// It supports the same reorder and pinch-zoom interactions as the box grid.
/// Place it directly in [CustomScrollView.slivers]; it must be a vertical
/// scroll view. Section headers and footers are always built (there are few of
/// them) and measured, so they keep the plain `Widget` API of [GridSection].
///
/// The widget is uncontrolled, exactly like `FluidGrid`: feed [onReorderFinished]
/// and [onCrossAxisCountChanged] back in as [sections] / [crossAxisCount].
class SliverFluidGrid<T> extends StatefulWidget implements FluidGridConfig<T> {
  const SliverFluidGrid({
    required this.sections,
    required this.idOf,
    required this.itemBuilder,
    required this.itemHeight,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.padding = EdgeInsets.zero,
    this.springs = const GridSprings(),
    this.reorderEnabled = true,
    this.dragStartDelay = kLongPressTimeout,
    this.liftScale = 1.03,
    this.autoScrollVelocityScalar = kDefaultAutoScrollVelocityScalar,
    this.zoomConfig,
    this.liftedBuilder,
    this.onReorderStarted,
    this.onReorderFinished,
    this.onReorderCanceled,
    this.onCrossAxisCountChanged,
    super.key,
  }) : assert(crossAxisCount > 0, 'crossAxisCount must be positive');

  @override
  final List<GridSection<T>> sections;

  /// Stable identity for an item. Must be unique across every section.
  @override
  final Object Function(T item) idOf;

  final Widget Function(BuildContext context, T item) itemBuilder;

  /// How the grid learns each item's height.
  ///
  /// [GridItemHeight.builder] supplies heights up front from data (exact scroll
  /// extent and positions, no estimation); with it, children are given tight
  /// constraints of exactly the returned height, so a mismatch overflows the
  /// tile rather than corrupting the layout. [GridItemHeight.measured] measures
  /// heights from the rendered content instead, at the cost of an approximate
  /// scroll extent until content has been visited. See [GridItemHeight].
  final GridItemHeight<T> itemHeight;

  @override
  final int crossAxisCount;
  @override
  final double crossAxisSpacing;
  @override
  final double mainAxisSpacing;
  @override
  final EdgeInsetsGeometry padding;
  @override
  final GridSprings springs;

  @override
  final bool reorderEnabled;
  final Duration dragStartDelay;
  final double liftScale;
  @override
  final double autoScrollVelocityScalar;
  @override
  final GridZoomConfig? zoomConfig;
  final LiftedItemBuilder<T>? liftedBuilder;

  @override
  final void Function(T item)? onReorderStarted;
  @override
  final void Function(GridReorderResult<T> result)? onReorderFinished;
  @override
  final void Function(T item)? onReorderCanceled;
  @override
  final ValueChanged<int>? onCrossAxisCountChanged;

  @override
  State<SliverFluidGrid<T>> createState() => _SliverFluidGridState<T>();
}

class _SliverFluidGridState<T> extends State<SliverFluidGrid<T>>
    with
        SingleTickerProviderStateMixin,
        FluidGridStateBase<T, SliverFluidGrid<T>> {
  late final TwoFingerScaleGestureRecognizer _pinchRecognizer;

  @override
  FluidGridConfig<T> get config => widget;

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    _pinchRecognizer =
        TwoFingerScaleGestureRecognizer(canStart: coordinator.canStartPinch)
          ..onStart = coordinator.onScaleStart
          ..onUpdate = coordinator.onScaleUpdate
          ..onEnd = coordinator.onScaleEnd;
  }

  @override
  void dispose() {
    _pinchRecognizer.dispose();
    super.dispose();
  }

  // --- Pinch pointer forwarding (a sliver cannot be wrapped in a detector) ---

  void _onPinchPointerDown(PointerDownEvent event) {
    coordinator.onPointerDown();
    _pinchRecognizer.addPointer(event);
  }

  void _onPinchPointerUp(PointerEvent event) => coordinator.onPointerUp();

  // --- Height callback (stable tearoff so the render object's cache is kept) ---

  double _itemHeightOf(Object id, double itemWidth) {
    final strategy = widget.itemHeight;
    if (strategy is! GridItemHeightBuilder<T>) return 0;
    final item = coordinator.itemFor(id);
    return item == null ? 0 : strategy.heightOf(item, itemWidth);
  }

  // --- Child builders ---

  Widget? _buildHeader(BuildContext context, Object sectionId) {
    for (final section in widget.sections) {
      if (section.id == sectionId) return section.header;
    }
    return null;
  }

  Widget? _buildFooter(BuildContext context, Object sectionId) {
    for (final section in widget.sections) {
      if (section.id == sectionId) return section.footer;
    }
    return null;
  }

  Widget _buildItem(BuildContext context, Object id) {
    final item = coordinator.itemFor(id);
    if (item == null) return const SizedBox.shrink();
    var child = widget.itemBuilder(context, item);
    if (coordinator.drag?.id == id && widget.liftedBuilder != null) {
      child = widget.liftedBuilder!(context, item, child);
    }
    return DragStartListener(
      enabled: widget.reorderEnabled,
      delay: widget.dragStartDelay,
      onStart: (position) => coordinator.onDragStart(id, position),
      child: child,
    );
  }

  Widget _buildOverlay(BuildContext context, Object id) {
    final item = coordinator.itemFor(id);
    if (item == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(child: widget.itemBuilder(context, item)),
    );
  }

  Widget _buildGhost(BuildContext context, Object id) {
    final item = coordinator.ghostItemFor(id);
    if (item == null) return const SizedBox.shrink();
    return IgnorePointer(child: widget.itemBuilder(context, item));
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final (:orderById, :zoomBuild) = prepareBuild();

    final sections = [
      for (final section in widget.sections)
        SliverSectionModel(
          id: section.id,
          itemIds: orderById[section.id] ?? const <Object>[],
          hasHeader: section.header != null,
          hasFooter: section.footer != null,
          collapseWhenEmpty: section.collapseWhenEmpty,
          emptyDropExtent: section.emptyDropExtent,
        ),
    ];

    return SliverMasonryGridBody(
      key: bodyKey,
      animator: coordinator.animator,
      cellOffsets: coordinator.cellOffsets,
      sections: sections,
      itemHeightOf: switch (widget.itemHeight) {
        GridItemHeightBuilder<T>() => _itemHeightOf,
        GridItemHeightMeasured<T>() => null,
      },
      ghostSizes: {
        for (final ghost in coordinator.ghosts) ghost.id: ghost.size,
      },
      crossAxisCount: coordinator.effectiveCrossAxisCount,
      crossAxisSpacing: widget.crossAxisSpacing,
      mainAxisSpacing: widget.mainAxisSpacing,
      padding: widget.padding.resolve(Directionality.of(context)),
      textDirection: Directionality.of(context),
      isDragging: coordinator.isDragging,
      liftScale: widget.liftScale,
      zoomStyle: widget.zoomConfig?.style ?? GridZoomStyle.morph,
      zoomLevels: widget.zoomConfig?.zoomLevels,
      dual: zoomBuild.dual,
      primarySlot: zoomBuild.primarySlot == ZoomSlot.none
          ? ZoomSlot.low
          : zoomBuild.primarySlot,
      contentRevision: 0,
      pinchEnabled: widget.zoomConfig != null,
      onPinchPointerDown: _onPinchPointerDown,
      onPinchPointerUp: _onPinchPointerUp,
      buildHeader: _buildHeader,
      buildFooter: _buildFooter,
      buildItem: _buildItem,
      buildOverlay: _buildOverlay,
      buildGhost: _buildGhost,
    );
  }
}
