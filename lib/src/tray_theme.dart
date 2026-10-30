import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as flutter_material;
import 'package:material_ui/material_ui.dart';

// Material's Theme widget also provides a CupertinoTheme built from the
// Material theme, so reading CupertinoTheme works under both MaterialApp and
// CupertinoApp.

/// The brightness the tray paints with.
Brightness trayBrightnessOf(BuildContext context) =>
    CupertinoTheme.of(context).brightness ??
    MediaQuery.platformBrightnessOf(context);

/// The tray background when no `surfaceColor` is given: the app's background
/// color, resolved at the elevated level like an iOS sheet.
Color traySurfaceColorOf(BuildContext context) => CupertinoDynamicColor.resolve(
  CupertinoTheme.of(context).scaffoldBackgroundColor,
  context,
);

/// The text style for the tray's Material wrapper. Under a Material app (either
/// Flutter's or material_ui's) this is null so Material uses `bodyMedium` from
/// that app's theme. Under CupertinoApp it keeps the ambient Cupertino style.
///
/// The check has to look for both Theme classes. A MaterialApp provides
/// Flutter's Theme, which material_ui's Theme type does not match.
TextStyle? trayTextStyleOf(BuildContext context) {
  final underMaterialTheme =
      context.findAncestorWidgetOfExactType<Theme>() != null ||
      context.findAncestorWidgetOfExactType<flutter_material.Theme>() != null;
  return underMaterialTheme ? null : DefaultTextStyle.of(context).style;
}
