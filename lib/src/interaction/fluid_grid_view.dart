import 'package:fluid_grid/src/layout/grid_render_host.dart';
import 'package:fluid_grid/src/layout/masonry_paint_math.dart';
import 'package:fluid_grid/src/model/grid_reorder_result.dart';
import 'package:fluid_grid/src/model/grid_section.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:fluid_grid/src/model/grid_zoom_config.dart';
import 'package:flutter/widgets.dart';

/// Whether the crossfade builds each item twice this frame, and which zoom slot
/// the primary (interactive, state-carrying) copy renders.
typedef ZoomBuild = ({bool dual, ZoomSlot primarySlot});

/// One removed item, still fading out.
class GridGhost<T> {
  const GridGhost({required this.item, required this.size});

  final T item;
  final Size size;
}

/// The seam between `FluidGridCoordinator` and whichever widget hosts it (the
/// box `FluidGrid` or the sliver `SliverFluidGrid`). The widget exposes its
/// current configuration (straight from its own fields), the render object as a
/// [GridHost], and a way to request a rebuild — nothing else. All of the drag /
/// pinch / ticker / reconcile logic then lives once, in the coordinator.
abstract interface class FluidGridView<T> {
  List<GridSection<T>> get sections;
  Object Function(T item) get idOf;
  GridSprings get springs;
  int get crossAxisCount;
  double get crossAxisSpacing;
  double get mainAxisSpacing;

  /// Padding already resolved against the ambient text direction.
  EdgeInsets get resolvedPadding;
  TextDirection get textDirection;

  bool get reorderEnabled;
  double get autoScrollVelocityScalar;
  GridZoomConfig? get zoomConfig;

  void Function(T item)? get onReorderStarted;
  void Function(GridReorderResult<T> result)? get onReorderFinished;
  void Function(T item)? get onReorderCanceled;
  ValueChanged<int>? get onCrossAxisCountChanged;

  /// The render object currently laying out the grid, or null before first
  /// layout / between mounts.
  GridHost? get host;

  /// Rebuild the hosting widget (its `build` reads the coordinator's read-model).
  void requestRebuild();

  bool get isMounted;
}
