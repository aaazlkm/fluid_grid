## Unreleased

- Add `GridZoomConfig.switchThreshold` — how far a gentle pinch must drag toward
  a neighbouring column count before releasing commits to it, as a fraction of
  one level-step measured from the starting count. Directional and symmetric in
  both zoom directions. Defaults to 0.1 (eager — one tenth of a step commits);
  0.5 is the classic snap-to-nearest, and 1.0 requires dragging all the way onto
  the next level. Flings still commit one step regardless.
- `GridZoomStyle.morph` now dissolves through a Gaussian blur: each crossfade
  rendition is blurred in proportion to its transparency, so the transition
  softens as content swaps and re-sharpens crisply at both resting levels.
- The photos-style zoom now expands about the initial pinch point: the frozen
  focal x is the horizontal fixed point of both crossfade canvases (they were
  previously anchored on the pinched tile, whose position shift between the two
  layouts translated the whole grid sideways during a morph). The zoom reads as
  a pure expansion/contraction under the fingers with zero horizontal drift,
  the covering canvas structurally always spans the viewport (no blank edge
  strips, no pan clamp), and every resting level is pixel-flush. Vertical
  behavior is unchanged (tile-anchored, scroll-pinned). Programmatic
  `crossAxisCount` morphs expand about the viewport centre.
- The photos style still re-anchors the grid around the pinched tile, matching
  iOS: the incoming layout is shifted by whole cells so the tile lands in the
  cell nearest the fingers instead of sweeping to its index-determined column,
  and the shift persists in the resting layout (blank leading cells, trailing
  partial row — like the Photos app). The cell is chosen once, as the pinch
  begins, and held for the gesture (no mid-pinch re-flow, so the grid never
  snaps sideways). Reorder drops resolve against the shifted layout; a
  programmatic `crossAxisCount` change returns to the canonical layout. Adds
  `GridSectionSpec.leadingCells` to the layout solver.
- Add `GridZoomConfig.zoomLevels` — restrict the pinch to a fixed set of column
  counts, iOS-Photos style (e.g. `[1, 3, 5, 9]`): the gesture morphs only
  between adjacent levels, the release snaps to the nearest level, and a fling
  commits one level in its direction.
- Add `GridZoomStyle.photos` — the iOS Photos zoom transition: the two endpoint
  grids crossfade as rigid canvases scale-anchored at the pinch focal point.
  The incoming grid paints fully rendered underneath while the outgoing one
  fades out on top, so newly visible tiles slide in from the screen edges
  already rendered and on-screen positions swap content with a fade.
- Add `SliverFluidGrid`, a fully lazy sliver variant of `FluidGrid` for use in
  a `CustomScrollView`. It builds only the tiles near the viewport, so it scales
  to thousands of items, while keeping full parity with the box grid: spring
  reflow, drag-to-reorder across sections (with edge autoscroll), and all three
  pinch-to-zoom styles.
- `SliverFluidGrid` takes its heights through a sealed `GridItemHeight<T>`
  strategy: `GridItemHeight.builder((item, width) => height)` computes heights
  up front for an exact scroll extent and positions, while
  `GridItemHeight.measured()` measures heights from the rendered content
  (estimating never-visited items with a self-correcting running average) for
  intrinsically sized tiles.
- The reorder solver (`resolveInsertion`) is now linear in the item count
  instead of quadratic, so drag stays responsive in large collections.
- Add `GridZoomStyle` to choose how items are rendered during a pinch morph:
  `morph` (the default travelling per-item crossfade) and `photos` (the iOS
  Photos rigid-canvas crossfade).
- **Breaking:** `GridZoomConfig.crossfade` (bool) is replaced by
  `GridZoomConfig.style` (`GridZoomStyle`). `crossfade: true` → `style:
  GridZoomStyle.morph` (the default).

## 0.1.0

Initial release.

- Sectioned masonry grid with a single-pass, measured (non-estimated) layout.
- Spring-driven implicit animation with velocity-preserving retargeting.
- Drag to reorder, including across section boundaries.
- iOS-Photos-style pinch-to-zoom that morphs continuously between column
  counts, keeps the point under the fingers in place, and settles to the
  nearest count on release.
- Photos-style square-grid example app.
