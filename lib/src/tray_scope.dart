import 'package:flutter/widgets.dart';

import 'tray_controller.dart';

class TrayScope extends InheritedNotifier<TrayController> {
  const TrayScope({
    super.key,
    required TrayController controller,
    required super.child,
  }) : super(notifier: controller);

  static TrayController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TrayScope>();
    assert(scope != null, 'context.tray can only be used inside an open tray.');
    return scope!.notifier!;
  }
}

extension TrayContext on BuildContext {
  TrayController get tray => TrayScope.of(this);
}
