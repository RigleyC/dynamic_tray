import 'package:flutter/widgets.dart';

/// The neutral drag affordance shown at the top of the tray.
class TrayHandle extends StatelessWidget {
  const TrayHandle({super.key, this.color = const Color(0xFFA1A1AA)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
