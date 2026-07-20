import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_sliver_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sliver grid whose sections/count can be mutated between pumps.
class _Stateful extends StatefulWidget {
  const _Stateful({required this.controller});
  final _GridController controller;

  @override
  State<_Stateful> createState() => _StatefulState();
}

class _GridController extends ChangeNotifier {
  _GridController(this.sections, this.crossAxisCount, {this.zoomStyle});
  List<GridSection<String>> sections;
  int crossAxisCount;
  final GridZoomStyle? zoomStyle;

  void update(List<GridSection<String>> next) {
    sections = next;
    notifyListeners();
  }

  void setCount(int count) {
    crossAxisCount = count;
    notifyListeners();
  }
}

class _StatefulState extends State<_Stateful> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverFluidGrid<String>(
              idOf: (item) => item,
              crossAxisCount: c.crossAxisCount,
              reorderEnabled: false,
              zoomConfig: c.zoomStyle == null
                  ? null
                  : GridZoomConfig(
                      minCrossAxisCount: 1,
                      maxCrossAxisCount: 4,
                      style: c.zoomStyle!,
                    ),
              sections: c.sections,
              itemHeight: GridItemHeight.builder((_, _) => 100),
              itemBuilder: (context, item) => SizedBox(height: 100, child: Text(item)),
            ),
          ],
        ),
      ),
    );
  }
}

RenderSliverFluidGrid _renderObject(WidgetTester tester) => tester.renderObject<RenderSliverFluidGrid>(find.byType(SliverMasonryGridBody));

void main() {
  testWidgets(
    'measures section headers and includes them in the scroll extent',
    (tester) async {
      final controller = _GridController([
        const GridSection<String>(
          id: 's',
          header: SizedBox(height: 40, child: Text('HEADER')),
          items: ['a', 'b'],
        ),
      ], 2);

      await tester.pumpWidget(_Stateful(controller: controller));
      await tester.pump();

      expect(find.text('HEADER'), findsOneWidget);
      // Header 40 + one row of 100 = 140.
      final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(
        position.maxScrollExtent,
        closeTo((140 - 600).clamp(0, double.infinity), 0.5),
      );
      expect(_renderObject(tester).headerHeightOf('s'), 40);
    },
  );

  testWidgets('removing an item fades it as a ghost, then forgets it', (
    tester,
  ) async {
    final controller = _GridController([
      const GridSection<String>(id: 's', items: ['a', 'b', 'c']),
    ], 2);

    await tester.pumpWidget(_Stateful(controller: controller));
    await tester.pump();
    expect(find.text('b'), findsOneWidget);

    controller.update([
      const GridSection<String>(id: 's', items: ['a', 'c']),
    ]);
    await tester.pump();
    // Mid-fade, the ghost is still painted.
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      find.text('b'),
      findsOneWidget,
      reason: 'the removed item lingers as a fading ghost',
    );

    await tester.pumpAndSettle();
    expect(
      find.text('b'),
      findsNothing,
      reason: 'the ghost is forgotten once faded',
    );
  });

  for (final style in GridZoomStyle.values) {
    testWidgets(
      'a programmatic column change morphs without error (${style.name})',
      (tester) async {
        final controller = _GridController(
          [
            GridSection<String>(
              id: 's',
              items: List.generate(12, (i) => 'i$i'),
            ),
          ],
          2,
          zoomStyle: style,
        );

        await tester.pumpWidget(_Stateful(controller: controller));
        await tester.pump();

        controller.setCount(3);
        // Step through the morph.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();

        // Settled at 3 columns: the crossfade collapsed back to a single build.
        expect(tester.takeException(), isNull);
        expect(find.text('i0'), findsOneWidget);
      },
    );
  }
}
