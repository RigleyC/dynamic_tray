import 'package:flutter/widgets.dart';

/// A framework-neutral header layout for tray pages.
///
/// Supply the widgets for each slot so the consuming app can keep its own
/// Material, Cupertino, or custom visual language.
class TrayHeader extends StatelessWidget {
  const TrayHeader({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.spacing = 12,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final hasText = title != null || subtitle != null;
    final hasTwoButtons = leading != null && trailing != null;
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          if (hasText || trailing != null) SizedBox(width: spacing),
        ],
        if (hasText)
          Expanded(
            child: Align(
              alignment:
                  hasTwoButtons ? Alignment.center : Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    hasTwoButtons
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                children: [
                  if (title != null) title!,
                  if (subtitle != null) subtitle!,
                ],
              ),
            ),
          ),
        if (trailing != null) ...[
          if (hasText || leading != null) SizedBox(width: spacing),
          trailing!,
        ],
      ],
    );
  }
}
