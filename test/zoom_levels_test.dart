import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _levels = [1, 3, 5, 9];

class _Card extends StatelessWidget {
  const _Card(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 80,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF4CAF50)),
      child: Center(child: Text(label)),
    ),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({this.onCountChanged, this.initialCount = 3});

  final ValueChanged<int>? onCountChanged;
  final int initialCount;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _count = widget.initialCount;

  void setCount(int count) => setState(() => _count = count);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          FluidGrid<String>(
            crossAxisCount: _count,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            reorderEnabled: false,
            zoomConfig: const GridZoomConfig(zoomLevels: _levels),
            idOf: (item) => item,
            sections: [
              GridSection(
                id: 's',
                items: [for (var i = 0; i < 24; i++) 'item$i'],
              ),
            ],
            onCrossAxisCountChanged: (count) {
              widget.onCountChanged?.call(count);
              setState(() => _count = count);
            },
            itemBuilder: (context, item) => _Card(item),
          ),
        ],
      ),
    ),
  );
}

RenderMasonryGrid _grid(WidgetTester tester) =>
    tester.renderObject<RenderMasonryGrid>(find.byType(MasonryGridBody));

Future<void> _pinch(
  WidgetTester tester, {
  required Offset center,
  required double fromSeparation,
  required double toSeparation,
}) async {
  final g1 = await tester.startGesture(
    center - Offset(fromSeparation / 2, 0),
    pointer: 1,
  );
  final g2 = await tester.startGesture(
    center + Offset(fromSeparation / 2, 0),
    pointer: 2,
  );

  const steps = 6;
  for (var step = 1; step <= steps; step++) {
    final separation =
        fromSeparation + (toSeparation - fromSeparation) * step / steps;
    await g1.moveTo(center - Offset(separation / 2, 0));
    await g2.moveTo(center + Offset(separation / 2, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }

  await g1.up();
  await g2.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a pinch release only ever reports an allowed level', (
    tester,
  ) async {
    final reported = <int>[];
    await tester.pumpWidget(_Harness(onCountChanged: reported.add));
    await tester.pumpAndSettle();

    // Pinch in (more columns), then out (fewer), from 3.
    await _pinch(
      tester,
      center: const Offset(200, 200),
      fromSeparation: 240,
      toSeparation: 80,
    );
    await _pinch(
      tester,
      center: const Offset(200, 200),
      fromSeparation: 80,
      toSeparation: 240,
    );

    expect(reported, isNotEmpty);
    for (final count in reported) {
      expect(
        _levels,
        contains(count),
        reason: 'release must snap to an allowed level, got $count',
      );
    }
  });

  testWidgets('mid-pinch the morph endpoints are an adjacent level pair', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await tester.pumpAndSettle();

    // Hold a pinch mid-flight (no release) that pushes the zoom off 3.
    const center = Offset(200, 200);
    final g1 = await tester.startGesture(
      center - const Offset(60, 0),
      pointer: 1,
    );
    final g2 = await tester.startGesture(
      center + const Offset(60, 0),
      pointer: 2,
    );
    for (var step = 1; step <= 4; step++) {
      await g1.moveBy(const Offset(-10, 0));
      await g2.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    final crossfade = _grid(tester).debugCrossfade;
    expect(crossfade.t, greaterThan(0), reason: 'the zoom is mid-morph');
    final pairIndex = _levels.indexOf(crossfade.low);
    expect(
      pairIndex,
      isNot(-1),
      reason: 'low endpoint ${crossfade.low} must be a level',
    );
    expect(
      crossfade.high,
      _levels[pairIndex + 1],
      reason:
          'endpoints must be ADJACENT levels, never an intermediate integer',
    );

    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'an external count change morphs across multiple level pairs without error',
    (tester) async {
      await tester.pumpWidget(const _Harness(initialCount: 9));
      await tester.pumpAndSettle();

      tester.state<_HarnessState>(find.byType(_Harness)).setCount(1);
      // Step through the whole settle, which crosses the (5,9), (3,5), (1,3) pairs.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();

      expect(find.text('item0'), findsOneWidget);
      final crossfade = _grid(tester).debugCrossfade;
      expect(crossfade.low, 1);
      expect(crossfade.high, 1);
    },
  );

  testWidgets('the scroll pinning holds while pinching with levels', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(initialCount: 5));
    await tester.pumpAndSettle();

    // Pinch out over a specific card and confirm no exception and a level
    // result; the pinning math shares levelNeighbors with the solve, so a
    // divergence would oscillate and typically throw or misreport.
    final reported = <int>[];
    await tester.pumpWidget(
      _Harness(initialCount: 5, onCountChanged: reported.add),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.text('item7'));
    await _pinch(tester, center: center, fromSeparation: 60, toSeparation: 220);

    expect(tester.takeException(), isNull);
    expect(reported, isNotEmpty);
    expect(_levels, contains(reported.last));
    expect(
      reported.last,
      lessThan(5),
      reason: 'spreading fingers zooms out to fewer columns',
    );
  });
}
