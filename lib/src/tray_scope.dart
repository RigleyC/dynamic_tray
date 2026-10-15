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

  @override
  bool updateShouldNotify(TrayScope oldWidget) =>
      controller != oldWidget.controller;
}

extension TrayContext on BuildContext {
  TrayController get tray => TrayScope.of(this);
}
