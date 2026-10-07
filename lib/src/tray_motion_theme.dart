import 'package:flutter/animation.dart';
import 'package:motor/motor.dart';

/// How far the tray travels below the viewport when entering and leaving.
sealed class TrayTravel {
  const TrayTravel();

  /// Travels exactly out of view: the tray's own height plus [hiddenGap].
  ///
  /// A hidden tray should sit clear of the edge rather than flush with it,
  /// otherwise the last frame before it disappears clips against the viewport.
  const factory TrayTravel.measured({double hiddenGap}) = MeasuredTrayTravel;

  /// Travels a fixed [distance], regardless of the tray's height.
  const factory TrayTravel.fixed(double distance) = FixedTrayTravel;
}

final class MeasuredTrayTravel extends TrayTravel {
  const MeasuredTrayTravel({this.hiddenGap = 16});

  final double hiddenGap;
}

final class FixedTrayTravel extends TrayTravel {
  const FixedTrayTravel(this.distance);

  final double distance;
}

class TrayMotionTheme {
  const TrayMotionTheme({
    required this.route,
    this.close = const CurvedMotion(
      Duration(milliseconds: 220),
      Cubic(0.4, 0, 0.8, 1),
    ),
    required this.geometry,
    required this.effects,
    this.effectsExit = const CurvedMotion(
      Duration(milliseconds: 180),
      Cubic(0.42, 0, 1, 1),
    ),
    required this.interactive,
    this.travel = const TrayTravel.measured(),
    this.dragFadeDistance = 240.0,
  });

  /// Motor motion for the tray's presentation spring when opening.
  final Motion route;

  /// Motor motion for the tray's timed close.
  ///
  /// Pair its curve with [travel]. With a measured travel almost the whole
  /// curve maps to visible pixels, so a near-linear mild ease-in reads best.
  final Motion close;

  /// Motor motion for changes to the tray's bounds and corner radius.
  final Motion geometry;

  /// Motion for page content and shared-element effects, not tray bounds.
  final Motion effects;

  /// Faster motion for outgoing pages. Shared elements continue using [effects].
  final Motion effectsExit;

  /// Motion used to settle interactive drag gestures.
  final Motion interactive;

  /// How far the tray travels when entering and leaving.
  final TrayTravel travel;

  /// Drag distance over which the backdrop fades out.
  ///
  /// The backdrop is the only feedback during a drag, so it needs its own
  /// scale instead of borrowing the travel distance, which changes with the
  /// tray's height.
  final double dragFadeDistance;

  /// Matches the original React Native tray: slow spring in, long fixed travel,
  /// and the same curve for page entry and exit.
  factory TrayMotionTheme.original() {
    return const TrayMotionTheme(
      route: SpringMotion(
        SpringDescription(mass: 1, stiffness: 240, damping: 26),
      ),
      close: CurvedMotion(Duration(milliseconds: 340), Cubic(0.55, 0, 1, 0.45)),
      geometry: SpringMotion(
        SpringDescription(mass: 0.6, stiffness: 185, damping: 15),
      ),
      effects: CurvedMotion(
        Duration(milliseconds: 370),
        Cubic(0.26, 0.08, 0.25, 1),
      ),
      effectsExit: CurvedMotion(
        Duration(milliseconds: 370),
        Cubic(0.26, 0.08, 0.25, 1),
      ),
      interactive: SpringMotion(
        SpringDescription(mass: 1, stiffness: 260, damping: 24),
      ),
      travel: TrayTravel.fixed(1000),
      dragFadeDistance: 1000,
    );
  }

  /// Faster than [TrayMotionTheme.original]. The travel is measured, so the
  /// spring is stiffer to cover fewer pixels in the same perceptual window.
  factory TrayMotionTheme.snappy() {
    return const TrayMotionTheme(
      route: SpringMotion(
        SpringDescription(mass: 1, stiffness: 400, damping: 34),
      ),
      close: CurvedMotion(Duration(milliseconds: 220), Cubic(0.4, 0, 0.8, 1)),
      geometry: SpringMotion(
        SpringDescription(mass: 0.6, stiffness: 185, damping: 15),
      ),
      effects: CurvedMotion(
        Duration(milliseconds: 370),
        Cubic(0.26, 0.08, 0.25, 1),
      ),
      effectsExit: CurvedMotion(
        Duration(milliseconds: 180),
        Cubic(0.42, 0, 1, 1),
      ),
      interactive: SpringMotion(
        SpringDescription(mass: 1, stiffness: 260, damping: 24),
      ),
    );
  }
}
