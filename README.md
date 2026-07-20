# fluid_grid

A sectioned, reorderable, implicitly animated masonry grid with spring-driven motion.

Think `implicitly_animated_reorderable_list`, but a grid: variable-height cards packed into
columns, grouped into sections, draggable **across** section boundaries, and animated with
springs rather than fixed-duration curves.

A runnable **Photos-style square-grid demo** (pinch to zoom, drag to reorder) lives in
[`example/`](example/) — `cd example && fvm flutter run`.

## Usage

```dart
FluidGrid<Category>(
  idOf: (category) => category.id,
  crossAxisCount: 2,
  crossAxisSpacing: 8,
  mainAxisSpacing: 8,
  padding: const EdgeInsets.symmetric(horizontal: 16),
  sections: [
    GridSection(
      id: 'pinned',
      items: pinnedCategories,
      header: const PinnedHeader(),
      collapseWhenEmpty: true,
    ),
    GridSection(id: 'unpinned', items: unpinnedCategories),
  ],
  itemBuilder: (context, category) => CategoryCard(category),
  onReorderFinished: (result) => viewModel.reorder(
    pinned: result.itemsOf('pinned'),
    unpinned: result.itemsOf('unpinned'),
  ),
)
```

The widget needs a scrollable ancestor (it sizes itself to its content and does not scroll),
which is also what it uses to autoscroll while you drag near a viewport edge.

## Pinch to zoom

Pass a `GridZoomConfig` to let a two-finger pinch change the column count, iOS-Photos style:

```dart
FluidGrid<Category>(
  crossAxisCount: columnCount,             // the source of truth
  zoomConfig: const GridZoomConfig(minCrossAxisCount: 1, maxCrossAxisCount: 4),
  onCrossAxisCountChanged: (count) => viewModel.setColumnCount(count),
  // ...
)
```

Like reorder, this is uncontrolled: the pinch settles and reports the new count through
`onCrossAxisCountChanged`; feed it back in as `crossAxisCount`. Leaving `zoomConfig` null (the
default) disables the gesture entirely — a grid built without it behaves exactly as before.

**During the gesture** the grid morphs continuously between the two nearest column counts rather
than snapping — cards follow the fingers 1:1 and the point under the fingers stays put (the grid
adjusts its ancestor scroll offset each frame). One finger still scrolls the list; a long-press
still starts a reorder; the two never fire at once.

**Discrete zoom levels.** iOS Photos doesn't stop at every column count — it steps through a
fixed set (1, 3, 5, …). Pass `zoomLevels` to get the same behavior:

```dart
zoomConfig: const GridZoomConfig(zoomLevels: [1, 3, 5, 9], style: GridZoomStyle.photos),
```

With levels, the pinch morphs only between **adjacent** levels (a zoom passing "4 columns" is
mid-blend between the 3- and 5-column layouts, never a 4-column layout), the release snaps to the
nearest level, and a fling commits one level in its direction. `minCrossAxisCount`/
`maxCrossAxisCount` are superseded; `crossAxisCount` must be one of the levels.

### How the zoom works

**Column morph.** There is no fractional column layout — masonry needs an integer column count.
So a pinch at a fractional zoom `z` solves the layout at the two adjacent resting counts (the
neighbouring `zoomLevels` when provided, else `floor(z)` and `ceil(z)`) and lerps the two
results. The endpoints are exact (`z` on a level → one solve, byte-identical to a plain grid);
the middle is a smooth blend. A dedicated `zoomLevel` spring channel drives the gesture and the
release settle, reusing the same velocity-preserving retarget as everything else.

**Zoom style.** `GridZoomConfig.style` picks how each item's two endpoint renderings are placed
and blended during the morph. All modes lerp the grid's total height and keep the pinched
content anchored under the fingers; they differ only in the tiles.

*`GridZoomStyle.morph` (default) — the travelling crossfade.* While the zoom is in flight every
item is rendered **twice**, once at each endpoint's exact column width, and **both renditions ride
the item's own interpolated rect**, scaled to the interpolated width — the pair coincides, so
every tile reads as one element travelling from its old slot to its new slot while its content
crossfades between the two renderings. The source and destination of each photo visibly overlap
mid-morph instead of two grids sliding across each other. The **incoming** rendition paints
beneath and ramps to solid
within the first fifth of the morph, while the **outgoing** one ghosts out linearly above it the
whole way — so the new rendering materialises early with the old one dissolving in place over it.
Each rendition also **dissolves through a Gaussian blur** proportional to its own transparency, so
the content visibly softens as it swaps and re-sharpens crisply at each resting level.
Each coinciding pair stays near-opaque at every point, so the background never washes through; both
fades are pure functions of the morph position, so a reversed pinch scrubs back through the same
frames; and each endpoint paints exactly one rendition, solid and direct, so entering, leaving,
and the settle are pixel-identical. Because each copy is laid out only when the integer pair
changes (not per frame), text never re-wraps mid-gesture. The moment the morph settles the item
springs take over at exactly the pixels the copies were painting — no hand-off jump even on a fast
release.

*`GridZoomStyle.photos` — the iOS Photos transition.* The two endpoint grids crossfade as **rigid
canvases**, each scale-anchored at the pinch focal point so tile sizes track the fingers. The
incoming grid is fully laid out and painted (solid almost immediately) *underneath*, while the
outgoing grid fades out on top. Items do not travel to their new masonry slot — the same screen
position simply swaps content with a fade — and newly visible items slide in from the screen edges
**already fully rendered**, because they are part of the incoming canvas settling into place.
Pairs naturally with `zoomLevels` (this is exactly what Photos does at its 1/3/5-column detents).

> **Async image content:** the incoming canvas is a freshly-built copy of every tile, so if your
> tiles decode images asynchronously, keep them cheap to re-obtain during the morph. Request a
> **fixed** decode size (so the incoming copy is a cache hit, not a new decode) and give
> `PaintingBinding.instance.imageCache` enough room to hold the dense visible set — otherwise the
> morph evicts and re-decodes, and tiles flash their placeholder. The device-photos example does
> both.

The photos style also **re-anchors the grid around the pinched tile**, again matching iOS. A
masonry layout normally fixes each item's column by its index, so a tile that sits at the right
edge at 4 columns but the left edge at 3 would sweep across the screen on every zoom. Instead, the
incoming layout is shifted by whole cells so the pinched tile lands in the cell nearest the
fingers, and that shift **persists in the resting layout**: the section may show blank leading
cells and a trailing partial row, exactly like the Photos app. The target cell is **chosen once,
as the pinch begins, and held for the gesture**: sliding the fingers sideways mid-pinch does not
re-flow the grid, so the tile never snaps to a different column under them. The offset survives
scrolling and data updates, and decays back to the canonical layout on the next programmatic
`crossAxisCount` change.

Both modes float section headers **above** the tiles, clip mid-gesture paint to the grid's own
bounds, and carry a contract on `itemBuilder`: item content is instantiated twice for a few hundred
milliseconds, so it must not contain GlobalKeys, Heroes, or single-subscription stream listens
(broadcast streams are fine). The transient copy is pointer- and semantics-transparent, and the
element on the committed side always survives the morph.

**Two-finger-only gesture.** A `ScaleGestureRecognizer` normally claims the arena on a one-finger
pan too, which would steal single-finger scrolling. A subclass declines the arena claim while
fewer than two pointers are down, so one finger always scrolls and only a real pinch zooms — the
same arena dynamic that lets `InteractiveViewer` pinch inside a list.

## Large collections: `SliverFluidGrid`

`FluidGrid` lays out every item on every pass, which keeps its geometry exact but caps it at
collections in the tens. For large collections, use **`SliverFluidGrid`** inside a
`CustomScrollView`. It is a true, **fully lazy** sliver: only the tiles whose (animated) position
intersects the cache window are built, laid out, and painted, so it scales to thousands of items
while keeping every interaction — spring reflow, drag-to-reorder across sections, and iOS-Photos
pinch-to-zoom in both styles.

```dart
CustomScrollView(
  slivers: [
    const SliverAppBar(title: Text('Library'), floating: true),
    SliverFluidGrid<Photo>(
      idOf: (photo) => photo.id,
      crossAxisCount: columnCount,
      zoomConfig: const GridZoomConfig(minCrossAxisCount: 1, maxCrossAxisCount: 12),
      onCrossAxisCountChanged: (count) => viewModel.setColumnCount(count),
      onReorderFinished: (result) => viewModel.reorder(result),
      // The one addition over FluidGrid: where heights come from.
      itemHeight: GridItemHeight.builder((photo, itemWidth) => itemWidth), // square tiles
      sections: [for (final s in sections) GridSection(id: s.id, items: s.photos)],
      itemBuilder: (context, photo) => PhotoTile(photo),
    ),
  ],
)
```

The one addition over `FluidGrid` is **`itemHeight`**, a sealed strategy with two options:

- **`GridItemHeight.builder((item, itemWidth) => height)`** — *exact*. Heights are pure data, so
  the masonry solver runs over the whole collection (giving an exact scroll extent and exact
  positions) without building a single offscreen child. Children are laid out at tight constraints
  of exactly that height, so — like `SliverFixedExtentList` — a wrong height overflows the tile
  rather than corrupting the layout. Use it whenever heights are computable up front (fixed
  aspect-ratio tiles, known dimensions).

- **`const GridItemHeight.measured()`** — *measured*, for intrinsically sized content (text cards,
  anything you'd rather not size by hand). Tiles near the viewport are built and their real rendered
  height measured and cached; items that have never been visited use a running-average estimate that
  self-corrects as they scroll in. The trade-off is that the scroll extent is approximate until
  content has been visited, exactly like `SliverList` with estimated extents — scrolling up through
  never-visited territory can shift content slightly as estimates resolve.

Section headers and footers keep the plain `Widget` API of `GridSection`; there are few of them, so
they are always built and measured in both modes.

Everything else matches `FluidGrid`: the same uncontrolled contract (echo `onReorderFinished` /
`onCrossAxisCountChanged` back in), the same `GridZoomConfig` / `GridZoomStyle`, the same springs.
The grid must be a direct child of a vertical `CustomScrollView`. The runnable
[`example/`](example/) has both variants — the toolbar's grid icon opens the lazy sliver gallery.

## Behaviour

**Uncontrolled.** Dropping an item reports the new ordering through `onReorderFinished` and
expects the caller to feed that ordering back in as `sections`. The drop position is held until
the caller does, so an optimistic state update produces no visual jump.

**Sections own pin-like semantics, not the grid.** The result carries `fromSectionId` and
`toSectionId`; deciding what "moved into the pinned section" *means* is the caller's job.

**Empty sections stay droppable.** A section with `collapseWhenEmpty: true` animates its header
and footer to zero extent when it empties — except during a drag, when it re-expands and reserves
`emptyDropExtent` so you can drop into it.

## Design

- **One layout pass, no estimation.** A custom `RenderBox` lays each child out at its column
  width, reads the measured height, runs the masonry solver, and sizes itself exactly. The first
  frame is already correct: no flicker, no post-frame measurement, correct scroll extent
  immediately. The cost is that the grid is **not lazy** — every item is laid out every pass.
  Intended for collections in the tens; past a few hundred, reach for `SliverFluidGrid`, which
  keeps the same solver and springs but drives the height from a callback so it can build only the
  visible window (see above).

- **Springs, stepped by hand.** Each item owns two scalar spring channels (x, y). Retargeting
  mid-flight restarts the simulation from the current position *and velocity*, so an interrupted
  animation carries its momentum into the new target. This is why the package drives
  `SpringSimulation` directly rather than using `AnimationController.animateWith`, whose unitless
  0..1 domain cannot express a velocity handoff between two different targets — and during a drag
  the target changes many times per second. A single `Ticker` advances every channel and marks
  the render object for repaint; springs never trigger relayout.

- **No diffing algorithm.** Items are keyed by a caller-supplied id and the grid is non-lazy, so
  reconciliation is set arithmetic: survivors spring to new slots, arrivals fade in, departures
  become ghosts pinned at their last rect. A Myers diff exists to recover an edit script *without*
  identity; with identity it buys nothing.

- **Drop targets found by replaying the solver.** Masonry has no usable inverse from position to
  index — inserting at index `k` reshuffles the column assignment of everything after it, so
  "which card am I over, before or after its midpoint" picks slots the item would never land in.
  Instead every candidate `(section, index)` is evaluated by running the real solver on that
  hypothetical ordering and measuring where the dragged item would end up; the nearest wins, with
  hysteresis to stop it flapping between near-equidistant slots. Cross-section drops and empty
  sections need no special case. At these item counts it is a few thousand float operations per
  frame, and it is exact.

- **Gestures via `DelayedMultiDragGestureRecognizer`**, the same mechanism behind Flutter's
  `ReorderableDelayedDragStartListener`. It joins the gesture arena, so it loses cleanly to an
  ancestor scrollable if the user scrolls first, and to a tap recognizer if they release first.

## Limitations

- Not lazy; see above.
- Reordering is drag-only, so it is not reachable by switch or screen-reader users. Semantic
  reorder actions are a known gap.
- A width change mid-drag (rotation, resize) cancels the drag rather than trying to remap stale
  geometry.
