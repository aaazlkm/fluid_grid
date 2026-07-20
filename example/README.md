# fluid_grid — Photos example

A photo-gallery demo for the `fluid_grid` package, styled after the
iOS Photos app:

- **Square tiles** — each cell is an `AspectRatio(aspectRatio: 1)`, so the masonry
  grid renders as a uniform square grid, edge to edge.
- **Pinch to zoom** — two fingers change the column count (2–6), morphing with the
  iOS-Photos cross-fade; the point under your fingers stays put.
- **Long-press to reorder** — drag a photo to a new spot, including across the
  dated sections (Today / Yesterday / Last Week).
- **Mode + column controls** — the bar under the app bar switches the zoom style
  (morph / photos) and steps the column count live.

The app-bar buttons open the other examples:

- **Lazy sliver gallery** — the same look backed by `SliverFluidGrid`, scaling to
  thousands of generated tiles.
- **Measured text cards** — a Pinterest-style board of variable-height note cards
  (`GridItemHeight.measured()`), some with a photo header.
- **Device photos** — the only page backed by *real* images: it loads your
  device photo library with [`photo_manager`](https://pub.dev/packages/photo_manager)
  and lays it out lazily in the iOS-Photos zoom. Grant photo access when prompted.
  Kept separate from the generated-gradient pages above. Because the photos-style
  pinch builds the incoming grid fresh, it requests a **fixed** thumbnail size and
  `main()` enlarges `imageCache` so the dense grid stays resident — otherwise the
  tiles would flash blank while re-decoding mid-zoom.

## Run

Platform runners aren't committed, so generate them once, then run:

```sh
cd example
flutter create --platforms=android,ios,macos .
flutter run
```

Everything lives in [`lib/main.dart`](lib/main.dart). All pages but **Device photos**
use generated gradient tiles (no bundled assets); Device photos reads the real
library, so it needs the photo permission already declared in the iOS/Android/macOS
runners.
