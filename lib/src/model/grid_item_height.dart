/// The natural height of an item laid out at a given column width. Used by the
/// exact height strategy, [GridItemHeight.builder].
typedef ItemHeightBuilder<T> = double Function(T item, double itemWidth);

/// How `SliverFluidGrid` learns each item's height.
///
/// Sealed, so callers pick a strategy with an exhaustive switch and the grid can
/// branch on it internally. Two strategies exist:
///
/// - [GridItemHeight.builder] — **exact**: heights are computed up front from
///   data, so the masonry solver runs over the whole collection without building
///   a single offscreen child. The scroll extent and every position are exact
///   from the first frame.
/// - [GridItemHeight.measured] — **measured**: heights come from the actual
///   rendered content. Items near the viewport are measured and cached; items
///   that have never been visited use a running-average estimate that
///   self-corrects as they scroll in, so the scroll extent is approximate until
///   content has been visited (like `SliverList` with estimated extents).
sealed class GridItemHeight<T> {
  const GridItemHeight();

  /// Exact heights, computed up front from data. See [GridItemHeight].
  const factory GridItemHeight.builder(ItemHeightBuilder<T> heightOf) = GridItemHeightBuilder<T>;

  /// Heights measured from the rendered content. See [GridItemHeight].
  const factory GridItemHeight.measured() = GridItemHeightMeasured<T>;
}

/// The exact strategy: [heightOf] supplies each item's height. See
/// [GridItemHeight.builder].
final class GridItemHeightBuilder<T> extends GridItemHeight<T> {
  const GridItemHeightBuilder(this.heightOf);

  final ItemHeightBuilder<T> heightOf;
}

/// The measured strategy. See [GridItemHeight.measured].
final class GridItemHeightMeasured<T> extends GridItemHeight<T> {
  const GridItemHeightMeasured();
}
