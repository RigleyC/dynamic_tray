import 'package:flutter/widgets.dart';

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
    this.layout = TrayPageLayout.intrinsic,
    this.viewId,
    this.restorationId,
    this.restorationArguments,
  });

  /// Builds the page content.
  ///
  /// The tray runs this once per page while the page is in the stack and keeps
  /// the widget it returns. It does not run again on controller notifications,
  /// keyboard or other MediaQuery changes, or lifecycle changes.
  ///
  /// Anything inherited or reactive, such as Theme, localizations or providers,
  /// must be read inside the widget this builder returns, so that widget
  /// rebuilds when those values change. Closures must not capture plain mutable
  /// variables and expect them to refresh, because they only see the values
  /// present when the page was built.
  final TrayPageBuilder builder;

  /// A footer displayed in the tray's persistent footer slot while this page
  /// is active. Falls back to the footer passed to [showTray] when null.
  ///
  /// The footer is built once per page while the page is in the stack, so the
  /// same rules as [builder] apply: read reactive values inside the footer
  /// widget itself.
  final Widget? footer;

  /// Builds a footer with the tray route's context. Prefer this when the
  /// footer needs access to the current tray session.
  ///
  /// Runs once per page while the page is in the stack, under the same rules
  /// as [builder]. Put Theme, localization and provider reads inside the
  /// returned widget, not in this callback.
  final WidgetBuilder? footerBuilder;

  /// Whether this page hides both its own footer and the route-level fallback.
  final bool hideFooter;

  final TrayPageLayout layout;

  /// Optional stable identity: `setView` and `openTray` reuse the page already
  /// bound to a `viewId` instead of stacking another one. It is also safe to
  /// omit for one-off views.
  final String? viewId;

  /// The stable identifier used to recreate this page during restoration.
  ///
  /// A page in a restorable tray must provide this value. The corresponding
  /// [TrayPageRestorer] receives it after the route is recreated.
  final String? restorationId;

  /// Codec-compatible arguments passed to the [TrayPageRestorer].
  final Object? restorationArguments;
}
