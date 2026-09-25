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
  Color barrierColor = const Color(0x52000000),
  bool barrierDismissible = true,
  Widget? footer,
  Color? surfaceColor = const Color(0xFFFFFFFF),
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
    this.surfaceColor = const Color(0xFFFFFFFF),
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
  final Color? surfaceColor;
  final TraySurfaceBuilder? surfaceBuilder;
  final String? restorationId;
  bool _initialMeasurementReady = false;
  T? _pendingResult;

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
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  TickerFuture didPush() {
    trayController.markOpening();
    return super.didPush()..whenCompleteOrCancel(trayController.markOpen);
  }

  void handleInitialMeasurement() {
    _initialMeasurementReady = true;
    _entranceSimulation?.open();
  }

  _InitialMeasurementSimulation? _entranceSimulation;

  @override
  Simulation? createSimulation({required bool forward}) {
    if (!forward) {
      return motionTheme.route.createSimulation(
        start: controller?.value ?? 1,
        end: 0,
        velocity: controller?.velocity ?? 0,
      );
    }
    final simulation = _InitialMeasurementSimulation(
      motionTheme.route.createSimulation(start: 0, end: 1),
    );
    _entranceSimulation = simulation;
    if (_initialMeasurementReady) {
      simulation.open();
    }
    return simulation;
  }

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Curve get barrierCurve => Curves.linear;

  // PopupRoute drives its barrier and routeAnimation from the same controller.
  // TraySurface uses routeAnimation only for route entry/exit; Motor remains
  // the sole driver of retargetable tray geometry morphs.

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    trayController.attachNavigator(Navigator.of(context));
    return TrayScope(
      controller: trayController,
      child: TraySurface(
        controller: trayController,
        routeAnimation: animation,
        geometryResolver: geometryResolver,
        motionTheme: motionTheme,
        footer: footer,
        surfaceColor: surfaceColor,
        surfaceBuilder: surfaceBuilder,
        barrierColor: _barrierColor,
        barrierDismissible: _barrierDismissible,
        onInitialMeasurement: handleInitialMeasurement,
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
    if (trayController.lifecycle != TrayLifecycle.closing &&
        trayController.canPop) {
      trayController.pop();
      return false;
    }
    trayController.markClosing();
    return super.didPop(result);
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

class _InitialMeasurementSimulation extends Simulation {
  _InitialMeasurementSimulation(this._simulation);

  final Simulation _simulation;
  double? _startTime;
  double _lastTime = 0;

  void open() {
    _startTime ??= _lastTime;
  }

  double _elapsedTime(double time) {
    _lastTime = time;
    final startTime = _startTime;
    if (startTime == null) {
      return 0;
    }
    return (time - startTime).clamp(0.0, double.infinity).toDouble();
  }

  @override
  double x(double time) =>
      _startTime == null ? 0 : _simulation.x(_elapsedTime(time));

  @override
  double dx(double time) {
    return _startTime == null ? 0 : _simulation.dx(_elapsedTime(time));
  }

  @override
  bool isDone(double time) {
    return _startTime != null && _simulation.isDone(_elapsedTime(time));
  }
}
