import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A grid of `count` fixed-height items in one section, inside a CustomScrollView
/// of the given viewport height.
Widget _harness({
  required int count,
  double itemHeight = 100,
  double viewportHeight = 600,
  int crossAxisCount = 2,
  Set<int>? built,
  ScrollController? controller,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(400, 600)),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: viewportHeight,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            SliverFluidGrid<int>(
              sections: [
                GridSection<int>(
                  id: 's',
                  items: List.generate(count, (i) => i),
                ),
              ],
              idOf: (i) => i,
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              reorderEnabled: false,
              itemHeight: GridItemHeight.builder((_, _) => itemHeight),
              itemBuilder: (context, i) {
                built?.add(i);
                return Text('item $i');
              },
            ),
          ],
        ),
      ),
    ),
  ),
);

RenderSliverFluidGrid _renderObject(WidgetTester tester) => tester.renderObject<RenderSliverFluidGrid>(find.byType(SliverMasonryGridBody));

void main() {
  testWidgets('lays out with exact scroll extent from the height callback', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(count: 100));
    await tester.pump();

    // 100 items, 2 columns, 50 rows of 100px + 8px spacing between rows.
    // Column bottoms: row height 100, spacing 8 -> total = 50*100 + 49*8 = 5392.
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, closeTo(5392 - 600, 0.5));
  });

  testWidgets('builds only the items near the viewport, not all of them', (
    tester,
  ) async {
    final built = <int>{};
    await tester.pumpWidget(_harness(count: 400, built: built));
    await tester.pump();

    // 600px viewport + cache, item rows are 108px tall -> well under 100 items,
    // nowhere near 400.
    expect(built.length, lessThan(100));
    expect(built, contains(0));
    expect(
      built.contains(399),
      isFalse,
      reason: 'the far item must never be built',
    );

    final materialised = _renderObject(tester).debugMaterialisedKeys.length;
    expect(materialised, lessThan(100));
  });

  testWidgets(
    'scrolls and materialises later items while forgetting early ones',
    (tester) async {
      final controller = ScrollController();
      final built = <int>{};
      await tester.pumpWidget(
        _harness(count: 400, built: built, controller: controller),
      );
      await tester.pump();

      expect(find.text('item 0'), findsOneWidget);

      controller.jumpTo(3000);
      await tester.pump();

      // Around row 27-28 at 3000px; item 0 is long gone.
      expect(find.text('item 0'), findsNothing);
      final keys = _renderObject(
        tester,
      ).debugMaterialisedKeys.map((k) => k.id).toSet();
      expect(keys.contains(0), isFalse);
      expect(
        keys.any((id) => (id as int) > 40),
        isTrue,
        reason: 'later items are now materialised',
      );
    },
  );

  testWidgets('a tap reaches a lazily built item', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 600)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 600,
              child: CustomScrollView(
                slivers: [
                  SliverFluidGrid<int>(
                    sections: [
                      GridSection<int>(
                        id: 's',
                        items: List.generate(50, (i) => i),
                      ),
                    ],
                    idOf: (i) => i,
                    reorderEnabled: false,
                    itemHeight: GridItemHeight.builder((_, _) => 100),
                    itemBuilder: (context, i) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tapped.add(i),
                      child: Text('item $i'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('item 0'));
    expect(tapped, [0]);
  });
}
