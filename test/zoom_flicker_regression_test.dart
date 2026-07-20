import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressions for the scroll-pinning feedback loop: the one-frame rollover
/// flash, the settle-tail jiggle, and the per-event double-correction
/// oscillation — the visible "flicker" family.

class _SquareTile extends StatelessWidget {
  const _SquareTile(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: ColoredBox(
      color: const Color(0xFF3F51B5),
      child: Center(child: Text(label, style: const TextStyle(fontSize: 8))),
    ),
  );
}

class _FixedTile extends StatelessWidget {
  const _FixedTile(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 80,
    child: ColoredBox(
      color: const Color(0xFF4CAF50),
      child: Center(child: Text(label, style: const TextStyle(fontSize: 8))),
    ),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({
    required this.itemCount,
    required this.square,
    required this.initialCount,
    this.controller,
    this.onScrollNotification,
  });

  final int itemCount;
  final bool square;
  final int initialCount;
  final ScrollController? controller;
  final void Function(ScrollUpdateNotification notification)? onScrollNotification;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _count = widget.initialCount;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          widget.onScrollNotification?.call(notification);
          return false;
        },
        child: ListView(
          controller: widget.controller,
          children: [
            FluidGrid<String>(
              crossAxisCount: _count,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              reorderEnabled: false,
              zoomConfig: const GridZoomConfig(),
              idOf: (item) => item,
              sections: [
                GridSection(
                  id: 's',
                  items: [for (var i = 0; i < widget.itemCount; i++) 'item$i'],
                ),
              ],
              onCrossAxisCountChanged: (count) => setState(() => _count = count),
              itemBuilder: (context, item) => widget.square ? _SquareTile(item) : _FixedTile(item),
            ),
          ],
        ),
      ),
    ),
  );
}

RenderMasonryGrid gridBox(WidgetTester tester) => tester.renderObject<RenderMasonryGrid>(find.byType(MasonryGridBody));

void main() {
  testWidgets(
    'crossing an integer count never jumps the scroll (rollover flash)',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _Harness(
          itemCount: 40,
          square: true,
          initialCount: 4,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(600);
      await tester.pumpAndSettle();

      // Pinch out from 4 columns through the 3.0 boundary. Separation is chosen
      // per step so the zoom lands at 3.3, 3.1, 2.95, 2.8 — exactly one pump
      // crosses the integer, where stale-height predictions used to jump the
      // scroll ~150px for one frame.
      const center = Offset(200, 300);
      const baseSeparation = 100.0;
      final g1 = await tester.startGesture(
        center - const Offset(baseSeparation / 2, 0),
        pointer: 1,
      );
      final g2 = await tester.startGesture(
        center + const Offset(baseSeparation / 2, 0),
        pointer: 2,
      );

      var previousOffset = controller.offset;
      var previousTop = tester.getTopLeft(find.text('item0').first);
      for (final zoom in const [3.3, 3.1, 2.95, 2.8]) {
        final separation = baseSeparation * 4 / zoom;
        await g1.moveTo(center - Offset(separation / 2, 0));
        await g2.moveTo(center + Offset(separation / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));

        expect(
          (controller.offset - previousOffset).abs(),
          lessThan(60),
          reason: 'zoom $zoom: the scroll correction must stay in legit per-frame range',
        );
        final top = tester.getTopLeft(find.text('item0').first);
        expect(
          (top.dy - previousTop.dy).abs(),
          lessThan(60),
          reason: 'zoom $zoom: content must not flash-jump at the rollover',
        );
        previousOffset = controller.offset;
        previousTop = top;
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'the settle glides the pinned point to rest without jiggle or snap',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _Harness(
          itemCount: 40,
          square: true,
          initialCount: 3,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();
      controller.jumpTo(600);
      await tester.pumpAndSettle();

      // Pinch out to zoom ≈ 1.9 and release: the settle spring carries it up to
      // 2 — an upward settle, which also exercises the degenerate-prediction
      // path at the collapse integer.
      const center = Offset(200, 300);
      final g1 = await tester.startGesture(
        center - const Offset(50, 0),
        pointer: 1,
      );
      final g2 = await tester.startGesture(
        center + const Offset(50, 0),
        pointer: 2,
      );
      for (var step = 1; step <= 4; step++) {
        final separation = 100 + step * 15.0;
        await g1.moveTo(center - Offset(separation / 2, 0));
        await g2.moveTo(center + Offset(separation / 2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();

      final box = gridBox(tester);
      expect(
        box.animator.zoomActive,
        isTrue,
        reason: 'the release left a real settle',
      );

      double pinError() {
        final anchorId = box.zoomAnchorId;
        final rect = anchorId == null ? null : box.lastLayout?.itemRects[anchorId];
        if (rect == null) return double.infinity;
        final pinnedGlobalY = box
            .localToGlobal(
              Offset(0, rect.top + box.zoomAnchorFraction.dy * rect.height),
            )
            .dy;
        return (pinnedGlobalY - center.dy).abs();
      }

      double pinnedDy() {
        final anchorId = box.zoomAnchorId;
        final rect = box.lastLayout!.itemRects[anchorId]!;
        return box
            .localToGlobal(
              Offset(0, rect.top + box.zoomAnchorFraction.dy * rect.height),
            )
            .dy;
      }

      // Every settle frame — including the terminal snap frame — keeps the
      // pinned point at the focal, and its motion never reverses direction more
      // than once (a glide, not a jiggle).
      var previousDy = pinnedDy();
      int? direction;
      var signChanges = 0;
      var frames = 0;
      while (box.animator.zoomActive && frames < 300) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        expect(
          pinError(),
          lessThan(3),
          reason: 'settle frame $frames: the pinned point stays under the focal',
        );
        final dy = pinnedDy();
        final delta = dy - previousDy;
        if (delta.abs() > 0.5) {
          final sign = delta.sign.toInt();
          if (direction != null && sign != direction) signChanges++;
          direction = sign;
        }
        previousDy = dy;
      }
      expect(frames, lessThan(300), reason: 'the settle rests');
      expect(
        signChanges,
        lessThanOrEqualTo(1),
        reason: 'the pinned point glides, never oscillates',
      );
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the scroll is corrected at most once per frame while pinching', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var notificationsThisPump = 0;

    await tester.pumpWidget(
      _Harness(
        itemCount: 20,
        square: false,
        initialCount: 2,
        controller: controller,
        onScrollNotification: (_) => notificationsThisPump++,
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(400);
    await tester.pumpAndSettle();

    const center = Offset(200, 300);
    final g1 = await tester.startGesture(
      center - const Offset(50, 0),
      pointer: 1,
    );
    final g2 = await tester.startGesture(
      center + const Offset(50, 0),
      pointer: 2,
    );
    for (var step = 1; step <= 5; step++) {
      final separation = 100 + step * 20.0;
      notificationsThisPump = 0;
      await g1.moveTo(center - Offset(separation / 2, 0));
      await g2.moveTo(center + Offset(separation / 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        notificationsThisPump,
        lessThanOrEqualTo(1),
        reason: 'step $step: one scroll write per frame, no per-event double-correction',
      );
    }

    // Hold the fingers still: re-issued identical moves must not make the
    // scroll ping-pong around its fixed point.
    final offsets = <double>[];
    for (var pump = 0; pump < 4; pump++) {
      await g1.moveTo(center - const Offset(100, 0));
      await g2.moveTo(center + const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 16));
      offsets.add(controller.offset);
    }
    final spread = offsets.reduce((a, b) => a > b ? a : b) - offsets.reduce((a, b) => a < b ? a : b);
    expect(
      spread,
      lessThan(1.0),
      reason: 'a held pinch keeps the scroll parked (no alternation)',
    );

    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'pinching past the range edge produces no movement at all (hard stop)',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _Harness(
          itemCount: 20,
          square: true,
          initialCount: 2,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      // Pinch far past the 1-column limit with the default (hard-stop) config:
      // once the zoom hits the edge the grid must be pixel-frozen.
      const center = Offset(200, 300);
      final g1 = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final g2 = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      // Reach the edge (scale 2 → zoom 1) first.
      for (var step = 1; step <= 4; step++) {
        await g1.moveTo(center - Offset(40 + step * 10.0, 0));
        await g2.moveTo(center + Offset(40 + step * 10.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final edgeWidth = tester.getSize(find.byType(_SquareTile).first).width;
      final edgeOffset = controller.offset;
      final edgeTop = tester.getTopLeft(find.text('item0').first);

      // Keep spreading well past the edge: nothing may move.
      for (var step = 5; step <= 9; step++) {
        await g1.moveTo(center - Offset(40 + step * 15.0, 0));
        await g2.moveTo(center + Offset(40 + step * 15.0, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          tester.getSize(find.byType(_SquareTile).first).width,
          moreOrLessEquals(edgeWidth, epsilon: 0.01),
          reason: 'step $step: tile size pinned at the edge',
        );
        expect(
          controller.offset,
          moreOrLessEquals(edgeOffset, epsilon: 0.5),
          reason: 'step $step: scroll pinned at the edge',
        );
        expect(
          tester.getTopLeft(find.text('item0').first).dy,
          moreOrLessEquals(edgeTop.dy, epsilon: 0.5),
          reason: 'step $step: content pinned at the edge',
        );
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      // Release at the edge: already integral, nothing to settle — stable at
      // one full-width (800px test viewport) column.
      expect(
        tester.getSize(find.byType(_SquareTile).first).width,
        moreOrLessEquals(800, epsilon: 1),
      );
    },
  );
}
