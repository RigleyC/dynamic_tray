import 'package:flutter/widgets.dart';

import 'tray_page.dart';
import 'tray_route.dart';

/// Shows content in a tray without requiring a manually-created controller.
///
/// A navigator hosts at most one tray. With no tray open, this creates one with
/// [builder] as its first page. With a tray already open and on screen, the page
/// is pushed into that tray, so a shared helper can call `openTray` without
/// knowing whether it runs inside a tray.
///
/// The returned future completes with the value passed to `context.tray.pop`,
/// or with `null` when the tray is dismissed. A call that cannot be honored
/// completes with `null` right away: the tray is still opening or closing,
/// another route covers it, or it is moving between pages. Use showTray when
/// a new tray must be created.
extension TrayOpenContext on BuildContext {
  Future<T?> openTray<T>({
    required TrayPageBuilder builder,
    String? viewId,
    WidgetBuilder? footer,
    TrayPageLayout layout = TrayPageLayout.intrinsic,
  }) {
    final controller = activeTrayControllerFor(
      Navigator.of(this, rootNavigator: true),
    );
    if (controller == null) {
      return showTray<T>(
        context: this,
        page: TrayPage<T>(builder: builder, layout: layout, viewId: viewId),
        footerBuilder: footer,
        useRootNavigator: true,
      );
    }
    if (controller.isSurfaceReady) {
      return controller.pushRequestedPage<T>(
        builder: builder,
        viewId: viewId,
        footer: footer,
        layout: layout,
      );
    }
    assert(() {
      debugPrint(
        'dynamic_tray: openTray was ignored because the tray on this navigator '
        'is not ready (still opening or closing, another route on top, or a '
        'page transition in progress).',
      );
      return true;
    }());
    return Future<T?>.value();
  }
}
