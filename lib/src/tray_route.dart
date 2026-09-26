import 'package:flutter/widgets.dart';

import 'tray_controller.dart';
import 'tray_geometry.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';
import 'tray_surface.dart';
import 'tray_scope.dart';

Future<T?> showTray<T>({
  required BuildContext context,
  required TrayPage<T> page,
  bool useRootNavigator = false,
  TrayGeometryResolver geometryResolver = const DefaultTrayGeometryResolver(),
  TrayMotionTheme? motionTheme,
  Color barrierColor = const Color.fromRGBO(0, 0, 0, 0.3),
  bool barrierDismissible = true,
  Widget? footer,
  WidgetBuilder? footerBuilder,
  Color? surfaceColor,
  TraySurfaceBuilder? surfaceBuilder,
}) {
  final controller = TrayController(initialPage: page);
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    TrayRoute<T>(
      trayController: controller,
      geometryResolver: geometryResolver,
      motionTheme: motionTheme ?? TrayMotionTheme.family(),
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      footer: footer,
      footerBuilder: footerBuilder,
      surfaceColor: surfaceColor,
      surfaceBuilder: surfaceBuilder,
    ),
  );
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
    this.surfaceBuilder,
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
  final TraySurfaceBuilder? surfaceBuilder;
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
      child: TraySurface(
        controller: trayController,
        geometryResolver: geometryResolver,
        motionTheme: motionTheme,
        footer: footer,
        footerBuilder: footerBuilder,
        surfaceColor: surfaceColor,
        surfaceBuilder: surfaceBuilder,
        barrierColor: _barrierColor,
        barrierDismissible: _barrierDismissible,
        restorationId: trayController.isRestorable ? restorationId : null,
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
    if (trayController.canPop) {
      trayController.pop<Object?>(result);
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
