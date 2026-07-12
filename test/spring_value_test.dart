import 'package:fluid_grid/src/animation/spring_value.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

const SpringDescription _spring = GridSprings.defaultReflow;
const double _dt = 1 / 60;

/// Runs the spring until it comes to rest, returning the frames it took.
int settle(SpringValue value, {int maxFrames = 600}) {
  var frames = 0;
  while (value.tick(_dt)) {
    frames++;
    if (frames > maxFrames) fail('spring did not settle within $maxFrames frames');
  }
  return frames;
}

void main() {
  test('starts at rest', () {
    final value = SpringValue(5)..tick(_dt);
    expect(value.value, 5);
    expect(value.isAnimating, isFalse);
  });

  test('jumpTo moves immediately and cancels motion', () {
    final value = SpringValue(0)
      ..retarget(100, _spring)
      ..tick(_dt)
      ..jumpTo(42);

    expect(value.value, 42);
    expect(value.target, 42);
    expect(value.velocity, 0);
    expect(value.isAnimating, isFalse);
  });

  test('converges on its target and stops', () {
    final value = SpringValue(0)..retarget(100, _spring);
    expect(value.isAnimating, isTrue);

    settle(value);

    expect(value.value, 100);
    expect(value.velocity, 0);
    expect(value.isAnimating, isFalse);
  });

  test('a retarget within tolerance snaps rather than animating', () {
    final value = SpringValue(0)..retarget(0.01, _spring);
    expect(value.isAnimating, isFalse);
    expect(value.value, 0.01);
  });

  test('retargeting to the same value does not restart the simulation', () {
    final value = SpringValue(0)..retarget(100, _spring);
    for (var i = 0; i < 10; i++) {
      value.tick(_dt);
    }
    final midway = value.value;

    value.retarget(100, _spring);
    expect(value.value, midway);
  });

  test('a mid-flight retarget is continuous in position and keeps velocity', () {
    final value = SpringValue(0)..retarget(100, _spring);
    for (var i = 0; i < 10; i++) {
      value.tick(_dt);
    }

    final positionBefore = value.value;
    final velocityBefore = value.velocity;
    expect(velocityBefore, greaterThan(0));

    value.retarget(200, _spring);

    // No teleport, and the momentum toward the old target is carried over.
    expect(value.value, positionBefore);
    expect(value.velocity, velocityBefore);

    value.tick(_dt);
    expect(value.value, greaterThan(positionBefore));

    settle(value);
    expect(value.value, 200);
  });

  test('reversing mid-flight is continuous and returns to the new target', () {
    final value = SpringValue(0)..retarget(100, _spring);
    for (var i = 0; i < 10; i++) {
      value.tick(_dt);
    }

    final positionBefore = value.value;
    final velocityBefore = value.velocity;

    value.retarget(0, _spring);

    // The reversal does not teleport, and it inherits the outbound velocity —
    // the restoring force then bleeds that off over the following frames.
    expect(value.value, positionBefore);
    expect(value.velocity, velocityBefore);

    settle(value);
    expect(value.value, 0);
    expect(value.velocity, 0);
  });

  test('retargeting to the same target with a new spring adopts the new tuning', () {
    const soft = SpringDescription(mass: 1, stiffness: 40, damping: 12);
    const stiff = SpringDescription(mass: 1, stiffness: 900, damping: 60);

    final soften = SpringValue(0)..retarget(100, soft);
    final stiffen = SpringValue(0)..retarget(100, soft);
    for (var i = 0; i < 6; i++) {
      soften.tick(_dt);
      stiffen.tick(_dt);
    }
    // Same position/velocity so far.
    expect(stiffen.value, moreOrLessEquals(soften.value));

    // Hand off to a much stiffer spring at the *same* target: the tuning must
    // actually change, so the next frame accelerates harder than staying soft.
    stiffen.retarget(100, stiff);
    final softNext = (soften..tick(_dt)).value;
    final stiffNext = (stiffen..tick(_dt)).value;
    expect(stiffNext, greaterThan(softNext), reason: 'the stiffer spring pulls harder toward the target');

    // Re-issuing the identical target+tuning does not restart the simulation.
    final beforeElapsedProgress = stiffen.value;
    stiffen.retarget(100, stiff);
    expect((stiffen..tick(_dt)).value, greaterThan(beforeElapsedProgress));
  });
}
