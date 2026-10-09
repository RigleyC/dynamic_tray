import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'tray_controller.dart';
import 'tray_geometry.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';
import 'tray_surface.dart';
import 'tray_scope.dart';

final Expando<Object> _activeTrays = Expando<Object>(
  'dynamic_tray active route',
);

/// Opens a tray on the selected navigator.
///
/// Each navigator hosts at most one tray at a time. An additional call while
/// that tray is active is ignored and completes with `null`.
Future<T?> showTray<T>({
  required BuildContext context,
  required TrayPage<T> page,
  bool useRootNavigator = true,
  TrayGeometryResolver geometryResolver = const DefaultTrayGeometryResolver(),
  TrayMotionTheme? motionTheme,
  Color barrierColor = const Color.fromRGBO(0, 0, 0, 0.3),
  bool barrierDismissible = true,
  Widget? footer,
  WidgetBuilder? footerBuilder,
  Color? surfaceColor,
}) {
  final controller = TrayController(initialPage: page);
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  if (_activeTrays[navigator] != null) {
    controller.dispose();
    return Future<T?>.value();
  }

  final identity = Object();
  final result = navigator.push<T>(
    TrayRoute<T>(
      trayController: controller,
      geometryResolver: geometryResolver,
      motionTheme: motionTheme ?? TrayMotionTheme.original(),
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      footer: footer,
      footerBuilder: footerBuilder,
      surfaceColor: surfaceColor,
    ),
  );
  _activeTrays[navigator] = identity;
  void release() {
    if (identical(_activeTrays[navigator], identity)) {
      _activeTrays[navigator] = null;
    }
  }

  unawaited(
    result.then<void>(
      (_) => release(),
      onError: (Object error, StackTrace stackTrace) => release(),
    ),
  );
  return result;
}

class TrayRoute<T> extends PopupRoute<T> {
  TrayRoute({
    required this.trayController,
    required this.geometryResolver,
    required this.motionTheme,
    required Color barrierColor,
    required bool barrierDismissible,
    this.footer,
    this.footerBuilder,
    this.surfaceColor,
    this.restorationId,
  }) : _barrierColor = barrierColor,
       _barrierDismissible = barrierDismissible;

  final TrayController trayController;
  final TrayGeometryResolver geometryResolver;
  final TrayMotionTheme motionTheme;
  final Color _barrierColor;
  final bool _barrierDismissible;
  final Widget? footer;
  final WidgetBuilder? footerBuilder;
  final Color? surfaceColor;
  final String? restorationId;
  Object? _pendingResult;

  @override
  Color? get barrierColor => _barrierColor;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String? get barrierLabel => 'Dismiss';

  /// The tray draws its barrier so opacity can share the presentation morph's
  /// progress. Avoid adding a second, independently animated route barrier.
  @override
  Widget buildModalBarrier() => const SizedBox.shrink();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  TickerFuture didPush() {
    trayController.markOpening();
    return super.didPush();
  }

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Curve get barrierCurve => Curves.linear;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    trayController.attachNavigator(Navigator.of(context), this);
    return TrayScope(
      controller: trayController,
      // A modal sheet sits above the page, so dynamic colors inside the tray
      // resolve to their elevated variants, as on iOS.
      child: CupertinoUserInterfaceLevel(
        data: CupertinoUserInterfaceLevelData.elevated,
        child: TraySurface(
          controller: trayController,
          geometryResolver: geometryResolver,
          motionTheme: motionTheme,
          footer: footer,
          footerBuilder: footerBuilder,
          surfaceColor: surfaceColor,
          barrierColor: _barrierColor,
          barrierDismissible: _barrierDismissible,
          restorationId: trayController.isRestorable ? restorationId : null,
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }

  @override
  bool didPop(T? result) {
    if (trayController.consumeRoutePopAuthorization()) {
      return super.didPop(result);
    }
    if (trayController.lifecycle == TrayLifecycle.closing) return false;
    // On system back (Android back button or iOS edge swipe), pop a page if
    // available, or close the tray if at root. This way the user stays in the
    // app longer and the tray doesn't reset the whole stack on one back.
    if (trayController.canPop) {
      trayController.goBack();
    } else {
      trayController.dismiss(result);
    }
    return false;
  }

  @override
  void didComplete(T? result) {
    _pendingResult = result;
    super.didComplete(result);
  }

  @override
  void dispose() {
    super.dispose();
    trayController.completeRoute(_pendingResult);
    trayController.markClosed();
    trayController.detachNavigator();
    trayController.dispose();
  }
}
