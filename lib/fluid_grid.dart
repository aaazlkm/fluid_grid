/// A sectioned, reorderable, implicitly animated masonry grid.
///
/// Items are laid out in a masonry (shortest-column) grid, grouped into
/// sections that may carry a header and a footer. Items animate to their
/// positions with springs, and can be dragged to reorder — including across
/// section boundaries.
///
/// With a `GridZoomConfig`, a two-finger pinch morphs the grid continuously
/// between column counts, iOS-Photos style, keeping the content under the
/// fingers in place and settling to the nearest count on release.
library;

export 'src/fluid_grid.dart' show FluidGrid;
export 'src/model/grid_item_height.dart'
    show
        GridItemHeight,
        GridItemHeightBuilder,
        GridItemHeightMeasured,
        ItemHeightBuilder;
export 'src/model/grid_reorder_result.dart'
    show GridReorderResult, GridSectionItems;
export 'src/model/grid_section.dart' show GridSection;
export 'src/model/grid_springs.dart' show GridSprings;
export 'src/model/grid_zoom_config.dart' show GridZoomConfig;
export 'src/model/grid_zoom_style.dart' show GridZoomStyle;
export 'src/sliver_fluid_grid.dart' show SliverFluidGrid;
