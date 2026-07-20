import 'package:fluid_grid/src/interaction/drag_start_listener.dart';
import 'package:fluid_grid/src/interaction/two_finger_scale_gesture_recognizer.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:fluid_grid/src/model/grid_reorder_result.dart';
import 'package:fluid_grid/src/model/grid_section.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:fluid_grid/src/model/grid_zoom_config.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:fluid_grid/src/widget/fluid_grid_state_base.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Builds the widget shown for an item while it is held by the pointer.
typedef LiftedItemBuilder<T> =
    Widget Function(BuildContext context, T item, Widget child);

/// A masonry grid whose items animate implicitly and can be dragged to reorder,
/// including from one section into another.
///
/// The grid is not lazy: every item is laid out on every pass. That keeps the
/// geometry exact — heights are measured rather than estimated — at the cost of
/// scaling. It is intended for collections in the tens, not thousands. For a
/// lazy, scrollable variant that supports large collections, use
/// `SliverFluidGrid` inside a `CustomScrollView`.
///
/// The widget is uncontrolled: dropping an item reports the new ordering
/// through [onReorderFinished] and expects the caller to feed that ordering
/// back in as [sections]. Until the caller does, the drop position is held.
class FluidGrid<T> extends StatefulWidget implements FluidGridConfig<T> {
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

  /// How much the held item grows while lifted.
  final double liftScale;

  /// Speed of the autoscroll when the held item nears a viewport edge.
  @override
  final double autoScrollVelocityScalar;

  /// Enables pinch-to-zoom column switching. Null (the default) disables it and
  /// leaves the grid at [crossAxisCount].
  @override
  final GridZoomConfig? zoomConfig;

  /// Decorates the held item, e.g. with a shadow.
  final LiftedItemBuilder<T>? liftedBuilder;

  @override
  final void Function(T item)? onReorderStarted;
  @override
  final void Function(GridReorderResult<T> result)? onReorderFinished;
  @override
  final void Function(T item)? onReorderCanceled;

  /// Fired when a pinch settles on a new column count. Like reorder, the widget
  /// is uncontrolled: feed the reported count back in as [crossAxisCount].
  @override
  final ValueChanged<int>? onCrossAxisCountChanged;

  @override
  State<FluidGrid<T>> createState() => _FluidGridState<T>();
}

class _FluidGridState<T> extends State<FluidGrid<T>>
    with SingleTickerProviderStateMixin, FluidGridStateBase<T, FluidGrid<T>> {
  @override
  FluidGridConfig<T> get config => widget;

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final drag = coordinator.drag;
    final (:orderById, :zoomBuild) = prepareBuild();
    final overlaySlot = zoomBuild.primarySlot == ZoomSlot.low
        ? ZoomSlot.high
        : ZoomSlot.low;

    final children = <Widget>[
      // Painted first so a fading item never covers a live one.
      for (final ghost in coordinator.ghosts)
        GridChild(
          key: ValueKey(('ghost', ghost.id)),
          id: ghost.id,
          sectionId: const Object(),
          role: GridChildRole.ghost,
          ghostSize: ghost.size,
          child: IgnorePointer(child: widget.itemBuilder(context, ghost.item)),
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
        final item = coordinator.itemFor(id);
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
            child: DragStartListener(
              enabled: widget.reorderEnabled,
              delay: widget.dragStartDelay,
              onStart: (position) => coordinator.onDragStart(id, position),
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
                child: ExcludeSemantics(
                  child: widget.itemBuilder(context, item),
                ),
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
      key: bodyKey,
      animator: coordinator.animator,
      cellOffsets: coordinator.cellOffsets,
      sectionConfigs: [
        for (final section in widget.sections)
          SectionLayoutConfig(
            id: section.id,
            collapseWhenEmpty: section.collapseWhenEmpty,
            emptyDropExtent: section.emptyDropExtent,
          ),
      ],
      crossAxisCount: coordinator.effectiveCrossAxisCount,
      crossAxisSpacing: widget.crossAxisSpacing,
      mainAxisSpacing: widget.mainAxisSpacing,
      padding: widget.padding.resolve(Directionality.of(context)),
      textDirection: Directionality.of(context),
      isDragging: coordinator.isDragging,
      liftScale: widget.liftScale,
      zoomStyle: widget.zoomConfig?.style ?? GridZoomStyle.morph,
      zoomLevels: widget.zoomConfig?.zoomLevels,
      children: children,
    );

    if (widget.zoomConfig == null) return body;
    return _wrapWithPinch(body);
  }

  Widget _wrapWithPinch(Widget body) => Listener(
    onPointerDown: (_) => coordinator.onPointerDown(),
    onPointerUp: (_) => coordinator.onPointerUp(),
    onPointerCancel: (_) => coordinator.onPointerUp(),
    child: RawGestureDetector(
      gestures: {
        TwoFingerScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              TwoFingerScaleGestureRecognizer
            >(
              () => TwoFingerScaleGestureRecognizer(
                canStart: coordinator.canStartPinch,
              ),
              (instance) => instance
                ..onStart = coordinator.onScaleStart
                ..onUpdate = coordinator.onScaleUpdate
                ..onEnd = coordinator.onScaleEnd,
            ),
      },
      // Let the item drag recognizers and the ancestor scrollable also see the
      // pointers; the scale recognizer only wins for a real two-finger pinch.
      behavior: HitTestBehavior.translucent,
      child: body,
    ),
  );
}
