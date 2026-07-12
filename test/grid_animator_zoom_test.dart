import 'dart:ui';

import 'package:fluid_grid/src/animation/grid_animator.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:flutter_test/flutter_test.dart';

const double _dt = 1 / 60;

GridAnimator animator({double initialZoomLevel = 2}) => GridAnimator(springs: const GridSprings(), initialZoomLevel: initialZoomLevel);

void main() {
  test('starts at the initial column count, at rest', () {
    final a = animator(initialZoomLevel: 3);
    expect(a.zoomLevel.value, 3);
    expect(a.zoomActive, isFalse);
  });

  test('a live pinch jumps the zoom level and marks it active', () {
    final a = animator()..zoomSessionActive = true;
    a.zoomLevel.jumpTo(2.6);

    expect(a.zoomLevel.value, 2.6);
    expect(a.zoomActive, isTrue);
  });

  test('the release settle keeps zoomActive true until the spring rests', () {
    final a = animator()
      ..zoomSessionActive = true
      ..zoomLevel.jumpTo(2.6);
    expect(a.zoomActive, isTrue);

    // Fingers lift: session ends but the spring is still travelling.
    a
      ..zoomSessionActive = false
      ..zoomLevel.retarget(3, GridSprings.defaultZoomSettle);
    expect(a.zoomActive, isTrue, reason: 'still settling');

    var guard = 0;
    while (a.zoomLevel.isAnimating && guard++ < 600) {
      a.tick(_dt);
    }

    expect(a.zoomLevel.value, moreOrLessEquals(3, epsilon: 0.01));
    expect(a.zoomActive, isFalse, reason: 'settled');
  });

  test('ticking the zoom settle requests a relayout', () {
    final a = animator()..zoomLevel.retarget(3, GridSprings.defaultZoomSettle);

    final result = a.tick(_dt);
    expect(result.active, isTrue);
    expect(a.needsLayout, isTrue);
  });

  test('an active zoom retargets items with the tracking spring, jumping height', () {
    final a = animator()
      ..zoomSessionActive = true
      // Seed an item at the origin.
      ..syncTargets(rects: {'x': const Rect.fromLTWH(0, 0, 40, 40)}, totalHeight: 100, jump: true);
    expect(a.offsetOf('x'), Offset.zero);

    // A pinch frame moves the item and grows the grid.
    a.syncTargets(
      rects: {'x': const Rect.fromLTWH(50, 80, 40, 40)},
      totalHeight: 200,
      jump: false,
      zoomActive: true,
    );

    // Height is frame-exact immediately (jumped, not sprung).
    expect(a.height, 200);
    // The item is on its way but has not teleported.
    a.tick(_dt);
    final offset = a.offsetOf('x')!;
    expect(offset.dx, greaterThan(0));
    expect(offset.dx, lessThan(50));
  });
}
