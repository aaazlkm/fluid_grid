import 'dart:ui' show Offset, Rect;

import 'package:fluid_grid/src/animation/spring_value.dart';
import 'package:fluid_grid/src/model/grid_springs.dart';

enum _FadePhase { steady, entering, exiting }

class _ItemAnimation {
  _ItemAnimation(Offset origin)
    : x = SpringValue(origin.dx),
      y = SpringValue(origin.dy);

  final SpringValue x;
  final SpringValue y;

  _FadePhase phase = _FadePhase.steady;
  double fade = 1;

  Offset get offset => Offset(x.value, y.value);

  bool get isAnimating =>
      x.isAnimating || y.isAnimating || phase != _FadePhase.steady;
}

/// Owns every animated quantity in the grid and advances them from a single
/// ticker.
///
/// Item positions and fades are paint-only. Section collapse and the grid's
/// total height feed back into layout, so they are reported separately via
/// [needsLayout] — the render object relayouts only while those are in motion.
class GridAnimator {
  GridAnimator({required this.springs, double initialZoomLevel = 2})
    : zoomLevel = SpringValue(initialZoomLevel);

  GridSprings springs;

  final Map<Object, _ItemAnimation> _items = {};
  final Map<Object, SpringValue> _collapse = {};

  /// Frozen rects of items that were removed and are fading out.
  final Map<Object, Rect> _ghostRects = {};

  final SpringValue _height = SpringValue(0);

  /// The continuous column count. Integral and at rest between gestures; the
  /// pinch drives it directly, and it springs to the resolved count on release.
  final SpringValue zoomLevel;

  /// True while fingers are down in a pinch. Combined with an in-flight
  /// [zoomLevel] spring (the release settle), it tells the render object to use
  /// the morph paint path and the tracking spring for item positions.
  bool zoomSessionActive = false;

  bool get zoomActive => zoomSessionActive || zoomLevel.isAnimating;

  /// The item currently held by the pointer, exempt from target syncing.
  Object? draggedId;

  /// 0 at rest, 1 fully lifted. Drives the dragged item's scale.
  final SpringValue lift = SpringValue(0);

  bool _needsLayout = false;
  bool get needsLayout => _needsLayout;
  void clearNeedsLayout() => _needsLayout = false;

  double get height => _height.value;

  Map<Object, Rect> get ghostRects => _ghostRects;

  Offset? offsetOf(Object id) => _items[id]?.offset;

  double fadeOf(Object id) => _items[id]?.fade ?? 1;

  /// 0 expanded, 1 collapsed.
  double collapseOf(Object id) => _collapse[id]?.value ?? 0;

  bool get isSettling {
    final id = draggedId;
    return id != null && (_items[id]?.isAnimating ?? false);
  }

  /// Pin the dragged item under the pointer without spring lag.
  void setDragOffset(Offset offset) {
    final item = _items[draggedId];
    if (item == null) return;
    item.x.jumpTo(offset.dx);
    item.y.jumpTo(offset.dy);
  }

  void setCollapseTarget(Object sectionId, double target, {bool jump = false}) {
    final value = _collapse.putIfAbsent(sectionId, () => SpringValue(target));
    if (jump) {
      value.jumpTo(target);
    } else {
      value.retarget(target, springs.reflow);
    }
  }

  /// Push the freshly computed layout into the springs. Items absent from
  /// [rects] have left the flow and keep their current position.
  ///
  /// While [zoomActive], item positions retarget with the stiff tracking spring
  /// instead of the reflow spring, and the total height jumps rather than
  /// springs — the layout must be frame-exact so focal anchoring can predict it.
  void syncTargets({
    required Map<Object, Rect> rects,
    required double totalHeight,
    required bool jump,
    bool zoomActive = false,
  }) {
    if (jump || zoomActive) {
      _height.jumpTo(totalHeight);
    } else {
      _height.retarget(totalHeight, springs.reflow);
    }

    final itemSpring = zoomActive ? springs.zoomTracking : springs.reflow;

    for (final entry in rects.entries) {
      final id = entry.key;
      final topLeft = entry.value.topLeft;

      final item = _items.putIfAbsent(id, () {
        // A brand-new item starts at its target and fades in rather than
        // sliding from an arbitrary origin.
        final fresh = _ItemAnimation(topLeft)
          ..phase = jump ? _FadePhase.steady : _FadePhase.entering;
        if (!jump) fresh.fade = 0;
        return fresh;
      });

      if (id == draggedId) continue;

      if (jump) {
        item.x.jumpTo(topLeft.dx);
        item.y.jumpTo(topLeft.dy);
      } else {
        item.x.retarget(topLeft.dx, itemSpring);
        item.y.retarget(topLeft.dy, itemSpring);
      }
    }
  }

  /// Settle the dragged item into [target] with the drop spring.
  void settleDragged(Offset target) {
    final item = _items[draggedId];
    if (item == null) return;
    item.x.retarget(target.dx, springs.settle);
    item.y.retarget(target.dy, springs.settle);
  }

  /// Begin fading [id] out; its last rect is retained so it can still paint.
  void beginExit(Object id, Rect lastRect) {
    final item = _items[id];
    if (item == null) return;
    item.phase = _FadePhase.exiting;
    _ghostRects[id] = lastRect;
  }

  /// Cancel an in-progress exit because [id] came back into the data before its
  /// fade finished: drop the ghost rect and fade the surviving animation back
  /// in from wherever it had reached, rather than leaving it fading to nothing.
  void cancelExit(Object id) {
    final item = _items[id];
    if (item == null) return;
    item.phase = item.fade >= 1 ? _FadePhase.steady : _FadePhase.entering;
    _ghostRects.remove(id);
  }

  /// Forget an item entirely (its exit finished, or it was never animated).
  void remove(Object id) {
    _items.remove(id);
    _ghostRects.remove(id);
  }

  /// The ids that currently have a live animation (spring or fade). A lazy grid
  /// scans these to find items whose animated position may intersect the
  /// viewport even though their solved rect does not.
  Iterable<Object> get animatedItemIds => _items.keys;

  /// Ensure [id] has an at-rest animation seeded at [at], creating one if it is
  /// absent. Unlike [syncTargets]'s implicit creation this never starts an
  /// enter fade — it is how a lazy grid re-materialises an existing item that
  /// scrolled back into view (it should slide from its old position, not fade
  /// in as if newly added). A no-op when the item already has an animation, so
  /// an in-flight spring is never disturbed.
  void ensureItem(Object id, Offset at) {
    _items.putIfAbsent(id, () => _ItemAnimation(at));
  }

  /// Drop the animations of items the lazy grid no longer needs, so the map
  /// stays bounded to roughly the visible window. Items still in motion (a
  /// running spring, an enter/exit fade), the dragged item, and ghosts are
  /// always retained regardless of [keep]; everything else [keep] rejects is
  /// forgotten.
  void pruneItems(bool Function(Object id) keep) {
    _items.removeWhere((id, item) {
      if (keep(id)) return false;
      if (id == draggedId) return false;
      if (item.isAnimating) return false;
      if (_ghostRects.containsKey(id)) return false;
      return true;
    });
  }

  /// Advance every channel. Returns the ids whose exit completed this tick, and
  /// whether anything is still moving.
  ({bool active, List<Object> exited}) tick(double dt) {
    var active = false;
    final exited = <Object>[];

    // Height, zoom, and collapse all feed back into layout. A spring's final
    // tick snaps its value to the target and reports "done", so relayout
    // whenever one *was* moving at the start of the frame — otherwise the exact
    // resting layout (e.g. the settled column width) is never rendered.
    final hadLayoutMotion =
        _height.isAnimating ||
        zoomLevel.isAnimating ||
        _collapse.values.any((value) => value.isAnimating);

    if (_height.tick(dt)) active = true;
    if (zoomLevel.tick(dt)) active = true;
    for (final value in _collapse.values) {
      if (value.tick(dt)) active = true;
    }
    if (hadLayoutMotion) _needsLayout = true;

    if (lift.tick(dt)) active = true;

    for (final entry in _items.entries) {
      final item = entry.value;
      if (item.x.tick(dt)) active = true;
      if (item.y.tick(dt)) active = true;

      switch (item.phase) {
        case _FadePhase.entering:
          item.fade = _advance(item.fade, dt, springs.enterDuration, 1);
          if (item.fade >= 1) {
            item.phase = _FadePhase.steady;
          } else {
            active = true;
          }
        case _FadePhase.exiting:
          item.fade = _advance(item.fade, dt, springs.exitDuration, 0);
          if (item.fade <= 0) {
            exited.add(entry.key);
          } else {
            active = true;
          }
        case _FadePhase.steady:
          break;
      }
    }

    for (final id in exited) {
      remove(id);
    }

    return (active: active, exited: exited);
  }

  double _advance(double current, double dt, Duration duration, double target) {
    final micros = duration.inMicroseconds;
    if (micros <= 0) return target;
    final step = dt * 1000000 / micros;
    return target > current
        ? (current + step).clamp(0.0, 1.0)
        : (current - step).clamp(0.0, 1.0);
  }

  /// True while any spring or fade is live.
  bool get isAnimating =>
      _height.isAnimating ||
      zoomLevel.isAnimating ||
      lift.isAnimating ||
      _collapse.values.any((value) => value.isAnimating) ||
      _items.values.any((item) => item.isAnimating);
}
