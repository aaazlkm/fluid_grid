import 'package:flutter/physics.dart';

/// Pixels and pixels/second below which a spring is considered at rest.
const Tolerance _kSpringTolerance = Tolerance(distance: 0.05, velocity: 0.05);

/// A single scalar driven by a spring.
///
/// Retargeting mid-flight restarts the simulation from the current position and
/// velocity, so an interrupted animation carries its momentum into the new
/// target instead of snapping or losing speed. This is why the grid drives
/// springs directly rather than through `AnimationController.animateWith`,
/// whose unitless 0..1 domain cannot express a velocity handoff between
/// different targets.
class SpringValue {
  SpringValue(double value)
    : _value = value,
      _target = value;

  double _value;
  double _target;
  double _velocity = 0;

  SpringSimulation? _simulation;
  double _elapsed = 0;

  double get value => _value;
  double get target => _target;
  double get velocity => _velocity;
  bool get isAnimating => _simulation != null;

  /// Move immediately, cancelling any motion.
  void jumpTo(double value) {
    _value = value;
    _target = value;
    _velocity = 0;
    _simulation = null;
  }

  /// Spring toward [target], preserving current velocity.
  void retarget(double target, SpringDescription spring) {
    if (_target == target && _simulation != null) return;
    if (_simulation == null && (target - _value).abs() <= _kSpringTolerance.distance) {
      jumpTo(target);
      return;
    }

    _target = target;
    _simulation = SpringSimulation(spring, _value, target, _velocity)..tolerance = _kSpringTolerance;
    _elapsed = 0;
  }

  /// Advance by [dt] seconds. Returns whether the spring is still in motion.
  bool tick(double dt) {
    final simulation = _simulation;
    if (simulation == null) return false;

    _elapsed += dt;
    _value = simulation.x(_elapsed);
    _velocity = simulation.dx(_elapsed);

    if (simulation.isDone(_elapsed)) {
      _value = _target;
      _velocity = 0;
      _simulation = null;
      return false;
    }
    return true;
  }
}
