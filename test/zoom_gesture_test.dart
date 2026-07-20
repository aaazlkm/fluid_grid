import 'package:fluid_grid/fluid_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  const _Harness({
    this.reorderEnabled = false,
    this.itemCount = 8,
    this.config = const GridZoomConfig(),
    this.onCountChanged,
    this.onReorderStarted,
    this.controller,
  });

  final bool reorderEnabled;
  final int itemCount;
  final GridZoomConfig config;
  final ValueChanged<int>? onCountChanged;
  final void Function(String)? onReorderStarted;
  final ScrollController? controller;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _count = 2;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: widget.controller,
        children: [
          FluidGrid<String>(
            crossAxisCount: _count,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            reorderEnabled: widget.reorderEnabled,
            zoomConfig: widget.config,
            idOf: (item) => item,
            sections: [
              GridSection(
                id: 's',
                items: [for (var i = 0; i < widget.itemCount; i++) 'item$i'],
              ),
            ],
            onReorderStarted: (item) => widget.onReorderStarted?.call(item),
            onCrossAxisCountChanged: (count) {
              widget.onCountChanged?.call(count);
              // Echo the resolved count back, as a real consumer would.
              setState(() => _count = count);
            },
            itemBuilder: (context, item) => _Card(item),
          ),
        ],
      ),
    ),
  );
}

/// Drives a symmetric two-finger pinch centred on [center], moving the fingers
/// from [fromSeparation] to [toSeparation] apart along the x-axis.
Future<void> pinch(
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
  testWidgets('pinching out lowers the column count', (tester) async {
    int? reported;
    await tester.pumpWidget(_Harness(onCountChanged: (c) => reported = c));
    await tester.pumpAndSettle();

    // Spread the fingers wide apart: scale ~ 2, so 2 columns -> 1.
    await pinch(
      tester,
      center: const Offset(200, 200),
      fromSeparation: 100,
      toSeparation: 200,
    );

    expect(reported, 1);
  });

  testWidgets('pinching in raises the column count', (tester) async {
    int? reported;
    await tester.pumpWidget(_Harness(onCountChanged: (c) => reported = c));
    await tester.pumpAndSettle();

    // Bring the fingers together: scale ~ 0.5, so 2 columns -> 4.
    await pinch(
      tester,
      center: const Offset(200, 200),
      fromSeparation: 240,
      toSeparation: 60,
    );

    expect(reported, greaterThan(2));
  });

  testWidgets(
    'a tiny pinch that resolves back to the base count reports nothing',
    (tester) async {
      int? reported;
      await tester.pumpWidget(_Harness(onCountChanged: (c) => reported = c));
      await tester.pumpAndSettle();

      // Barely change the separation: resolves back to 2.
      await pinch(
        tester,
        center: const Offset(200, 200),
        fromSeparation: 150,
        toSeparation: 160,
      );

      expect(reported, isNull);
    },
  );

  testWidgets('the resolved count echoes back without a layout jump', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    await tester.pumpAndSettle();

    final beforeCards = tester.widgetList(find.byType(_Card)).length;
    await pinch(
      tester,
      center: const Offset(200, 200),
      fromSeparation: 100,
      toSeparation: 200,
    );

    // After settle + echo, the grid is stable at one column with all cards.
    expect(tester.widgetList(find.byType(_Card)).length, beforeCards);
    // One column: every card spans the full content width.
    final width = tester.getSize(find.byType(_Card).first).width;
    expect(width, greaterThan(300));
  });

  testWidgets('a one-finger drag still scrolls the list instead of zooming', (
    tester,
  ) async {
    int? reported;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _Harness(
        itemCount: 40,
        onCountChanged: (c) => reported = c,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(200, 300), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0), reason: 'the list scrolled');
    expect(reported, isNull, reason: 'no zoom from a single finger');
  });

  testWidgets('a two-finger pinch does not start a reorder', (tester) async {
    final started = <String>[];
    await tester.pumpWidget(
      _Harness(reorderEnabled: true, onReorderStarted: started.add),
    );
    await tester.pumpAndSettle();

    await pinch(
      tester,
      center: const Offset(200, 200),
      fromSeparation: 100,
      toSeparation: 220,
    );

    expect(started, isEmpty);
  });

  testWidgets(
    're-pinching while the previous settle runs does not snap the grid',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // First pinch with sideways travel, released mid-flight.
      const center = Offset(200, 260);
      var g1 = await tester.startGesture(
        center - const Offset(60, 0),
        pointer: 1,
      );
      var g2 = await tester.startGesture(
        center + const Offset(60, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 3; step++) {
        final drift = Offset(step * 20.0, 0);
        await g1.moveTo(
          center - const Offset(90, 0) - Offset(step * 12.0, 0) + drift,
        );
        await g2.moveTo(
          center + const Offset(90, 0) + Offset(step * 12.0, 0) + drift,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 32));

      // Second pinch begins while the settle is still running. Track a card
      // across frames: no single frame may jump it far.
      final probe = find.byType(_Card).first;
      var previous = tester.getTopLeft(probe);
      g1 = await tester.startGesture(center - const Offset(60, 0), pointer: 3);
      g2 = await tester.startGesture(center + const Offset(60, 0), pointer: 4);
      for (var step = 1; step <= 4; step++) {
        await g1.moveTo(center - Offset(60 + step * 10.0, 0));
        await g2.moveTo(center + Offset(60 + step * 10.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
        final current = tester.getTopLeft(probe);
        expect(
          (current - previous).distance,
          lessThan(20),
          reason: 'frame $step: a continuous morph never teleports a tile',
        );
        previous = current;
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a mid-settle re-pinch centred somewhere else does not jump the canvas',
    (tester) async {
      await tester.pumpWidget(const _Harness());
      await tester.pumpAndSettle();

      // First pinch out toward 1 column, released early in the morph so the
      // settle is still painting canvases scaled well away from 1.
      const firstCenter = Offset(120, 260);
      var g1 = await tester.startGesture(
        firstCenter - const Offset(60, 0),
        pointer: 1,
      );
      var g2 = await tester.startGesture(
        firstCenter + const Offset(60, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 3; step++) {
        await g1.moveTo(firstCenter - Offset(60 + step * 9.0, 0));
        await g2.moveTo(firstCenter + Offset(60 + step * 9.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 32));

      // The new pinch lands ~150px away from the previous one, and its fingers
      // barely move — so legitimate morph motion is a few pixels per frame.
      // Regression net: capturing a new gesture must never couple its position
      // into painted x (tiles ride their own lerped rects, which no gesture
      // coordinate can shift sideways).
      const secondCenter = Offset(270, 260);
      final probe = find.byType(_Card).first;
      var previous = tester.getTopLeft(probe);
      g1 = await tester.startGesture(
        secondCenter - const Offset(60, 0),
        pointer: 3,
      );
      g2 = await tester.startGesture(
        secondCenter + const Offset(60, 0),
        pointer: 4,
      );
      for (var step = 1; step <= 4; step++) {
        await g1.moveTo(secondCenter - Offset(60 + step * 2.0, 0));
        await g2.moveTo(secondCenter + Offset(60 + step * 2.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
        final current = tester.getTopLeft(probe);
        // Horizontal only: vertical motion belongs to the scroll anchor (and its
        // clamp at the scroll extent), which this test does not exercise.
        expect(
          (current.dx - previous.dx).abs(),
          lessThan(15),
          reason:
              'frame $step: capturing at a displaced focal must not shift the canvas sideways',
        );
        previous = current;
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('releasing a sideways-drifting pinch adds no horizontal motion', (
    tester,
  ) async {
    // An explicit rubber-band factor keeps this regression exercising the
    // rubber zone (the default is a hard stop).
    await tester.pumpWidget(
      const _Harness(config: GridZoomConfig(rubberBandFactor: 0.15)),
    );
    await tester.pumpAndSettle();

    // Pinch out far past the 1-column limit while drifting sideways: the zoom
    // rubber-bands at the range edge, so on release the pair is degenerate and
    // nothing should move at all. Regression net: sideways finger travel must
    // leave no residual motion to dissolve after release (an earlier design
    // slid the whole grid back over many frames here).
    const center = Offset(200, 260);
    final g1 = await tester.startGesture(
      center - const Offset(40, 0),
      pointer: 1,
    );
    final g2 = await tester.startGesture(
      center + const Offset(40, 0),
      pointer: 2,
    );
    for (var step = 1; step <= 8; step++) {
      final drift = Offset(step * 15.0, 0);
      await g1.moveTo(center - Offset(40 + step * 25.0, 0) + drift);
      await g2.moveTo(center + Offset(40 + step * 25.0, 0) + drift);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pump();

    final probes = find.byType(_Card);
    var previous = [
      for (var i = 0; i < probes.evaluate().length; i++)
        tester.getTopLeft(probes.at(i)),
    ];
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = [
        for (var i = 0; i < probes.evaluate().length; i++)
          tester.getTopLeft(probes.at(i)),
      ];
      for (var i = 0; i < current.length; i++) {
        expect(
          (current[i].dx - previous[i].dx).abs(),
          lessThan(1),
          reason:
              'frame $frame, tile $i: release must not slide tiles sideways',
        );
      }
      previous = current;
    }
    await tester.pumpAndSettle();
  });
}
