import 'package:flutter/widgets.dart';

import 'tray_page.dart';
import 'tray_route.dart';

/// Opens one tray session without requiring a manually-created controller.
///
/// The returned future completes with [result] passed to `context.tray.close`.
extension TrayOpenContext on BuildContext {
  Future<T?> openTray<T>({
    required TrayPageBuilder builder,
    String? viewId,
    WidgetBuilder? footer,
    TrayPageLayout layout = TrayPageLayout.intrinsic,
  }) {
    return showTray<T>(
      context: this,
      page: TrayPage<T>(builder: builder, layout: layout, viewId: viewId),
      footerBuilder: footer,
      useRootNavigator: true,
    );
  }
}
