import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system back dismisses the tray instead of popping its page stack', () {
    final root = TrayPage<void>(builder: (_) => const SizedBox.shrink());
    final child = TrayPage<void>(builder: (_) => const SizedBox.shrink());
    final controller = TrayController(initialPage: root);
    controller.push<void>(child);
    final route = TrayRoute<void>(
      trayController: controller,
      geometryResolver: const DefaultTrayGeometryResolver(),
      motionTheme: TrayMotionTheme.family(),
      barrierColor: Colors.black54,
      barrierDismissible: true,
    );

    expect(route.didPop(null), isFalse);
    expect(controller.currentPage, same(child));
    expect(controller.canPop, isTrue);
    expect(controller.lifecycle, TrayLifecycle.closing);

    route.dispose();
  });
}
