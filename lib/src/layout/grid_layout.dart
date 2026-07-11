import 'dart:ui' show Rect, TextDirection, lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

/// One item's contribution to the layout: an identity and a measured height.
@immutable
class GridItemSpec {
  const GridItemSpec({required this.id, required this.height});

  final Object id;
  final double height;
}

/// One section's contribution: header/footer extents and ordered items.
@immutable
class GridSectionSpec {
  const GridSectionSpec({
    required this.id,
    required this.items,
    this.headerHeight = 0,
    this.footerHeight = 0,
    this.emptyExtent = 0,
  });

  final Object id;
  final List<GridItemSpec> items;
  final double headerHeight;
  final double footerHeight;

  /// Extent reserved between header and footer while the section has no items.
  /// Used to keep an empty section droppable during a drag.
  final double emptyExtent;
}

/// Everything the solver needs. Contains no widgets — heights are measured by
/// the render object and fed in here, which lets the drag resolver replay the
/// solver on hypothetical orderings without touching the widget tree.
@immutable
class GridLayoutSpec {
  const GridLayoutSpec({
    required this.width,
    required this.sections,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.padding = EdgeInsets.zero,
    this.textDirection = TextDirection.ltr,
  });

  final double width;
  final List<GridSectionSpec> sections;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final EdgeInsets padding;
  final TextDirection textDirection;

  double get contentWidth => (width - padding.horizontal).clamp(0.0, double.infinity);

  double get columnWidth => columnWidthFor(crossAxisCount);

  /// Width of a single column if the grid had [count] columns, independent of
  /// this spec's own [crossAxisCount]. Used by the zoom morph to interpolate
  /// between two column counts.
  double columnWidthFor(int count) {
    if (count <= 0) return 0;
    final available = contentWidth - crossAxisSpacing * (count - 1);
    return (available / count).clamp(0.0, double.infinity);
  }

  GridLayoutSpec copyWith({int? crossAxisCount}) => GridLayoutSpec(
    width: width,
    sections: sections,
    crossAxisCount: crossAxisCount ?? this.crossAxisCount,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisSpacing: mainAxisSpacing,
    padding: padding,
    textDirection: textDirection,
  );
}

/// Where a section's chrome ended up.
@immutable
class SectionGeometry {
  const SectionGeometry({
    required this.headerRect,
    required this.footerRect,
    required this.top,
    required this.bottom,
    required this.contentTop,
    required this.contentBottom,
  });

  final Rect headerRect;
  final Rect footerRect;

  /// Outer bounds of the whole section, header top to footer bottom.
  final double top;
  final double bottom;

  /// Bounds of the item area, between header and footer.
  final double contentTop;
  final double contentBottom;

  static SectionGeometry? lerp(SectionGeometry? a, SectionGeometry? b, double t) {
    if (a == null) return b;
    if (b == null) return a;
    return SectionGeometry(
      headerRect: Rect.lerp(a.headerRect, b.headerRect, t)!,
      footerRect: Rect.lerp(a.footerRect, b.footerRect, t)!,
      top: lerpDouble(a.top, b.top, t)!,
      bottom: lerpDouble(a.bottom, b.bottom, t)!,
      contentTop: lerpDouble(a.contentTop, b.contentTop, t)!,
      contentBottom: lerpDouble(a.contentBottom, b.contentBottom, t)!,
    );
  }
}

@immutable
class GridLayoutResult {
  const GridLayoutResult({
    required this.totalHeight,
    required this.itemRects,
    required this.sections,
  });

  final double totalHeight;
  final Map<Object, Rect> itemRects;
  final Map<Object, SectionGeometry> sections;
}

/// Lays sections out vertically; within each section, items are placed into the
/// column whose current bottom is highest up (ties break to the lowest column
/// index), which is the same shortest-column rule `MasonryGridView` uses.
///
/// Column extents reset at every section boundary, matching the previous
/// implementation's one-grid-per-section structure.
GridLayoutResult computeMasonryLayout(GridLayoutSpec spec) {
  final itemRects = <Object, Rect>{};
  final sections = <Object, SectionGeometry>{};

  final columnWidth = spec.columnWidth;
  final contentWidth = spec.contentWidth;
  final isRtl = spec.textDirection == TextDirection.rtl;

  double xOf(int column) {
    final stride = columnWidth + spec.crossAxisSpacing;
    if (isRtl) {
      return spec.width - spec.padding.right - columnWidth - column * stride;
    }
    return spec.padding.left + column * stride;
  }

  var y = spec.padding.top;

  for (final section in spec.sections) {
    final sectionTop = y;
    final headerRect = Rect.fromLTWH(spec.padding.left, y, contentWidth, section.headerHeight);
    y += section.headerHeight;

    final contentTop = y;
    double contentBottom;

    if (section.items.isEmpty) {
      contentBottom = contentTop + section.emptyExtent;
    } else {
      // Seeded one spacing above the content top so the first item in each
      // column lands exactly at contentTop.
      final columnBottoms = List<double>.filled(spec.crossAxisCount, contentTop - spec.mainAxisSpacing);

      for (final item in section.items) {
        var column = 0;
        for (var c = 1; c < spec.crossAxisCount; c++) {
          if (columnBottoms[c] < columnBottoms[column] - precisionErrorTolerance) {
            column = c;
          }
        }

        final top = columnBottoms[column] + spec.mainAxisSpacing;
        itemRects[item.id] = Rect.fromLTWH(xOf(column), top, columnWidth, item.height);
        columnBottoms[column] = top + item.height;
      }

      contentBottom = columnBottoms.reduce((a, b) => a > b ? a : b);
    }

    y = contentBottom;
    final footerRect = Rect.fromLTWH(spec.padding.left, y, contentWidth, section.footerHeight);
    y += section.footerHeight;

    sections[section.id] = SectionGeometry(
      headerRect: headerRect,
      footerRect: footerRect,
      top: sectionTop,
      bottom: y,
      contentTop: contentTop,
      contentBottom: contentBottom,
    );
  }

  return GridLayoutResult(
    totalHeight: y + spec.padding.bottom,
    itemRects: itemRects,
    sections: sections,
  );
}

/// Blends two layouts computed for adjacent column counts.
///
/// This is how the pinch morph works: [a] is the layout at the lower column
/// count, [b] at the higher, both solved from the same measured heights, and
/// [t] the fractional position between them. Because the endpoint column widths
/// were themselves measured at the interpolated width, at `t == 0` the result
/// is exactly [a] and at `t == 1` exactly [b] — the morph has no snap.
///
/// [t] may fall slightly outside `[0, 1]` while rubber-banding at a range edge;
/// the lerps simply extrapolate.
GridLayoutResult lerpGridLayoutResult(GridLayoutResult a, GridLayoutResult b, double t) {
  final itemRects = <Object, Rect>{};
  for (final id in a.itemRects.keys) {
    final ra = a.itemRects[id];
    final rb = b.itemRects[id];
    if (ra != null && rb != null) {
      itemRects[id] = Rect.lerp(ra, rb, t)!;
    } else {
      itemRects[id] = (rb ?? ra)!;
    }
  }
  // Ids only present in b (should not happen for a shared item set, but keep
  // the merge total).
  for (final id in b.itemRects.keys) {
    itemRects.putIfAbsent(id, () => b.itemRects[id]!);
  }

  final sections = <Object, SectionGeometry>{};
  for (final id in {...a.sections.keys, ...b.sections.keys}) {
    final merged = SectionGeometry.lerp(a.sections[id], b.sections[id], t);
    if (merged != null) sections[id] = merged;
  }

  return GridLayoutResult(
    totalHeight: lerpDouble(a.totalHeight, b.totalHeight, t)!,
    itemRects: itemRects,
    sections: sections,
  );
}
