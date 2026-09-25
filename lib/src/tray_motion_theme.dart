import 'package:flutter/animation.dart';
import 'package:motor/motor.dart';

class TrayMotionTheme {
  const TrayMotionTheme({
    required this.geometry,
    required this.effects,
    required this.interactive,
  });

  /// The single motion used for route entry/exit and every tray size morph.
  ///
  /// Expansion, collapse, fullscreen, opening, and dismissal all share this
  /// motion so their geometry never switches animation styles.
  final Motion geometry;

  /// Motion for page content and shared-element effects, not tray bounds.
  final Motion effects;

  /// Motion used to settle interactive drag gestures.
  final Motion interactive;

  factory TrayMotionTheme.family() {
    return TrayMotionTheme(
      geometry: const SpringMotion(
        SpringDescription(mass: 1, stiffness: 240, damping: 26),
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
