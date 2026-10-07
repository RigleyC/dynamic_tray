import 'package:flutter/widgets.dart';

import 'tray_scope.dart';

/// The neutral drag affordance shown at the top of the tray.
///
/// Provides drag accessibility via the drag handle action and a close action
/// for keyboard and screen reader users.
class TrayHandle extends StatelessWidget {
  const TrayHandle({super.key, this.color = const Color(0xFFA1A1AA)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final scope = TrayScope.of(context);
    return Semantics(
      label: 'Drag handle',
      enabled: true,
      onDismiss: scope?.controller.canPop == true
          ? () => scope!.controller.pop<void>()
          : () => scope!.controller.dismiss(),
      child: SizedBox(
        width: 40,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
