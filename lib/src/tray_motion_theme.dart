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
      Duration(milliseconds: 340),
      _closeCurve,
    ),
    required this.geometry,
    required this.effects,
    this.effectsExit = const CurvedMotion(
      Duration(milliseconds: 370),
      _viewCurve,
    ),
    required this.interactive,
    this.travel = const TrayTravel.fixed(1000),
    this.dragFadeDistance = 240.0,
    this.pageScale = 0.96,
  });

  /// Motor motion for the tray's presentation spring when opening.
  final Motion route;

  /// Motor motion for the tray's timed close.
  ///
  /// Pair its curve with [travel]. The close is a timed ease-in, so the tray
  /// accelerates out of view.
  final Motion close;

  /// Motor motion for changes to the tray's bounds and corner radius.
  final Motion geometry;

  /// Motion for page content and shared-element flights, not tray bounds.
  ///
  /// A page change runs its fade and scale on this motion. Shared-element
  /// flights follow the incoming page's progress, so they land with it.
  final Motion effects;

  /// Motion for pages that leave the stack. Same curve as [effects] by default.
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

  /// Scale of a page while it is hidden, which it grows from as it appears and
  /// shrinks back to as it leaves. Both directions use the page's progress, so
  /// the scale shares the fade's curve. Use 1 to keep a plain crossfade.
  final double pageScale;

  /// The Expo Dynamic Tray feel, and the default for every tray.
  ///
  /// The tray presents on a 240/26 spring from 1000 px below. Its height moves
  /// on a 185/0.6/15 spring. Page changes fade and scale over 370 ms on one
  /// ease, from 0.96 to 1 for the entering page and back for the leaving one.
  factory TrayMotionTheme.expo() {
    return const TrayMotionTheme(
      route: SpringMotion(
        SpringDescription(mass: 1, stiffness: 240, damping: 26),
      ),
      close: CurvedMotion(Duration(milliseconds: 340), _closeCurve),
      geometry: SpringMotion(
        SpringDescription(mass: 0.6, stiffness: 185, damping: 15),
      ),
      effects: CurvedMotion(Duration(milliseconds: 370), _viewCurve),
      effectsExit: CurvedMotion(Duration(milliseconds: 370), _viewCurve),
      interactive: SpringMotion(
        SpringDescription(mass: 1, stiffness: 260, damping: 24),
      ),
      travel: TrayTravel.fixed(1000),
      pageScale: 0.96,
    );
  }
}

// Expo's VIEW_EASING for page changes and CLOSE_EASING for the close.
const _viewCurve = Cubic(0.26, 0.08, 0.25, 1);
const _closeCurve = Cubic(0.55, 0, 1, 0.45);
