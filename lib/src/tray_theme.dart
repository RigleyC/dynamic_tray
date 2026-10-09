import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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

/// The text style for the tray's Material wrapper. Under MaterialApp this is
/// null so Material uses `bodyMedium`. Under CupertinoApp it keeps the ambient
/// Cupertino style instead of the default Material theme's.
TextStyle? trayTextStyleOf(BuildContext context) =>
    context.findAncestorWidgetOfExactType<Theme>() == null
    ? DefaultTextStyle.of(context).style
    : null;
