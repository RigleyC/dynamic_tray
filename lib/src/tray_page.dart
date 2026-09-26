import 'package:flutter/widgets.dart';

import 'tray_presentation.dart';

typedef TrayPageBuilder = Widget Function(BuildContext context);
typedef TrayPageRestorer =
    TrayPage<dynamic> Function(String restorationId, Object? arguments);

enum TrayPageLayout {
  /// The page determines its own height from intrinsic content.
  ///
  /// Use this for finite, non-scrollable content. Scroll views and slivers
  /// need a finite viewport and should use [TrayPageLayout.bounded].
  intrinsic,

  /// The page receives a finite viewport and owns its scrolling.
  ///
  /// Use a single `ListView` or `CustomScrollView` at the page root instead
  /// of nesting a scroll view inside another scrollable.
  bounded,
}

class TrayPage<T> {
  const TrayPage({
    required this.builder,
    this.footer,
    this.footerBuilder,
    this.hideFooter = false,
    this.presentation = TrayPresentation.content,
    this.layout = TrayPageLayout.intrinsic,
    this.viewId,
    this.restorationId,
    this.restorationArguments,
  });

  final TrayPageBuilder builder;

  /// A footer displayed in the tray's persistent footer slot while this page
  /// is active. Falls back to the footer passed to [showTray] when null.
  final Widget? footer;

  /// Builds a footer with the tray route's context. Prefer this when the
  /// footer needs access to the current tray session.
  final WidgetBuilder? footerBuilder;

  /// Whether this page hides both its own footer and the route-level fallback.
  final bool hideFooter;

  final TrayPresentation presentation;
  final TrayPageLayout layout;

  /// Optional stable identity used by [TrayController.setView] to reuse a
  /// previously visited page. It is also safe to omit for one-off views.
  final String? viewId;

  /// The stable identifier used to recreate this page during restoration.
  ///
  /// A page in a restorable tray must provide this value. The corresponding
  /// [TrayPageRestorer] receives it after the route is recreated.
  final String? restorationId;

  /// Codec-compatible arguments passed to the [TrayPageRestorer].
  final Object? restorationArguments;
}
