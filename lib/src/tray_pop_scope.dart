import 'package:flutter/widgets.dart';

/// Blocks the system back gesture and back button while [canPop] is false.
///
/// Place it inside the page it protects, for example around a form with unsaved
/// changes. Only the visible page blocks back: a page kept behind the current
/// one has its tickers disabled, so it does not stop the stack from popping.
///
/// [onPopBlocked] runs each time a back press is refused, so the page can ask
/// the user to confirm the discard.
class TrayPopScope extends StatelessWidget {
  const TrayPopScope({
    super.key,
    required this.canPop,
    this.onPopBlocked,
    required this.child,
  });

  final bool canPop;
  final VoidCallback? onPopBlocked;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isVisible = TickerMode.valuesOf(context).enabled;
    return PopScope(
      canPop: canPop || !isVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onPopBlocked?.call();
      },
      child: child,
    );
  }
}
