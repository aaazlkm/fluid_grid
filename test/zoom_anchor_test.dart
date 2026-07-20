import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Card extends StatelessWidget {
  const _Card(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF3F51B5)),
      child: Center(child: Text(label)),
    ),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.itemCount,
    this.scrollable = true,
    this.controller,
  });

  final int itemCount;
  final bool scrollable;
  final ScrollController? controller;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _count = 2;

  late final List<String> _items = [
    for (var i = 0; i < widget.itemCount; i++) 'item$i',
  ];

  void removeItem(String id) => setState(() => _items.remove(id));

  @override
  Widget build(BuildContext context) {
    final grid = FluidGrid<String>(
      crossAxisCount: _count,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      reorderEnabled: false,
      zoomConfig: const GridZoomConfig(),
      idOf: (item) => item,
      sections: [
        GridSection(id: 's', items: _items),
      ],
      onCrossAxisCountChanged: (count) => setState(() => _count = count),
      itemBuilder: (context, item) => _Card(item),
    );

    return MaterialApp(
      home: Scaffold(
        body: widget.scrollable
            ? ListView(controller: widget.controller, children: [grid])
            : Align(alignment: Alignment.topLeft, child: grid),
      ),
    );
  }
}

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

/// A label of a card whose centre currently sits within the given y band.
String cardNear(
  WidgetTester tester, {
  required double minY,
  required double maxY,
}) {
  for (final element in tester.widgetList<_Card>(find.byType(_Card))) {
    final finder = find.text(element.label);
    if (finder.evaluate().isEmpty) continue;
    final dy = tester.getCenter(finder).dy;
    if (dy > minY && dy < maxY) return element.label;
  }
  fail('no card found in the y band [$minY, $maxY]');
}

void main() {
  testWidgets('keeps the pinched item under the fingers while zooming out', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_Harness(itemCount: 20, controller: controller));
    await tester.pumpAndSettle();

    controller.jumpTo(240);
    await tester.pumpAndSettle();

    final label = cardNear(tester, minY: 220, maxY: 360);
    final before = tester.getCenter(find.text(label));

    // Pinch out, centred on that card.
    await pinch(tester, center: before, fromSeparation: 100, toSeparation: 190);

    final after = tester.getCenter(find.text(label));
    expect(
      after.dy,
      moreOrLessEquals(before.dy, epsilon: 28),
      reason: 'the anchor held its vertical place',
    );
  });

  testWidgets('keeps the pinched item under the fingers while zooming in', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    // A long list, scrolled deep, so the anchor stays mid-content even after
    // zooming in shrinks the grid (otherwise the scroll clamps and slides).
    await tester.pumpWidget(_Harness(itemCount: 60, controller: controller));
    await tester.pumpAndSettle();

    controller.jumpTo(500);
    await tester.pumpAndSettle();

    final label = cardNear(tester, minY: 220, maxY: 360);
    final before = tester.getCenter(find.text(label));

    // Pinch in (more columns), centred on that card.
    await pinch(tester, center: before, fromSeparation: 200, toSeparation: 90);

    final after = tester.getCenter(find.text(label));
    expect(after.dy, moreOrLessEquals(before.dy, epsilon: 28));
  });

  testWidgets(
    'pinching without a scrollable ancestor still zooms and does not throw',
    (tester) async {
      await tester.pumpWidget(const _Harness(itemCount: 6, scrollable: false));
      await tester.pumpAndSettle();

      final twoColWidth = tester.getSize(find.byType(_Card).first).width;
      await pinch(
        tester,
        center: const Offset(200, 200),
        fromSeparation: 100,
        toSeparation: 200,
      );

      // Zoomed to one column: cards are wider.
      expect(
        tester.getSize(find.byType(_Card).first).width,
        greaterThan(twoColWidth),
      );
    },
  );

  testWidgets('the scroll pinning survives the anchor item leaving the data', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_Harness(itemCount: 20, controller: controller));
    await tester.pumpAndSettle();
    controller.jumpTo(240);
    await tester.pumpAndSettle();

    final box = tester.renderObject<RenderMasonryGrid>(
      find.byType(MasonryGridBody),
    );

    // Pinch centred on a known card so it becomes the scroll anchor. Gentle
    // steps keep the zoom mid-morph (z ≈ 1.1–1.5) rather than rubber-banding
    // at the range edge, so both the live pinning and the settle are real.
    final label = cardNear(tester, minY: 220, maxY: 360);
    final center = tester.getCenter(find.text(label));
    final g1 = await tester.startGesture(
      center - const Offset(50, 0),
      pointer: 1,
    );
    final g2 = await tester.startGesture(
      center + const Offset(50, 0),
      pointer: 2,
    );
    for (var step = 1; step <= 2; step++) {
      await g1.moveTo(center - Offset(50 + step * 15.0, 0));
      await g2.moveTo(center + Offset(50 + step * 15.0, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(box.zoomAnchorId, label);

    // The pinning property: the anchor's fractional point sits at the finger's
    // global y. Raw scroll deltas do NOT discriminate here — holding a deep
    // anchor through a fast morph legitimately moves the offset by 100px+ per
    // frame — but a mis-derived hand-off fraction shifts the pinned point by
    // about a tile, which this catches.
    double pinError() {
      final anchorId = box.zoomAnchorId;
      final rect = box.lastLayout?.itemRects[anchorId];
      if (anchorId == null || rect == null) return double.infinity;
      final pinnedGlobalY = box
          .localToGlobal(
            Offset(0, rect.top + box.zoomAnchorFraction.dy * rect.height),
          )
          .dy;
      return (pinnedGlobalY - center.dy).abs();
    }

    // The anchor item leaves the data mid-pinch: the anchor hands to a
    // survivor whose fraction is derived against the reflowed layout, so the
    // point under the fingers keeps pinning to the survivor seamlessly.
    tester.state<_HarnessState>(find.byType(_Harness)).removeItem(label);
    await tester.pump(const Duration(milliseconds: 16));
    final handedTo = box.zoomAnchorId;
    expect(handedTo, isNotNull);
    expect(handedTo, isNot(label));

    for (var step = 3; step <= 5; step++) {
      await g1.moveTo(center - Offset(80 + (step - 2) * 3.0, 0));
      await g2.moveTo(center + Offset(80 + (step - 2) * 3.0, 0));
      await tester.pump(const Duration(milliseconds: 16));
      // A mis-derived hand-off fraction pins ~a full tile (130px+) off; a
      // correct one stays within one-frame prediction transients (the tight
      // bound also guards the once-per-frame correction — per-event double
      // writes used to park this at ~28px).
      expect(
        pinError(),
        lessThan(10),
        reason: 'step $step: the survivor pins to the finger',
      );
    }
    await g1.up();
    await g2.up();

    // And the settle keeps pinning even if the replacement anchor leaves too
    // (the anchor is read live each tick, not frozen at release).
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      box.animator.zoomActive,
      isTrue,
      reason: 'the release left a real settle to pin through',
    );
    tester
        .state<_HarnessState>(find.byType(_Harness))
        .removeItem(handedTo! as String);
    await tester.pump(const Duration(milliseconds: 16));
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(pinError(), lessThan(40), reason: 'settle frame $frame');
    }
    await tester.pumpAndSettle();
  });
}
