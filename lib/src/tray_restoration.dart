import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Stores a tray page stack in Flutter's restoration bucket.
class TrayRestorableSnapshot extends RestorableValue<List<Object?>> {
  TrayRestorableSnapshot(this._defaultValue);

  final List<Object?> _defaultValue;

  @override
  List<Object?> createDefaultValue() => List<Object?>.from(_defaultValue);

  @override
  void didUpdateValue(List<Object?>? oldValue) {
    assert(() {
      const StandardMessageCodec().encodeMessage(value);
      return true;
    }());
    notifyListeners();
  }

  @override
  List<Object?> fromPrimitives(Object? serialized) {
    if (serialized is! List) {
      return <Object?>[];
    }
    return List<Object?>.from(serialized);
  }

  @override
  Object? toPrimitives() => value;
}
