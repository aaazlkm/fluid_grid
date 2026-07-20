/// How items are rendered while a pinch morphs the grid between two column
/// counts.
///
/// Passed to `GridZoomConfig.style`. Both modes lerp the grid's total height
/// and keep the pinched content anchored under the fingers; they differ only
/// in how each item's two column-count renderings are placed and blended.
///
/// Every mode builds each item **twice** during the morph (the transient copy
/// is pointer- and semantics-excluded), so item content must tolerate two live
/// instances: no GlobalKeys, Heroes, or single-subscription stream listens
/// inside `itemBuilder` content.
enum GridZoomStyle {
  /// Each item is rendered once at each endpoint's exact column width, and
  /// **both renditions ride the item's own interpolated rect**, scaled to the
  /// interpolated width — so the pair coincides and every tile reads as one
  /// element travelling from its old slot to its new slot while its content
  /// crossfades between the two renderings. The incoming rendition ramps to
  /// solid within the first fifth of the morph; the outgoing one ghosts out
  /// linearly the whole way. Each rendition also **dissolves through a blur** —
  /// blurred in proportion to its transparency — so the transition softens as
  /// the content swaps and re-sharpens crisply at both resting levels.
  morph,

  /// The iOS Photos transition: the two endpoint grids crossfade as **rigid
  /// canvases** scale-anchored at the pinch focal point. The incoming grid is
  /// fully laid out and painted (solid almost immediately) *underneath*, while
  /// the outgoing grid fades out on top. Items do not travel to their new
  /// masonry slot — the same screen position simply swaps content with a fade —
  /// and newly visible items slide in from the screen edges already fully
  /// rendered, because they are part of the incoming canvas settling into
  /// place.
  ///
  /// Pairs naturally with `GridZoomConfig.zoomLevels` (e.g. `[1, 3, 5, 9]`).
  photos,
}
