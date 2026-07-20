import 'dart:ui' show Rect, TextDirection;

import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:fluid_grid/src/model/grid_zoom_style.dart';
import 'package:fluid_grid/src/zoom/zoom_math.dart' show levelNeighbors;
import 'package:flutter/painting.dart' show EdgeInsets;

/// The endpoint column counts the animated [zoom] level morphs between, the
/// interpolation weight `t`, and the three relevant column widths: each
/// endpoint's plus the interpolated one that untagged items are measured at.
/// Shared by the box and sliver render objects so both morph identically.
///
/// [levels] restricts the endpoints to adjacent allowed zoom levels (see
/// `GridZoomConfig.zoomLevels`); null means every integer, i.e. floor/ceil.
({
  int lowCount,
  int highCount,
  double t,
  double lowWidth,
  double highWidth,
  double itemWidth,
})
zoomEndpoints({
  required double zoom,
  required double width,
  required double crossAxisSpacing,
  required double mainAxisSpacing,
  required EdgeInsets padding,
  required TextDirection textDirection,
  required List<int>? levels,
}) {
  final neighbors = levelNeighbors(zoom, levels);
  final lowCount = neighbors.low;
  final highCount = neighbors.high;
  final t = neighbors.t;

  final probe = GridLayoutSpec(
    width: width,
    sections: const [],
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
    padding: padding,
    textDirection: textDirection,
  );
  final lowWidth = probe.columnWidthFor(lowCount);
  final highWidth = probe.columnWidthFor(highCount);
  // The visual column width mid-morph. Slot-tagged copies are measured at their
  // own endpoint width and only scaled toward this; untagged items are measured
  // directly at it. Both agree exactly at the endpoints because it lerps between
  // the two slot widths.
  final itemWidth = lowWidth + (highWidth - lowWidth) * t;

  return (
    lowCount: lowCount,
    highCount: highCount,
    t: t,
    lowWidth: lowWidth,
    highWidth: highWidth,
    itemWidth: itemWidth,
  );
}

/// Runs the masonry solver for both endpoint column counts and lerps between
/// them, returning the interpolated result plus each endpoint's own item
/// rects (kept for [GridZoomStyle.photos], whose rigid canvases map each
/// rendition through its own endpoint position rather than the lerped one).
///
/// At an integer zoom the two endpoints coincide, so the solver runs once and
/// both endpoint rect maps point at that single solve.
({
  GridLayoutResult result,
  Map<Object, Rect> lowRects,
  Map<Object, Rect> highRects,
})
solveZoomAware({
  required double width,
  required List<GridSectionSpec> lowSections,
  required List<GridSectionSpec> highSections,
  required int lowCount,
  required int highCount,
  required double t,
  required double crossAxisSpacing,
  required double mainAxisSpacing,
  required EdgeInsets padding,
  required TextDirection textDirection,
}) {
  final specLow = GridLayoutSpec(
    width: width,
    sections: lowSections,
    crossAxisCount: lowCount,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
    padding: padding,
    textDirection: textDirection,
  );

  if (lowCount == highCount) {
    final result = computeMasonryLayout(specLow);
    return (
      result: result,
      lowRects: result.itemRects,
      highRects: result.itemRects,
    );
  }

  final lowResult = computeMasonryLayout(specLow);
  final highResult = computeMasonryLayout(
    GridLayoutSpec(
      width: width,
      sections: highSections,
      crossAxisCount: highCount,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      padding: padding,
      textDirection: textDirection,
    ),
  );

  return (
    result: lerpGridLayoutResult(lowResult, highResult, t),
    lowRects: lowResult.itemRects,
    highRects: highResult.itemRects,
  );
}
