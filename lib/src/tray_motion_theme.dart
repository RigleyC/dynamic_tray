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
    this.close = const SpringMotion(
      SpringDescription(mass: 1, stiffness: 900, damping: 60),
    ),
    required this.geometry,
    required this.effects,
    this.effectsExit = const CurvedMotion(
      Duration(milliseconds: 170),
      _viewCurve,
    ),
    required this.interactive,
    this.travel = const TrayTravel.measured(),
    this.dragFadeDistance = 240.0,
    this.pageScale = 0.90,
  });

  /// Motor motion for the tray's presentation spring when opening.
  final Motion route;

  /// Motor motion for the tray's close.
  ///
  /// A spring that starts fast and decelerates into the hidden position. It
  /// runs over [travel], so the tray leaves the viewport on the same path it
  /// entered.
  final Motion close;

  /// Motor motion for changes to the tray's bounds and corner radius.
  final Motion geometry;

  /// Motion for entering page content and shared-element flights, not tray
  /// bounds.
  ///
  /// A forward page change runs the entering page's fade and scale on this
  /// motion. Shared-element flights follow the incoming page's progress, so
  /// they land with it.
  final Motion effects;

  /// Motion for pages that leave the stack, such as the outgoing page of a
  /// forward change or the page popped by a back change. Shorter than
  /// [effects] by default, so the leaving page clears before the new one
  /// settles.
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

  /// Scale that page content moves between during a page change.
  ///
  /// A forward change grows the entering page from this scale to 1. A back
  /// change shrinks the leaving page from 1 down to this scale. The other page
  /// keeps scale 1, and every page scales around its center. Use 1 to keep a
  /// plain crossfade.
  final double pageScale;

  /// The Expo Dynamic Tray feel, and the default for every tray.
  ///
  /// The tray presents on a 900/54 spring over a measured travel, so it starts
  /// just below the viewport and clears it. It closes on a 900/60 spring that
  /// starts fast and decelerates. The tray does not scale while it opens or
  /// closes, it only moves. Its height moves on a 550/41 spring.
  ///
  /// Page changes use one ease. The entering page fades in over 245 ms and
  /// the leaving page fades out over 170 ms. On a forward change the entering
  /// page grows from 0.90 to 1. On a back change the leaving page shrinks
  /// toward 0.90.
  factory TrayMotionTheme.expo() {
    return const TrayMotionTheme(
      route: SpringMotion(
        SpringDescription(mass: 1, stiffness: 900, damping: 54),
      ),
      close: SpringMotion(
        SpringDescription(mass: 1, stiffness: 900, damping: 60),
      ),
      geometry: SpringMotion(
        SpringDescription(mass: 1, stiffness: 550, damping: 41),
      ),
      effects: CurvedMotion(Duration(milliseconds: 245), _viewCurve),
      effectsExit: CurvedMotion(Duration(milliseconds: 170), _viewCurve),
      interactive: SpringMotion(
        SpringDescription(mass: 1, stiffness: 260, damping: 24),
      ),
      travel: TrayTravel.measured(),
      pageScale: 0.90,
    );
  }
}

// Expo's VIEW_EASING for page changes.
const _viewCurve = Cubic(0.26, 0.08, 0.25, 1);
