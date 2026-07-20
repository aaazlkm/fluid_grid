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
  SpringValue(double value) : _value = value, _target = value;

  double _value;
  double _target;
  double _velocity = 0;

  SpringSimulation? _simulation;
  SpringDescription? _spring;
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
    _spring = null;
  }

  /// Spring toward [target], preserving current velocity.
  ///
  /// A running simulation is reused only when *both* the target and the spring
  /// tuning are unchanged — handing a moving value from one spring to another
  /// at the same target (e.g. the zoom-tracking → settle handoff on release)
  /// must adopt the new tuning, not keep coasting under the old one.
  void retarget(double target, SpringDescription spring) {
    if (_simulation != null && _target == target && _sameSpring(spring)) return;
    if (_simulation == null && (target - _value).abs() <= _kSpringTolerance.distance) {
      jumpTo(target);
      return;
    }

    _target = target;
    _spring = spring;
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
      _spring = null;
      return false;
    }
    return true;
  }

  /// Whether [spring] has the same tuning as the running simulation's. Compared
  /// by value (SpringDescription has no `==`), so distinct instances with equal
  /// tuning are treated as the same and don't pointlessly restart the sim.
  bool _sameSpring(SpringDescription spring) {
    final current = _spring;
    return current != null && current.mass == spring.mass && current.stiffness == spring.stiffness && current.damping == spring.damping;
  }
}
