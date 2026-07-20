import 'package:fluid_grid/src/layout/grid_layout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

GridSectionSpec section(
  String id,
  List<(String, double)> items, {
  double headerHeight = 0,
  double footerHeight = 0,
  double emptyExtent = 0,
  int leadingCells = 0,
}) => GridSectionSpec(
  id: id,
  items: [
    for (final (itemId, height) in items)
      GridItemSpec(id: itemId, height: height),
  ],
  headerHeight: headerHeight,
  footerHeight: footerHeight,
  emptyExtent: emptyExtent,
  leadingCells: leadingCells,
);

GridLayoutSpec spec(
  List<GridSectionSpec> sections, {
  double width = 216,
  double crossAxisSpacing = 8,
  double mainAxisSpacing = 8,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 16),
  TextDirection textDirection = TextDirection.ltr,
}) => GridLayoutSpec(
  width: width,
  sections: sections,
  crossAxisSpacing: crossAxisSpacing,
  mainAxisSpacing: mainAxisSpacing,
  padding: padding,
  textDirection: textDirection,
);

void main() {
  // width 216 - padding 32 = 184 content; (184 - 8) / 2 = 88 per column.
  const columnWidth = 88.0;

  group('column geometry', () {
    test('splits the content width across columns minus spacing', () {
      expect(spec([]).columnWidth, columnWidth);
      expect(spec([]).contentWidth, 184);
    });

    test('never returns a negative column width', () {
      final narrow = spec([], width: 4);
      expect(narrow.contentWidth, 0);
      expect(narrow.columnWidth, 0);
    });
  });

  group('masonry placement', () {
    test('places the first two items side by side at the content top', () {
      final result = computeMasonryLayout(
        spec([
          section('s', [('a', 100), ('b', 50)]),
        ]),
      );

      expect(
        result.itemRects['a'],
        const Rect.fromLTWH(16, 0, columnWidth, 100),
      );
      expect(
        result.itemRects['b'],
        const Rect.fromLTWH(16 + columnWidth + 8, 0, columnWidth, 50),
      );
    });

    test('sends the next item to the shortest column', () {
      final result = computeMasonryLayout(
        spec([
          section('s', [('a', 100), ('b', 50), ('c', 30)]),
        ]),
      );

      // Column 1 ends at 50, column 0 at 100, so 'c' stacks under 'b'.
      expect(result.itemRects['c']!.top, 50 + 8);
      expect(result.itemRects['c']!.left, result.itemRects['b']!.left);
    });

    test('breaks ties toward the lowest column index', () {
      final result = computeMasonryLayout(
        spec([
          section('s', [('a', 40), ('b', 40), ('c', 10)]),
        ]),
      );

      expect(result.itemRects['c']!.left, result.itemRects['a']!.left);
    });

    test('total height is the tallest column plus padding', () {
      final result = computeMasonryLayout(
        spec(
          [
            section('s', [('a', 100), ('b', 50), ('c', 30)]),
          ],
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        ),
      );

      // Column 0: 100. Column 1: 50 + 8 + 30 = 88. Tallest is 100, offset by top padding.
      expect(result.totalHeight, 4 + 100 + 12);
    });

    test('reserves no main-axis spacing above the first row', () {
      final result = computeMasonryLayout(
        spec(
          [
            section('s', [('a', 10)]),
          ],
          padding: EdgeInsets.zero,
        ),
      );

      expect(result.itemRects['a']!.top, 0);
    });
  });

  group('sections', () {
    test('stacks sections and resets columns at each boundary', () {
      final result = computeMasonryLayout(
        spec(
          [
            section('one', [('a', 100), ('b', 20)]),
            section('two', [('c', 10)]),
          ],
          padding: EdgeInsets.zero,
        ),
      );

      // Section one is 100 tall; section two starts there and 'c' takes column 0.
      expect(result.sections['two']!.top, 100);
      expect(result.itemRects['c']!.top, 100);
      expect(result.itemRects['c']!.left, 0);
    });

    test('positions header above and footer below the item area', () {
      final result = computeMasonryLayout(
        spec(
          [
            section('s', [('a', 40)], headerHeight: 30, footerHeight: 12),
          ],
          padding: EdgeInsets.zero,
        ),
      );

      final geometry = result.sections['s']!;
      expect(geometry.headerRect, const Rect.fromLTWH(0, 0, 216, 30));
      expect(geometry.contentTop, 30);
      expect(result.itemRects['a']!.top, 30);
      expect(geometry.contentBottom, 70);
      expect(geometry.footerRect, const Rect.fromLTWH(0, 70, 216, 12));
      expect(result.totalHeight, 82);
    });

    test('an empty section occupies only its collapsed chrome', () {
      final result = computeMasonryLayout(
        spec(
          [
            section('empty', [], headerHeight: 0, footerHeight: 0),
            section('rest', [('a', 20)]),
          ],
          padding: EdgeInsets.zero,
        ),
      );

      expect(result.sections['empty']!.top, 0);
      expect(result.sections['empty']!.bottom, 0);
      expect(result.itemRects['a']!.top, 0);
    });

    test('an empty section reserves its drop extent while dragging', () {
      final result = computeMasonryLayout(
        spec(
          [
            section('empty', [], headerHeight: 30, emptyExtent: 64),
            section('rest', [('a', 20)]),
          ],
          padding: EdgeInsets.zero,
        ),
      );

      expect(result.sections['empty']!.contentTop, 30);
      expect(result.sections['empty']!.contentBottom, 94);
      expect(result.itemRects['a']!.top, 94);
    });
  });

  group('right-to-left', () {
    test('mirrors columns from the right edge', () {
      final result = computeMasonryLayout(
        spec([
          section('s', [('a', 40), ('b', 40)]),
        ], textDirection: TextDirection.rtl),
      );

      // Column 0 hugs the right content edge; column 1 sits to its left.
      expect(result.itemRects['a']!.left, 216 - 16 - columnWidth);
      expect(result.itemRects['b']!.left, 16);
      expect(result.itemRects['a']!.top, result.itemRects['b']!.top);
    });

    test('keeps the shortest-column order independent of direction', () {
      final items = [('a', 100.0), ('b', 50.0), ('c', 30.0)];
      final ltr = computeMasonryLayout(spec([section('s', items)]));
      final rtl = computeMasonryLayout(
        spec([section('s', items)], textDirection: TextDirection.rtl),
      );

      expect(rtl.itemRects['c']!.top, ltr.itemRects['c']!.top);
      expect(rtl.totalHeight, ltr.totalHeight);
    });
  });

  group('columnWidthFor', () {
    test('is independent of the spec own crossAxisCount', () {
      // width 216 - padding 32 = 184 content.
      final two = spec([], crossAxisSpacing: 8);
      // 1 column: whole content width. 2 columns: (184 - 8) / 2 = 88.
      expect(two.columnWidthFor(1), 184);
      expect(two.columnWidthFor(2), 88);
      // 4 columns: (184 - 24) / 4 = 40.
      expect(two.columnWidthFor(4), 40);
    });

    test('clamps to zero for a non-positive count', () {
      expect(spec([]).columnWidthFor(0), 0);
    });
  });

  group('lerpGridLayoutResult', () {
    // Items are re-solved at each column count. To mimic the real morph, the
    // caller feeds heights measured at the interpolated width; here we keep
    // heights fixed, which is enough to exercise the blend.
    GridLayoutResult solveAt(int count) => computeMasonryLayout(
      spec([
        section('s', [('a', 100), ('b', 60), ('c', 40)]),
      ]).copyWith(crossAxisCount: count),
    );

    test('returns the low layout exactly at t = 0', () {
      final one = solveAt(1);
      final two = solveAt(2);
      final blended = lerpGridLayoutResult(one, two, 0);

      expect(blended.itemRects['a'], one.itemRects['a']);
      expect(blended.itemRects['c'], one.itemRects['c']);
      expect(blended.totalHeight, one.totalHeight);
    });

    test('returns the high layout exactly at t = 1', () {
      final one = solveAt(1);
      final two = solveAt(2);
      final blended = lerpGridLayoutResult(one, two, 1);

      expect(blended.itemRects['a'], two.itemRects['a']);
      expect(blended.itemRects['c'], two.itemRects['c']);
      expect(blended.totalHeight, two.totalHeight);
    });

    test('blends rects and total height at the midpoint', () {
      final one = solveAt(1);
      final two = solveAt(2);
      final blended = lerpGridLayoutResult(one, two, 0.5);

      final expectedTop =
          (one.itemRects['c']!.top + two.itemRects['c']!.top) / 2;
      expect(blended.itemRects['c']!.top, moreOrLessEquals(expectedTop));
      expect(
        blended.totalHeight,
        moreOrLessEquals((one.totalHeight + two.totalHeight) / 2),
      );
    });

    test('extrapolates past t = 1 for edge rubber-banding', () {
      final one = solveAt(1);
      final two = solveAt(2);
      final blended = lerpGridLayoutResult(one, two, 1.1);

      // Beyond the 'b' endpoint, continuing along the a->b direction.
      final ca = one.itemRects['a']!.width;
      final cb = two.itemRects['a']!.width;
      expect(
        blended.itemRects['a']!.width,
        moreOrLessEquals(cb + (cb - ca) * 0.1),
      );
    });

    test('lerps section header geometry', () {
      GridLayoutResult solveHeaderAt(int count) => computeMasonryLayout(
        spec([
          section('s', [('a', 40)], headerHeight: 30, footerHeight: 10),
        ]).copyWith(crossAxisCount: count),
      );
      final one = solveHeaderAt(1);
      final two = solveHeaderAt(2);
      final blended = lerpGridLayoutResult(one, two, 0.5);

      expect(
        blended.sections['s']!.contentBottom,
        moreOrLessEquals(
          (one.sections['s']!.contentBottom +
                  two.sections['s']!.contentBottom) /
              2,
        ),
      );
    });
  });

  group('leadingCells', () {
    List<(String, double)> uniform(int count, double height) => [
      for (var i = 0; i < count; i++) ('i$i', height),
    ];

    test('normalizeLeadingCells reduces to [0, crossAxisCount)', () {
      expect(normalizeLeadingCells(0, 3), 0);
      expect(normalizeLeadingCells(2, 3), 2);
      expect(normalizeLeadingCells(3, 3), 0);
      expect(normalizeLeadingCells(7, 3), 1);
      expect(normalizeLeadingCells(5, 0), 0);
    });

    test('the first item lands at column leadingCells, at the content top', () {
      final result = computeMasonryLayout(
        spec([
          section('s', uniform(4, 40), leadingCells: 1),
        ]),
      );

      // Column 0 is blocked: i0 starts at column 1, top 0.
      expect(
        result.itemRects['i0'],
        const Rect.fromLTWH(16 + columnWidth + 8, 0, columnWidth, 40),
      );
      // i1 wraps to column 0 of the next row.
      expect(
        result.itemRects['i1'],
        const Rect.fromLTWH(16, 48, columnWidth, 40),
      );
    });

    test('a uniform grid shifts by exactly k cells with wrap-around', () {
      // 3 columns wide enough for exact math: width 320, no padding/spacing.
      GridLayoutSpec threeCols(int leadingCells) => GridLayoutSpec(
        width: 300,
        crossAxisCount: 3,
        sections: [
          GridSectionSpec(
            id: 's',
            items: [
              for (var i = 0; i < 7; i++) GridItemSpec(id: 'i$i', height: 100),
            ],
            leadingCells: leadingCells,
          ),
        ],
      );

      final canonical = computeMasonryLayout(threeCols(0));
      final shifted = computeMasonryLayout(threeCols(2));

      for (var i = 0; i < 7; i++) {
        final flat = i + 2;
        expect(
          shifted.itemRects['i$i'],
          Rect.fromLTWH((flat % 3) * 100.0, (flat ~/ 3) * 100.0, 100, 100),
          reason: 'item i$i occupies flat cell $flat',
        );
        // Equivalent phrasing: shifted rect of i == canonical rect of the
        // item that canonically occupies cell i+k (when one exists).
        if (i + 2 < 7) {
          expect(shifted.itemRects['i$i'], canonical.itemRects['i${i + 2}']);
        }
      }
      // 7 items + 2 blocked cells = 9 cells = 3 full rows.
      expect(shifted.totalHeight, 300);
      expect(canonical.totalHeight, 300);
    });

    test('whole-row offsets normalize away', () {
      final canonical = computeMasonryLayout(
        spec([
          section('s', uniform(4, 40)),
        ]),
      );
      final wholeRows = computeMasonryLayout(
        spec([
          section('s', uniform(4, 40), leadingCells: 4),
        ]),
      );
      expect(wholeRows.itemRects, canonical.itemRects);
    });

    test(
      'RTL: blocked cells occupy the reading-order start (the right edge)',
      () {
        final result = computeMasonryLayout(
          spec([
            section('s', uniform(2, 40), leadingCells: 1),
          ], textDirection: TextDirection.rtl),
        );

        // Logical column 0 (rightmost in RTL) is blocked: i0 lands at logical
        // column 1 = the LEFT column.
        expect(result.itemRects['i0']!.left, 16);
        expect(result.itemRects['i0']!.top, 0);
        // i1 wraps to logical column 0 (right) of the next row.
        expect(result.itemRects['i1']!.left, 216 - 16 - columnWidth);
        expect(result.itemRects['i1']!.top, 48);
      },
    );

    test(
      'variable heights: blanks size to the first item, packing stays greedy',
      () {
        final result = computeMasonryLayout(
          spec([
            section('s', [('a', 100), ('b', 30), ('c', 30)], leadingCells: 1),
          ]),
        );

        // a at column 1 (column 0 blocked at height 100).
        expect(
          result.itemRects['a'],
          const Rect.fromLTWH(16 + columnWidth + 8, 0, columnWidth, 100),
        );
        // b: shortest column is the blocked col 0 (bottom 100) vs col 1 (108
        // after spacing)... col 0 bottom 100 < col 1 bottom 100 -> tie goes to
        // col 0: b starts below the phantom.
        expect(
          result.itemRects['b'],
          const Rect.fromLTWH(16, 108, columnWidth, 30),
        );
      },
    );

    test('an empty section ignores leadingCells (emptyExtent wins)', () {
      final withOffset = computeMasonryLayout(
        spec([
          section('empty', const [], emptyExtent: 64, leadingCells: 2),
          section('s', uniform(2, 40)),
        ]),
      );
      final without = computeMasonryLayout(
        spec([
          section('empty', const [], emptyExtent: 64),
          section('s', uniform(2, 40)),
        ]),
      );
      expect(withOffset.itemRects, without.itemRects);
      expect(withOffset.totalHeight, without.totalHeight);
    });

    test('lerp blends layouts whose offsets differ', () {
      final a = computeMasonryLayout(
        spec([
          section('s', uniform(4, 40)),
        ]),
      );
      final b = computeMasonryLayout(
        spec([
          section('s', uniform(4, 40), leadingCells: 1),
        ]),
      );
      final blended = lerpGridLayoutResult(a, b, 0.5);

      expect(
        blended.itemRects['i0']!.left,
        moreOrLessEquals(
          (a.itemRects['i0']!.left + b.itemRects['i0']!.left) / 2,
        ),
      );
      expect(
        blended.totalHeight,
        moreOrLessEquals((a.totalHeight + b.totalHeight) / 2),
      );
    });
  });
}
