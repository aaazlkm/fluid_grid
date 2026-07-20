import 'package:fluid_grid/fluid_grid.dart';
import 'package:fluid_grid/src/layout/render_masonry_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ImageFilterLayer, OpacityLayer;
import 'package:flutter_test/flutter_test.dart';

/// A card whose height depends on its width: the text wraps to more lines as
/// the column narrows, so its measured height differs at 1 vs 2 columns. This
/// is the case the crossfade morph has to get right.
class _WrapCard extends StatelessWidget {
  const _WrapCard(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: Color(0xFF2196F3)),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Text('$label ' * 8, style: const TextStyle(fontSize: 14)),
    ),
  );
}

/// A stateful card: proves the primary copy's element survives a full morph.
class _CounterCard extends StatefulWidget {
  const _CounterCard(this.label, {super.key});

  final String label;

  @override
  State<_CounterCard> createState() => _CounterCardState();
}

class _CounterCardState extends State<_CounterCard> {
  int count = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: GestureDetector(
      onTap: () => setState(() => count++),
      child: ColoredBox(
        color: const Color(0xFF9C27B0),
        child: Center(child: Text('${widget.label}:$count')),
      ),
    ),
  );
}

class _Harness extends StatelessWidget {
  const _Harness({
    required this.crossAxisCount,
    this.springs = const GridSprings(),
    this.buildCard,
    this.onTapItem,
  });

  final int crossAxisCount;
  final GridSprings springs;
  final Widget Function(String item)? buildCard;
  final void Function(String item)? onTapItem;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          child: ListView(
            children: [
              FluidGrid<String>(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                reorderEnabled: false,
                springs: springs,
                zoomConfig: const GridZoomConfig(style: GridZoomStyle.morph),
                idOf: (item) => item,
                sections: const [
                  GridSection(id: 's', items: ['a', 'b', 'c', 'd']),
                ],
                itemBuilder: (context, item) =>
                    buildCard?.call(item) ??
                    GestureDetector(
                      onTap: onTapItem == null ? null : () => onTapItem!(item),
                      child: _WrapCard(item),
                    ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Finder cardOf(String label) => find.ancestor(
  of: find.text('$label ' * 8),
  matching: find.byType(_WrapCard),
);

double cardWidth(WidgetTester tester, String label) => tester.getSize(cardOf(label)).width;

RenderMasonryGrid gridBox(WidgetTester tester) => tester.renderObject<RenderMasonryGrid>(find.byType(MasonryGridBody));

void main() {
  testWidgets('a static grid lays cards out at the exact column width', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();

    // 400 width, 2 columns, spacing 8 => (400 - 8) / 2 = 196.
    expect(cardWidth(tester, 'a'), moreOrLessEquals(196));
    // Single mode: one copy per item.
    expect(find.byType(_WrapCard), findsNWidgets(4));
  });

  testWidgets(
    'crossfades two endpoint renderings instead of re-wrapping text live',
    (tester) async {
      await tester.pumpWidget(const _Harness(crossAxisCount: 2));
      await tester.pumpAndSettle();

      // Drop to a single column: the settle spring morphs the layout.
      await tester.pumpWidget(const _Harness(crossAxisCount: 1));
      await tester.pump(const Duration(milliseconds: 60));

      // Every item exists twice mid-morph: the outgoing and incoming renderings.
      final cards = find.byType(_WrapCard);
      expect(cards, findsNWidgets(8));

      // Each copy is laid out at an exact endpoint width — never an intermediate
      // one. That is the "no live re-wrap" contract.
      for (final element in cards.evaluate()) {
        final width = (element.renderObject! as RenderBox).size.width;
        expect(
          [196.0, 400.0].any((endpoint) => (width - endpoint).abs() < 0.01),
          isTrue,
          reason: 'copy width $width must be an endpoint width',
        );
      }

      // Photos layering: the incoming (high) canvas ramps to solid by t = 0.4,
      // the outgoing (low) canvas ghosts out above it. Each group's fractional
      // alpha appears as at most one shared OpacityLayer; a solid group paints
      // direct with none. No per-item opacity layers.
      final crossfade = gridBox(tester).debugCrossfade;
      expect(crossfade.t, greaterThan(0));
      expect(crossfade.t, lessThan(1));

      final t = crossfade.t;
      const solidAt = 0.18;
      final highAlpha = (t / solidAt).clamp(0.0, 1.0);
      final lowAlpha = 1 - t;
      final alphas = tester.layers.whereType<OpacityLayer>().map((layer) => layer.alpha ?? -1).toList();
      for (final groupAlpha in [highAlpha, lowAlpha]) {
        if (groupAlpha > 0 && groupAlpha < 1) {
          expect(
            alphas,
            contains((groupAlpha * 255).round()),
            reason: 'a translucent canvas fades as one group',
          );
        }
      }

      // Both renditions scale from their endpoint width to the same interpolated
      // width, so the pair shares one painted tile size — the crossfade swaps
      // resolution in place instead of blending two differently-sized grids.
      double copyScale(ZoomSlot slot) {
        final copy = find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is GridChild && widget.id == 'a' && widget.zoomSlot == slot,
          ),
          matching: find.byType(_WrapCard),
        );
        return tester.renderObject<RenderBox>(copy).getTransformTo(gridBox(tester)).storage[0];
      }

      final expectedLowScale = crossfade.itemWidth / crossfade.lowWidth;
      final expectedHighScale = crossfade.itemWidth / crossfade.highWidth;
      expect(
        copyScale(ZoomSlot.low),
        moreOrLessEquals(expectedLowScale, epsilon: 0.01),
      );
      expect(
        copyScale(ZoomSlot.high),
        moreOrLessEquals(expectedHighScale, epsilon: 0.01),
      );
      expect(
        copyScale(ZoomSlot.low) * crossfade.lowWidth,
        moreOrLessEquals(
          copyScale(ZoomSlot.high) * crossfade.highWidth,
          epsilon: 0.1,
        ),
        reason: 'both renditions paint at the interpolated width',
      );

      await tester.pumpAndSettle();
      // One column spans the full content width; copies collapsed to one each.
      expect(cardWidth(tester, 'a'), moreOrLessEquals(400));
      expect(find.byType(_WrapCard), findsNWidgets(4));
    },
  );

  testWidgets('style: morph dissolves the fading rendition through a blur', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();

    // At rest there is no crossfade, so nothing is blurred.
    expect(
      tester.layers.whereType<ImageFilterLayer>(),
      isEmpty,
      reason: 'the resting grid is crisp',
    );

    // Morph to one column; while a rendition is fading (alpha < 1) it is
    // blurred, so a blur layer is composited on at least one mid-morph frame.
    await tester.pumpWidget(const _Harness(crossAxisCount: 1));
    var sawBlur = false;
    var sawMorph = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final t = gridBox(tester).debugCrossfade.t;
      if (t > 0 && t < 1) sawMorph = true;
      if (tester.layers.whereType<ImageFilterLayer>().isNotEmpty) sawBlur = true;
    }
    expect(sawMorph, isTrue, reason: 'the programmatic morph was mid-flight');
    expect(
      sawBlur,
      isTrue,
      reason: 'the fading morph rendition is blurred mid-transition',
    );

    // The settle removes the crossfade, so the resting grid is crisp again.
    await tester.pumpAndSettle();
    expect(
      tester.layers.whereType<ImageFilterLayer>(),
      isEmpty,
      reason: 'the settled grid is crisp',
    );
  });

  testWidgets('the settled layout equals a grid built directly at that count', (
    tester,
  ) async {
    const ids = ['a', 'b', 'c', 'd'];

    // Reference rects from grids built directly at each count (tree reset in
    // between, so neither reference is itself the product of a morph).
    Future<Map<String, Rect>> directRects(int count) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_Harness(crossAxisCount: count));
      await tester.pumpAndSettle();
      return {for (final id in ids) id: tester.getRect(cardOf(id))};
    }

    final directOne = await directRects(1);
    final directTwo = await directRects(2);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();

    Future<void> expectSettledAt(int count, Map<String, Rect> direct) async {
      await tester.pumpWidget(_Harness(crossAxisCount: count));
      await tester.pumpAndSettle();
      for (final id in ids) {
        final rect = tester.getRect(cardOf(id));
        expect(
          rect.left,
          moreOrLessEquals(direct[id]!.left, epsilon: 0.5),
          reason: '$id left at $count cols',
        );
        expect(
          rect.top,
          moreOrLessEquals(direct[id]!.top, epsilon: 0.5),
          reason: '$id top at $count cols',
        );
        expect(
          rect.width,
          moreOrLessEquals(direct[id]!.width, epsilon: 0.5),
          reason: '$id width at $count cols',
        );
      }
    }

    // Morph both directions; every item lands exactly on the direct build.
    await expectSettledAt(1, directOne);
    await expectSettledAt(2, directTwo);
    await expectSettledAt(1, directOne);
  });

  testWidgets('total grid height grows as columns collapse to one', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();
    final twoColHeight = tester.getSize(find.byType(FluidGrid<String>)).height;

    await tester.pumpWidget(const _Harness(crossAxisCount: 1));
    await tester.pumpAndSettle();
    final oneColHeight = tester.getSize(find.byType(FluidGrid<String>)).height;

    // Four stacked cards are taller than two columns of two.
    expect(oneColHeight, greaterThan(twoColHeight));
  });

  testWidgets('element state survives the morph on the primary copy', (
    tester,
  ) async {
    Widget counterHarness(int count) => _Harness(
      crossAxisCount: count,
      buildCard: (item) => _CounterCard(item, key: ValueKey('counter-$item')),
    );

    await tester.pumpWidget(counterHarness(2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('a:0'));
    await tester.pump();
    await tester.tap(find.text('a:1'));
    await tester.pump();
    expect(find.text('a:2'), findsOneWidget);

    // Morph down to one column and back; the primary element must persist.
    await tester.pumpWidget(counterHarness(1));
    await tester.pumpAndSettle();
    expect(find.text('a:2'), findsOneWidget);

    await tester.pumpWidget(counterHarness(2));
    await tester.pumpAndSettle();
    expect(find.text('a:2'), findsOneWidget);
  });

  testWidgets('the dual-to-single collapse never teleports a tile', (
    tester,
  ) async {
    // A deliberately soft tracking spring guarantees the item springs lag far
    // behind the morph the whole way. When the zoom rests and the crossfade
    // copies collapse to single mode, paint hands over from the frame-exact
    // lerped rects to the springs — without the collapse-frame jump that
    // hand-off is a 100px+ single-frame scatter that then glides back.
    const laggy = GridSprings(
      zoomTracking: SpringDescription(mass: 1, stiffness: 50, damping: 14),
    );

    await tester.pumpWidget(const _Harness(crossAxisCount: 2, springs: laggy));
    await tester.pumpAndSettle();

    // Track every item's PRIMARY copy by identity, so the samples stay valid
    // through the dual-mode frames and across the collapse. (Item 'a' sits at
    // the same spot in both layouts; the others travel.)
    Finder primaryOf(String id) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is GridChild && widget.id == id && !widget.isZoomOverlay,
      ),
      matching: find.byType(_WrapCard),
    );
    const ids = ['a', 'b', 'c', 'd'];

    await tester.pumpWidget(const _Harness(crossAxisCount: 1, springs: laggy));
    // Skip the first morph frame: when the degenerate start pair becomes a real
    // pair, the primary copy changes which endpoint rendering it represents — a
    // sampling identity flip while that rendering is still invisible, not a
    // visual jump.
    await tester.pump(const Duration(milliseconds: 8));

    var previous = {for (final id in ids) id: tester.getTopLeft(primaryOf(id))};
    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames < 300) {
      await tester.pump(const Duration(milliseconds: 8));
      frames++;
      final current = {
        for (final id in ids) id: tester.getTopLeft(primaryOf(id)),
      };
      for (final id in ids) {
        expect(
          (current[id]! - previous[id]!).distance,
          lessThan(60),
          reason: 'frame $frames, item $id: the morph and its collapse must be continuous',
        );
      }
      previous = current;
    }
    expect(frames, lessThan(300), reason: 'the morph settles');

    // And it genuinely finished where a direct build would sit.
    expect(cardWidth(tester, 'a'), moreOrLessEquals(400));
  });

  testWidgets("an item's two renditions coincide throughout the morph", (
    tester,
  ) async {
    // The defining Photos property: the source and destination copies of each
    // element travel together, so every tile reads as ONE element morphing to
    // its new slot while its content crossfades.
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const _Harness(crossAxisCount: 1));
    await tester.pump(const Duration(milliseconds: 8));

    Finder copyOf(String id, {required bool overlay}) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is GridChild && widget.id == id && widget.isZoomOverlay == overlay,
      ),
      matching: find.byType(_WrapCard),
    );

    var midMorphFrames = 0;
    while (tester.binding.hasScheduledFrame && midMorphFrames < 300) {
      await tester.pump(const Duration(milliseconds: 16));
      if (copyOf('a', overlay: true).evaluate().isEmpty) break; // collapsed to single mode
      midMorphFrames++;
      final itemWidth = gridBox(tester).debugCrossfade.itemWidth;
      for (final id in const ['a', 'b', 'c', 'd']) {
        final primary = tester.getRect(copyOf(id, overlay: false));
        final secondary = tester.getRect(copyOf(id, overlay: true));
        expect(
          (primary.left - secondary.left).abs(),
          lessThan(0.01),
          reason: 'frame $midMorphFrames, $id: pair shares its left edge',
        );
        expect(
          (primary.top - secondary.top).abs(),
          lessThan(0.01),
          reason: 'frame $midMorphFrames, $id: pair shares its top edge',
        );
        expect(
          primary.width,
          moreOrLessEquals(itemWidth, epsilon: 0.01),
          reason: 'frame $midMorphFrames, $id: primary paints at the interpolated width',
        );
        expect(
          secondary.width,
          moreOrLessEquals(itemWidth, epsilon: 0.01),
          reason: 'frame $midMorphFrames, $id: overlay paints at the interpolated width',
        );
      }
    }
    expect(
      midMorphFrames,
      greaterThan(3),
      reason: 'sampled a real stretch of the morph',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('the incoming canvas converges to its resting x by pure scale', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(crossAxisCount: 2));
    await tester.pumpAndSettle();

    // Morph 2 -> 1 programmatically and follow the incoming (1-column) copy of
    // a right-column item. Riding its lerped rect, it starts at its 2-column x
    // and must move toward its resting x every frame, never past it and never
    // back: sign-constant convergence, no sideways detours.
    await tester.pumpWidget(const _Harness(crossAxisCount: 1));
    await tester.pump(const Duration(milliseconds: 8));

    Finder incomingOf(String id) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is GridChild && widget.id == id && widget.zoomSlot == ZoomSlot.low,
      ),
      matching: find.byType(_WrapCard),
    );

    final xs = <double>[];
    var frames = 0;
    while (incomingOf('b').evaluate().isNotEmpty && frames < 300) {
      xs.add(tester.getTopLeft(incomingOf('b')).dx);
      await tester.pump(const Duration(milliseconds: 8));
      frames++;
    }
    expect(frames, lessThan(300), reason: 'the morph settles');
    expect(
      xs.length,
      greaterThan(3),
      reason: 'sampled a real stretch of the morph',
    );

    int? direction;
    for (var i = 1; i < xs.length; i++) {
      final delta = xs[i] - xs[i - 1];
      if (delta.abs() < 0.01) continue;
      direction ??= delta.sign.toInt();
      expect(
        delta.sign.toInt(),
        direction,
        reason: 'frame $i: x-motion never reverses',
      );
    }

    await tester.pumpAndSettle();
    // And it lands exactly where a direct 1-column build puts the tile.
    expect(tester.getTopLeft(cardOf('b')).dx, moreOrLessEquals(0));
    expect(cardWidth(tester, 'b'), moreOrLessEquals(400));
  });

  testWidgets('a tap mid-morph reaches exactly one copy', (tester) async {
    final taps = <String>[];

    Widget tapHarness(int count) => _Harness(crossAxisCount: count, onTapItem: taps.add);

    await tester.pumpWidget(tapHarness(2));
    await tester.pumpAndSettle();

    await tester.pumpWidget(tapHarness(1));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(_WrapCard), findsNWidgets(8), reason: 'mid-morph');

    // Both copies of an item paint at the same animated offset; the overlay
    // must be pointer-transparent.
    final target = tester.getTopLeft(find.byType(_WrapCard).first) + const Offset(10, 10);
    await tester.tapAt(target);
    await tester.pumpAndSettle();

    expect(taps, hasLength(1));
  });
}
