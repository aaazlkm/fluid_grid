import 'package:fluid_grid/src/interaction/fluid_grid_coordinator.dart';
import 'package:fluid_grid/src/interaction/fluid_grid_view.dart';
import 'package:fluid_grid/src/layout/grid_render_host.dart';
import 'package:fluid_grid/src/model/grid_reorder_result.dart';
import 'package:fluid_grid/src/model/grid_section.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:fluid_grid/src/model/grid_zoom_config.dart';
import 'package:flutter/widgets.dart';

/// Matches `SliverReorderableList`'s autoscroll speed.
const double kDefaultAutoScrollVelocityScalar = 50;

/// The configuration surface `FluidGrid` and `SliverFluidGrid` share. Both
/// widget classes implement it (every member is one of their fields), which
/// lets [FluidGridStateBase] forward [FluidGridView] to either widget without
/// knowing which one it is. Not exported: implementing it changes no public
/// API.
abstract interface class FluidGridConfig<T> {
  List<GridSection<T>> get sections;
  Object Function(T item) get idOf;
  GridSprings get springs;
  int get crossAxisCount;
  double get crossAxisSpacing;
  double get mainAxisSpacing;
  EdgeInsetsGeometry get padding;
  bool get reorderEnabled;
  double get autoScrollVelocityScalar;
  GridZoomConfig? get zoomConfig;
  void Function(T item)? get onReorderStarted;
  void Function(GridReorderResult<T> result)? get onReorderFinished;
  void Function(T item)? get onReorderCanceled;
  ValueChanged<int>? get onCrossAxisCountChanged;
}

/// Everything a grid State does identically for the box and sliver variants:
/// forwarding [FluidGridView] to the widget's configuration, owning the
/// coordinator and the render body's key, and the shared lifecycle. Each State
/// keeps only its own `build` and pinch wiring.
mixin FluidGridStateBase<T, W extends StatefulWidget>
    on State<W>, SingleTickerProviderStateMixin<W>
    implements FluidGridView<T> {
  /// The hosting widget's configuration (each State returns its `widget`).
  @protected
  FluidGridConfig<T> get config;

  @protected
  final GlobalKey bodyKey = GlobalKey();

  @protected
  late final FluidGridCoordinator<T> coordinator;

  // --- FluidGridView: configuration, straight from the widget ---

  @override
  List<GridSection<T>> get sections => config.sections;
  @override
  Object Function(T item) get idOf => config.idOf;
  @override
  GridSprings get springs => config.springs;
  @override
  int get crossAxisCount => config.crossAxisCount;
  @override
  double get crossAxisSpacing => config.crossAxisSpacing;
  @override
  double get mainAxisSpacing => config.mainAxisSpacing;
  @override
  EdgeInsets get resolvedPadding =>
      config.padding.resolve(Directionality.of(context));
  @override
  TextDirection get textDirection => Directionality.of(context);
  @override
  bool get reorderEnabled => config.reorderEnabled;
  @override
  double get autoScrollVelocityScalar => config.autoScrollVelocityScalar;
  @override
  GridZoomConfig? get zoomConfig => config.zoomConfig;
  @override
  void Function(T item)? get onReorderStarted => config.onReorderStarted;
  @override
  void Function(GridReorderResult<T> result)? get onReorderFinished =>
      config.onReorderFinished;
  @override
  void Function(T item)? get onReorderCanceled => config.onReorderCanceled;
  @override
  ValueChanged<int>? get onCrossAxisCountChanged =>
      config.onCrossAxisCountChanged;

  @override
  GridHost? get host => bodyKey.currentContext?.findRenderObject() as GridHost?;

  @override
  void requestRebuild() {
    if (mounted) setState(() {});
  }

  @override
  bool get isMounted => mounted;

  // --- Lifecycle ---

  @override
  void initState() {
    super.initState();
    assert(
      config.zoomConfig?.debugZoomLevelsValid ?? true,
      'zoomLevels must be non-empty, strictly ascending, and every value >= 1',
    );
    assert(
      config.zoomConfig == null ||
          (config.zoomConfig!.zoomLevels != null
              ? config.zoomConfig!.zoomLevels!.contains(config.crossAxisCount)
              : (config.crossAxisCount >=
                        config.zoomConfig!.minCrossAxisCount &&
                    config.crossAxisCount <=
                        config.zoomConfig!.maxCrossAxisCount)),
      config.zoomConfig?.zoomLevels != null
          ? 'crossAxisCount must be one of the zoomLevels'
          : 'crossAxisCount must be within '
                '[minCrossAxisCount, maxCrossAxisCount]',
    );
    coordinator = FluidGridCoordinator<T>(view: this, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    coordinator.attachScrollable(Scrollable.maybeOf(context));
  }

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);
    coordinator.didUpdateWidget();
  }

  @override
  void dispose() {
    coordinator.dispose();
    super.dispose();
  }

  // --- Build head ---

  /// The shared start of both builds: the display order keyed by section id,
  /// and the crossfade shape this frame will build, stamped as built.
  @protected
  ({Map<Object, List<Object>> orderById, ZoomBuild zoomBuild}) prepareBuild() {
    final order = coordinator.displayOrder();
    final orderById = {
      for (final section in order) section.id: section.itemIds,
    };

    // During a crossfade every item is emitted twice: the primary copy renders
    // the committed-count side of the morph, the overlay copy the other side.
    final zoomBuild = coordinator.expectedZoomBuild();
    coordinator.builtZoom = zoomBuild;
    return (orderById: orderById, zoomBuild: zoomBuild);
  }
}
