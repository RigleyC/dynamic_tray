import 'package:corner_radius_plugin/corner_radius_plugin.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';

BorderRadius? _deviceCornerRadii;
Future<void>? _pendingDeviceCornerRadii;

/// Device display corner radii in logical pixels, or `null` when unavailable.
///
/// Resolving this goes through a platform channel, so it cannot be awaited
/// before the first tray frame. Reading it while the tray is opening and
/// rebuilding on completion would rebuild every page mid-animation and let the
/// geometry spring animate a corner radius the first frame never showed.
/// Resolve it during app start with [warmUpTrayDeviceCorners] instead, then
/// read the resolved value synchronously on every build.
BorderRadius? get trayDeviceCornerRadii => _deviceCornerRadii;

/// Starts reading [trayDeviceCornerRadii] once per process.
///
/// Call this while the app starts, before the first tray can be opened.
/// Repeated calls share the first read. Platforms without a plugin
/// implementation, including web, resolve to `null` and the tray falls back to
/// `MediaQuery.displayCornerRadii`.
Future<void> warmUpTrayDeviceCorners() {
  return _pendingDeviceCornerRadii ??= _readDeviceCornerRadii();
}

Future<void> _readDeviceCornerRadii() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

  try {
    final radii = await CornerRadiusPlugin.init();
    _deviceCornerRadii = BorderRadius.only(
      topLeft: Radius.circular(radii.topLeft),
      topRight: Radius.circular(radii.topRight),
      bottomLeft: Radius.circular(radii.bottomLeft),
      bottomRight: Radius.circular(radii.bottomRight),
    );
  } on Object {
    // Host apps without the plugin keep the MediaQuery geometry.
  }
}
