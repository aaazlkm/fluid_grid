import 'dart:ui';

import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1 / 60;

GridAnimator animator() => GridAnimator(springs: const GridSprings());

Rect _rect(double top) => Rect.fromLTWH(0, top, 100, 40);

void main() {
  group('ensureItem', () {
    test('creates an at-rest animation seeded at the given offset', () {
      final a = animator()..ensureItem('a', const Offset(10, 20));

      expect(a.offsetOf('a'), const Offset(10, 20));
      expect(
        a.fadeOf('a'),
        1,
        reason: 'a re-materialised item is fully visible, not fading in',
      );
      expect(a.isAnimating, isFalse);
      expect(a.animatedItemIds, contains('a'));
    });

    test('is a no-op when the item already has an animation in flight', () {
      // A brand-new item arriving via syncTargets slides toward its target.
      final a = animator()
        ..syncTargets(rects: {'a': _rect(100)}, totalHeight: 140, jump: true)
        ..syncTargets(rects: {'a': _rect(200)}, totalHeight: 240, jump: false);
      final beforeTarget = a.offsetOf('a');

      a.ensureItem('a', const Offset(999, 999));

      expect(
        a.offsetOf('a'),
        beforeTarget,
        reason: 'ensureItem must not disturb a live spring',
      );
    });
  });

  group('enter-fade vs slide-in', () {
    test(
      'an item seeded by ensureItem then retargeted slides in without an enter fade',
      () {
        final a = animator()
          ..ensureItem('a', const Offset(0, 500))
          ..syncTargets(rects: {'a': _rect(0)}, totalHeight: 40, jump: false);

        // Slides from 500 toward 0, staying fully opaque the whole way.
        expect(a.fadeOf('a'), 1);
        a.tick(_dt);
        expect(a.fadeOf('a'), 1);
        expect(a.offsetOf('a')!.dy, lessThan(500));
      },
    );

    test('a genuinely new id fades in from zero opacity', () {
      final a = animator()..syncTargets(rects: {'a': _rect(0)}, totalHeight: 40, jump: false);

      expect(
        a.fadeOf('a'),
        0,
        reason: 'a new arrival starts transparent and fades in',
      );
    });
  });

  group('pruneItems', () {
    test('drops at-rest items the keep predicate rejects', () {
      final a = animator()
        ..ensureItem('keep', Offset.zero)
        ..ensureItem('drop', const Offset(0, 1000))
        ..pruneItems((id) => id == 'keep');

      expect(a.animatedItemIds, contains('keep'));
      expect(a.animatedItemIds, isNot(contains('drop')));
      expect(a.offsetOf('drop'), isNull);
    });

    test('retains items still in motion regardless of the predicate', () {
      final a = animator()
        ..syncTargets(rects: {'m': _rect(0)}, totalHeight: 40, jump: true)
        ..syncTargets(rects: {'m': _rect(400)}, totalHeight: 440, jump: false);
      expect(a.offsetOf('m')!.dy, isNot(400), reason: 'spring is mid-flight');

      a.pruneItems((id) => false);

      expect(
        a.animatedItemIds,
        contains('m'),
        reason: 'a moving spring must survive pruning',
      );
    });

    test('retains the dragged item regardless of the predicate', () {
      final a = animator()
        ..ensureItem('d', Offset.zero)
        ..draggedId = 'd'
        ..pruneItems((id) => false);

      expect(a.animatedItemIds, contains('d'));
    });

    test('retains a ghost that is fading out', () {
      final a = animator()
        ..syncTargets(rects: {'g': _rect(0)}, totalHeight: 40, jump: true)
        ..beginExit('g', _rect(0))
        ..pruneItems((id) => false);

      expect(
        a.animatedItemIds,
        contains('g'),
        reason: 'an exiting ghost must keep painting',
      );
    });
  });
}
