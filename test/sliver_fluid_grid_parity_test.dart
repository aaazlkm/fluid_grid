import 'package:fluid_grid/fluid_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _dragDelay = Duration(milliseconds: 300);

/// A single-section reorderable sliver grid inside a CustomScrollView, with an
/// optional box adapter placed before it so the grid starts at a scroll offset.
Widget _harness({
  required List<String> items,
  void Function(GridReorderResult<String>)? onReorderFinished,
  void Function(int)? onCrossAxisCountChanged,
  double leadingExtent = 0,
  GridZoomConfig? zoomConfig,
  int crossAxisCount = 2,
}) => MaterialApp(
  home: Scaffold(
    body: CustomScrollView(
      slivers: [
        if (leadingExtent > 0)
          SliverToBoxAdapter(
            child: SizedBox(
              height: leadingExtent,
              child: const ColoredBox(color: Color(0xFF00FF00)),
            ),
          ),
        SliverFluidGrid<String>(
          idOf: (item) => item,
          dragStartDelay: _dragDelay,
          crossAxisCount: crossAxisCount,
          zoomConfig: zoomConfig,
          sections: [GridSection(id: 's', items: items)],
          onReorderFinished: onReorderFinished,
          onCrossAxisCountChanged: onCrossAxisCountChanged,
          itemHeight: GridItemHeight.builder((_, _) => 100),
          itemBuilder: (context, item) => SizedBox(height: 100, child: Text(item)),
        ),
      ],
    ),
  ),
);

Future<void> _dragItem(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(_dragDelay + const Duration(milliseconds: 50));
  final delta = to - from;
  for (var step = 1; step <= 5; step++) {
    await gesture.moveTo(from + delta * (step / 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'dragging an item onto its neighbour reorders inside the sliver',
    (tester) async {
      GridReorderResult<String>? result;
      await tester.pumpWidget(
        _harness(
          items: ['a', 'b', 'c', 'd'],
          onReorderFinished: (r) => result = r,
        ),
      );
      await tester.pump();

      await _dragItem(
        tester,
        tester.getCenter(find.text('a')),
        tester.getCenter(find.text('b')),
      );

      expect(result, isNotNull);
      expect(result!.item, 'a');
      // 'a' left index 0; it should land at a different slot.
      expect(result!.toIndex, isNot(0));
    },
  );

  testWidgets('reorder coordinate math accounts for a preceding sliver', (
    tester,
  ) async {
    GridReorderResult<String>? result;
    await tester.pumpWidget(
      _harness(
        items: ['a', 'b', 'c', 'd'],
        leadingExtent: 250,
        onReorderFinished: (r) => result = r,
      ),
    );
    await tester.pump();

    // The grid starts 250px down; the drag helper uses on-screen positions, so
    // this only lands correctly if globalToGridLocal subtracts the leading
    // sliver's extent via the render tree.
    await _dragItem(
      tester,
      tester.getCenter(find.text('a')),
      tester.getCenter(find.text('d')),
    );

    expect(result, isNotNull);
    expect(result!.item, 'a');
    expect(
      result!.toIndex,
      greaterThan(0),
      reason: 'a moved forward past its origin',
    );
  });

  testWidgets('a two-finger pinch changes the column count', (tester) async {
    int? newCount;
    await tester.pumpWidget(
      _harness(
        items: List.generate(12, (i) => 'i$i'),
        crossAxisCount: 2,
        zoomConfig: const GridZoomConfig(
          minCrossAxisCount: 1,
          maxCrossAxisCount: 4,
        ),
        onCrossAxisCountChanged: (c) => newCount = c,
      ),
    );
    await tester.pump();

    // Spreading two fingers apart enlarges the cards, which means fewer columns
    // (iOS-Photos semantics).
    final center = tester.getCenter(find.byType(CustomScrollView));
    final g1 = await tester.startGesture(center - const Offset(20, 0));
    final g2 = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    for (var step = 1; step <= 6; step++) {
      await g1.moveBy(const Offset(-14, 0));
      await g2.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(newCount, isNotNull);
    expect(
      newCount,
      lessThan(2),
      reason: 'spreading fingers zooms out to fewer columns',
    );
  });
}
