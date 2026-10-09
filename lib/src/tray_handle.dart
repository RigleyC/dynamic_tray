import 'package:flutter/widgets.dart';

import 'tray_theme.dart';

/// The neutral drag affordance shown at the top of the tray.
class TrayHandle extends StatelessWidget {
  const TrayHandle({super.key, this.color});

  /// Overrides the theme-derived handle color when set.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor =
        color ??
        (trayBrightnessOf(context) == Brightness.dark
            ? const Color(0xFFA1A1AA)
            : const Color(0xFFD4D4D8));
    return SizedBox(
      width: 40,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resolvedColor,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
