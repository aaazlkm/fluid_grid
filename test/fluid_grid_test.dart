import 'package:fluid_grid/fluid_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed-height cards keep the expected geometry easy to state.
class _Item {
  const _Item(this.id, this.height);

  final String id;
  final double height;
}

const _dragDelay = Duration(milliseconds: 300);

class _Harness extends StatelessWidget {
  const _Harness({
    required this.pinned,
    required this.unpinned,
    this.onReorderFinished,
    this.onReorderStarted,
    this.onReorderCanceled,
    this.pinnedHeader,
    this.collapseWhenEmpty = false,
    this.onTapItem,
  });

  final List<_Item> pinned;
  final List<_Item> unpinned;
  final void Function(GridReorderResult<_Item>)? onReorderFinished;
  final void Function(_Item)? onReorderStarted;
  final void Function(_Item)? onReorderCanceled;
  final Widget? pinnedHeader;
  final bool collapseWhenEmpty;
  final void Function(_Item)? onTapItem;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: ListView(
        children: [
          FluidGrid<_Item>(
            idOf: (item) => item.id,
            dragStartDelay: _dragDelay,
            sections: [
              GridSection(
                id: 'pinned',
                items: pinned,
                header: pinnedHeader,
                collapseWhenEmpty: collapseWhenEmpty,
              ),
              GridSection(id: 'unpinned', items: unpinned),
            ],
            onReorderStarted: onReorderStarted,
            onReorderFinished: onReorderFinished,
            onReorderCanceled: onReorderCanceled,
            itemBuilder: (context, item) => GestureDetector(
              onTap: () => onTapItem?.call(item),
              child: SizedBox(height: item.height, child: Text(item.id)),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Drives a long-press drag from [from] to [to] and releases.
Future<void> dragItem(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(_dragDelay + const Duration(milliseconds: 50));
  // Several small moves so the resolver sees intermediate positions.
  final delta = to - from;
  for (var step = 1; step <= 5; step++) {
    await gesture.moveTo(from + delta * (step / 5));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('layout', () {
    testWidgets(
      'sizes itself exactly on the first frame, without an estimate pass',
      (tester) async {
        await tester.pumpWidget(
          const _Harness(
            pinned: [],
            unpinned: [_Item('a', 100), _Item('b', 40), _Item('c', 30)],
          ),
        );
        // Deliberately no settle: assert what the very first frame produced.

        final grid = tester.getSize(find.byType(FluidGrid<_Item>));
        // Two columns: 'a' alone (100), then 'b' + 'c' stacked (40 + 30) in the other.
        expect(grid.height, 100);
      },
    );

    testWidgets('places items into the shortest column', (tester) async {
      await tester.pumpWidget(
        const _Harness(
          pinned: [],
          unpinned: [_Item('a', 100), _Item('b', 40), _Item('c', 30)],
        ),
      );

      final a = tester.getTopLeft(find.text('a'));
      final b = tester.getTopLeft(find.text('b'));
      final c = tester.getTopLeft(find.text('c'));

      expect(b.dx, greaterThan(a.dx));
      expect(c.dx, b.dx);
      expect(c.dy, 40);
    });

    testWidgets('separates sections and keeps their column flows independent', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(
          pinned: [_Item('p', 60)],
          unpinned: [_Item('u', 20)],
        ),
      );

      // 'u' starts a fresh section, so it takes column 0 below the pinned block.
      expect(tester.getTopLeft(find.text('u')).dy, 60);
      expect(
        tester.getTopLeft(find.text('u')).dx,
        tester.getTopLeft(find.text('p')).dx,
      );
    });
  });

  group('implicit animation', () {
    testWidgets('springs surviving items into the gap left by a removal', (
      tester,
    ) async {
      await tester.pumpWidget(
        const _Harness(
          pinned: [],
          unpinned: [_Item('a', 40), _Item('b', 40), _Item('c', 40)],
        ),
      );

      expect(tester.getTopLeft(find.text('c')).dy, 40);

      await tester.pumpWidget(
        const _Harness(
          pinned: [],
          unpinned: [_Item('a', 40), _Item('c', 40)],
        ),
      );
      await tester.pump();

      // 'c' has not teleported: it is still on its way to the vacated slot.
      expect(tester.getTopLeft(find.text('c')).dy, greaterThan(0));

      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('c')).dy,
        moreOrLessEquals(0, epsilon: 0.5),
      );
      // The ghost of 'b' has been dropped.
      expect(find.text('b'), findsNothing);
    });

    testWidgets('fades a newly added item in at its slot', (tester) async {
      await tester.pumpWidget(
        const _Harness(pinned: [], unpinned: [_Item('a', 40)]),
      );
      await tester.pumpWidget(
        const _Harness(pinned: [], unpinned: [_Item('a', 40), _Item('b', 40)]),
      );
      await tester.pump();

      expect(find.text('b'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('b')).dy, 0);
    });
  });

  group('reorder', () {
    testWidgets('a tap still reaches the item', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        _Harness(
          pinned: const [],
          unpinned: const [_Item('a', 60), _Item('b', 60)],
          onTapItem: (item) => tapped.add(item.id),
        ),
      );

      await tester.tap(find.text('a'));
      await tester.pumpAndSettle();

      expect(tapped, ['a']);
    });

    testWidgets('a short drag without the long press does not reorder', (
      tester,
    ) async {
      GridReorderResult<_Item>? result;
      await tester.pumpWidget(
        _Harness(
          pinned: const [],
          unpinned: const [_Item('a', 60), _Item('b', 60)],
          onReorderFinished: (value) => result = value,
        ),
      );

      // No pump past the delay: the recognizer never wins the arena.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a')),
      );
      await gesture.moveTo(tester.getCenter(find.text('b')));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('dragging an item onto its neighbour swaps them', (
      tester,
    ) async {
      GridReorderResult<_Item>? result;
      final started = <String>[];

      await tester.pumpWidget(
        _Harness(
          pinned: const [],
          unpinned: const [_Item('a', 60), _Item('b', 60)],
          onReorderStarted: (item) => started.add(item.id),
          onReorderFinished: (value) => result = value,
        ),
      );

      await dragItem(
        tester,
        tester.getCenter(find.text('a')),
        tester.getCenter(find.text('b')),
      );

      expect(started, ['a']);
      expect(result, isNotNull);
      expect(result!.item.id, 'a');
      expect(result!.fromSectionId, 'unpinned');
      expect(result!.fromIndex, 0);
      expect(result!.toSectionId, 'unpinned');
      expect(result!.toIndex, 1);
      expect(result!.itemsOf('unpinned').map((item) => item.id), ['b', 'a']);
      expect(result!.movedAcrossSections, isFalse);
    });

    testWidgets('dragging into another section reports the target section', (
      tester,
    ) async {
      GridReorderResult<_Item>? result;

      await tester.pumpWidget(
        _Harness(
          pinned: const [_Item('p', 60)],
          unpinned: const [_Item('u', 60)],
          onReorderFinished: (value) => result = value,
        ),
      );

      await dragItem(
        tester,
        tester.getCenter(find.text('u')),
        tester.getCenter(find.text('p')),
      );

      expect(result, isNotNull);
      expect(result!.item.id, 'u');
      expect(result!.fromSectionId, 'unpinned');
      expect(result!.toSectionId, 'pinned');
      expect(result!.movedAcrossSections, isTrue);
      expect(result!.itemsOf('pinned').map((item) => item.id), contains('u'));
      expect(result!.itemsOf('unpinned'), isEmpty);
    });

    testWidgets(
      'an empty collapsing section still accepts a drop while dragging',
      (tester) async {
        GridReorderResult<_Item>? result;

        await tester.pumpWidget(
          _Harness(
            pinned: const [],
            unpinned: const [_Item('u', 60)],
            pinnedHeader: const SizedBox(height: 20, child: Text('Pinned')),
            collapseWhenEmpty: true,
            onReorderFinished: (value) => result = value,
          ),
        );
        await tester.pumpAndSettle();

        // The header has collapsed away, so the grid begins with the item.
        expect(
          tester.getTopLeft(find.text('u')).dy,
          moreOrLessEquals(0, epsilon: 0.5),
        );

        // Drag upward past the top: the pinned section re-expands as a drop zone.
        final from = tester.getCenter(find.text('u'));
        await dragItem(tester, from, from - const Offset(0, 40));

        expect(result, isNotNull);
        expect(result!.toSectionId, 'pinned');
        expect(result!.toIndex, 0);
      },
    );

    testWidgets('removing the dragged item mid-drag cancels the drag', (
      tester,
    ) async {
      final canceled = <String>[];
      GridReorderResult<_Item>? result;

      await tester.pumpWidget(
        _Harness(
          pinned: const [],
          unpinned: const [_Item('a', 60), _Item('b', 60)],
          onReorderCanceled: (item) => canceled.add(item.id),
          onReorderFinished: (value) => result = value,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a')),
      );
      await tester.pump(_dragDelay + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump();

      // The data drops the item out from under the finger.
      await tester.pumpWidget(
        _Harness(
          pinned: const [],
          unpinned: const [_Item('b', 60)],
          onReorderCanceled: (item) => canceled.add(item.id),
          onReorderFinished: (value) => result = value,
        ),
      );
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      expect(canceled, ['a']);
      expect(result, isNull);
    });
  });

  testWidgets(
    'an item re-added before its exit fade finishes renders once, not as a ghost',
    (tester) async {
      await tester.pumpWidget(
        const _Harness(pinned: [_Item('a', 60), _Item('b', 60)], unpinned: []),
      );
      await tester.pumpAndSettle();
      expect(find.text('b'), findsOneWidget);

      // Remove b, but only pump partway through its exit fade so it is still a
      // live ghost.
      await tester.pumpWidget(
        const _Harness(pinned: [_Item('a', 60)], unpinned: []),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('b'), findsOneWidget, reason: 'still fading out');

      // Bring b back before the fade completes.
      await tester.pumpWidget(
        const _Harness(pinned: [_Item('a', 60), _Item('b', 60)], unpinned: []),
      );
      await tester.pump();

      // Exactly one b — the revived live tile, not a ghost plus a live copy.
      expect(
        find.text('b'),
        findsOneWidget,
        reason: 'the ghost was cancelled, not left alongside the live tile',
      );

      // And it settles fully opaque rather than fading to nothing.
      await tester.pumpAndSettle();
      expect(find.text('b'), findsOneWidget);
      final opacity = tester.widgetList<Opacity>(
        find.ancestor(of: find.text('b'), matching: find.byType(Opacity)),
      );
      for (final o in opacity) {
        expect(
          o.opacity,
          greaterThan(0.99),
          reason: 'the revived tile is opaque, not mid-exit',
        );
      }
    },
  );
}
