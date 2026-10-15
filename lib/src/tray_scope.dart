import 'package:flutter/widgets.dart';

import 'tray_controller.dart';

/// Provides the tray controller to the pages of one tray session.
///
/// It only exposes the controller, which is used to issue commands. It does not
/// notify on controller changes, so readers never rebuild because the tray's
/// state moved. Pages that show state must listen to it themselves.
class TrayScope extends InheritedWidget {
  const TrayScope({super.key, required this.controller, required super.child});

  final TrayController controller;

  static TrayController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TrayScope>();
    assert(scope != null, 'context.tray can only be used inside an open tray.');
    return scope!.controller;
  }

  /// The controller of the tray this context belongs to, or null when there is
  /// no tray here.
  ///
  /// Use this when a page can also be shown outside a tray. It does not create
  /// a dependency on the scope, so the caller listens to the controller itself
  /// when it needs to react to the tray's state.
  static TrayController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TrayScope>()?.controller;

  @override
  bool updateShouldNotify(TrayScope oldWidget) =>
      controller != oldWidget.controller;
}

extension TrayContext on BuildContext {
  TrayController get tray => TrayScope.of(this);

  /// The tray that owns this context, or null when there is no tray here.
  TrayController? get maybeTray => TrayScope.maybeOf(this);
}
