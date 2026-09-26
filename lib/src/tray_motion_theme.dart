import 'package:flutter/animation.dart';
import 'package:motor/motor.dart';

class TrayMotionTheme {
  const TrayMotionTheme({
    required this.route,
    this.close = const CurvedMotion(
      Duration(milliseconds: 200),
      Cubic(0.42, 0, 1, 1),
    ),
    required this.geometry,
    required this.effects,
    this.effectsExit = const CurvedMotion(
      Duration(milliseconds: 180),
      Cubic(0.42, 0, 1, 1),
    ),
    required this.interactive,
  });

  /// Motor motion for the tray's presentation spring when opening.
  final Motion route;

  /// Motor motion for the tray's timed close.
  final Motion close;

  /// Motor motion for changes to the tray's bounds and corner radius.
  final Motion geometry;

  /// Motion for page content and shared-element effects, not tray bounds.
  final Motion effects;

  /// Faster motion for outgoing pages. Shared elements continue using [effects].
  final Motion effectsExit;

  /// Motion used to settle interactive drag gestures.
  final Motion interactive;

  factory TrayMotionTheme.family() {
    return TrayMotionTheme(
      route: const SpringMotion(
        SpringDescription(mass: 1, stiffness: 240, damping: 26),
      ),
      close: const CurvedMotion(
        Duration(milliseconds: 200),
        Cubic(0.42, 0, 1, 1),
      ),
      geometry: const SpringMotion(
        SpringDescription(mass: 0.6, stiffness: 185, damping: 15),
      ),
      effects: const CurvedMotion(
        Duration(milliseconds: 370),
        Cubic(0.26, 0.08, 0.25, 1),
      ),
      effectsExit: const CurvedMotion(
        Duration(milliseconds: 180),
        Cubic(0.42, 0, 1, 1),
      ),
      interactive: const SpringMotion(
        SpringDescription(mass: 1, stiffness: 260, damping: 24),
      ),
    );
  }
}
