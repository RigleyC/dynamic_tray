import 'package:flutter/animation.dart';
import 'package:motor/motor.dart';

class TrayMotionTheme {
  const TrayMotionTheme({
    required this.route,
    required this.geometry,
    required this.effects,
    required this.interactive,
  });

  /// Motor motion for both route entry and route exit.
  final Motion route;

  /// Motor motion for changes to the tray's bounds and corner radius.
  final Motion geometry;

  /// Motion for page content and shared-element effects, not tray bounds.
  final Motion effects;

  /// Motion used to settle interactive drag gestures.
  final Motion interactive;

  factory TrayMotionTheme.family() {
    return TrayMotionTheme(
      route: const SpringMotion(
        SpringDescription(mass: 1, stiffness: 240, damping: 26),
      ),
      geometry: const SpringMotion(
        SpringDescription(mass: 0.6, stiffness: 185, damping: 15),
      ),
      effects: const CurvedMotion(
        Duration(milliseconds: 370),
        Cubic(0.26, 0.08, 0.25, 1),
      ),
      interactive: const SpringMotion(
        SpringDescription(mass: 1, stiffness: 260, damping: 24),
      ),
    );
  }
}
