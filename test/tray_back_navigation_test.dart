import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('system back pops the page stack before dismissing the tray', () {
    final root = TrayPage<void>(builder: (_) => const SizedBox.shrink());
    final child = TrayPage<void>(builder: (_) => const SizedBox.shrink());
    final controller = TrayController(initialPage: root);
    controller.push<void>(child);
    controller.completePageTransition(controller.transition!.id);
    final route = TrayRoute<void>(
      trayController: controller,
      geometryResolver: const DefaultTrayGeometryResolver(),
      motionTheme: TrayMotionTheme.snappy(),
      barrierColor: Colors.black54,
      barrierDismissible: true,
    );

    expect(route.didPop(null), isFalse);
    expect(controller.currentPage, same(root));
    expect(controller.lifecycle, isNot(TrayLifecycle.closing));

    controller.completePageTransition(controller.transition!.id);
    expect(route.didPop(null), isFalse);
    expect(controller.lifecycle, TrayLifecycle.closing);

    route.dispose();
  });
}
