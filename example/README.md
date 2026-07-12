# fluid_grid — Photos example

A photo-gallery demo for the `fluid_grid` package, styled after the
iOS Photos app:

- **Square tiles** — each cell is an `AspectRatio(aspectRatio: 1)`, so the masonry
  grid renders as a uniform square grid, edge to edge.
- **Pinch to zoom** — two fingers change the column count (2–6), morphing with the
  iOS-Photos cross-fade; the point under your fingers stays put.
- **Long-press to reorder** — drag a photo to a new spot, including across the
  dated sections (Today / Yesterday / Last Week).

## Run

Platform runners aren't committed, so generate them once, then run:

```sh
cd example
flutter create --platforms=android,ios,macos .
flutter run
```

Everything lives in [`lib/main.dart`](lib/main.dart) — no image assets, tiles are
generated gradients.
