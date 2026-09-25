import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'tray_controller.dart';
import 'tray_page.dart';

typedef TraySharedElementFlightBuilder =
    Widget Function(BuildContext context, Widget child);

class TraySharedElement extends StatefulWidget {
  const TraySharedElement({
    super.key,
    required this.tag,
    required this.child,
    this.flightBuilder,
  });

  final Object tag;
  final Widget child;
  final TraySharedElementFlightBuilder? flightBuilder;

  @override
  State<TraySharedElement> createState() => _TraySharedElementState();
}

class _TraySharedElementState extends State<TraySharedElement> {
  final Object _marker = Object();

  @override
  void didUpdateWidget(covariant TraySharedElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag == widget.tag) {
      return;
    }

    final scope = TraySharedElementScope.maybeOf(context);
    if (scope == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scope.registry.unregister(
        page: scope.page,
        tag: oldWidget.tag,
        marker: _marker,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = TraySharedElementScope.maybeOf(context);
    if (scope == null) {
      return widget.child;
    }

    return _TraySharedElementReporter(
      onRectChanged: (renderObject) {
        final rect = scope.toLocalRect(renderObject);
        if (rect == null) {
          scope.registry.unregister(
            page: scope.page,
            tag: widget.tag,
            marker: _marker,
          );
          return;
        }
        scope.registry.register(
          page: scope.page,
          tag: widget.tag,
          marker: _marker,
          rect: rect,
          child: widget.child,
          flightBuilder: widget.flightBuilder,
        );
      },
      onDetached: () {
        scope.registry.unregister(
          page: scope.page,
          tag: widget.tag,
          marker: _marker,
        );
      },
      child: ListenableBuilder(
        listenable: scope.registry,
        child: widget.child,
        builder: (context, child) {
          final transition = scope.transition;
          final hidden =
              transition != null &&
              scope.registry.isFlying(
                transition,
                page: scope.page,
                tag: widget.tag,
                marker: _marker,
              );
          return Opacity(opacity: hidden ? 0 : 1, child: child);
        },
      ),
    );
  }
}

@internal
class TraySharedElementRegistry extends ChangeNotifier {
  final Map<TrayPage<dynamic>, Map<Object, List<_TraySharedElementRecord>>>
  _records = {};
  bool _disposed = false;

  void register({
    required TrayPage<dynamic> page,
    required Object tag,
    required Object marker,
    required Rect rect,
    required Widget child,
    required TraySharedElementFlightBuilder? flightBuilder,
  }) {
    if (_disposed) {
      return;
    }
    final pageRecords = _records.putIfAbsent(page, () => {});
    final next = _TraySharedElementRecord(
      page: page,
      tag: tag,
      marker: marker,
      rect: rect,
      child: child,
      flightBuilder: flightBuilder,
    );
    final tagRecords = pageRecords.putIfAbsent(tag, () => []);
    final existingIndex = tagRecords.indexWhere(
      (record) => identical(record.marker, marker),
    );
    if (existingIndex >= 0) {
      if (tagRecords[existingIndex] == next) {
        return;
      }
      tagRecords[existingIndex] = next;
    } else {
      tagRecords.add(next);
    }
    notifyListeners();
  }

  void unregister({
    required TrayPage<dynamic> page,
    required Object tag,
    required Object marker,
  }) {
    if (_disposed) {
      return;
    }
    final pageRecords = _records[page];
    if (pageRecords == null) {
      return;
    }
    final tagRecords = pageRecords[tag];
    if (tagRecords == null) {
      return;
    }
    tagRecords.removeWhere((record) => identical(record.marker, marker));
    if (tagRecords.isEmpty) {
      pageRecords.remove(tag);
    }
    if (pageRecords.isEmpty) {
      _records.remove(page);
    }
    notifyListeners();
  }

  bool isFlying(
    TrayPageTransition transition, {
    required TrayPage<dynamic> page,
    required Object tag,
    required Object marker,
  }) {
    final match = _match(transition, tag);
    if (match == null) {
      return false;
    }
    final records = _records[page]?[tag];
    final record = records == null || records.isEmpty ? null : records.first;
    return record != null && identical(record.marker, marker);
  }

  List<TraySharedElementMatch> matches(TrayPageTransition transition) {
    if (_disposed) {
      return const [];
    }
    final outgoing = _records[transition.outgoing];
    final incoming = _records[transition.incoming];
    if (outgoing == null || incoming == null) {
      return const [];
    }

    final matches = <TraySharedElementMatch>[];
    for (final entry in outgoing.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final incomingRecords = incoming[entry.key];
      if (incomingRecords == null || incomingRecords.isEmpty) {
        continue;
      }
      final outgoingRecord = entry.value.first;
      final incomingRecord = incomingRecords.first;
      matches.add(
        TraySharedElementMatch(
          tag: entry.key,
          outgoingRect: outgoingRecord.rect,
          incomingRect: incomingRecord.rect,
          child: incomingRecord.child,
          flightBuilder: incomingRecord.flightBuilder,
        ),
      );
    }
    return matches;
  }

  @override
  void dispose() {
    _disposed = true;
    _records.clear();
    super.dispose();
  }

  TraySharedElementMatch? _match(TrayPageTransition transition, Object tag) {
    for (final match in matches(transition)) {
      if (match.tag == tag) {
        return match;
      }
    }
    return null;
  }
}

@internal
class TraySharedElementMatch {
  const TraySharedElementMatch({
    required this.tag,
    required this.outgoingRect,
    required this.incomingRect,
    required this.child,
    required this.flightBuilder,
  });

  final Object tag;
  final Rect outgoingRect;
  final Rect incomingRect;
  final Widget child;
  final TraySharedElementFlightBuilder? flightBuilder;
}

@internal
class TraySharedElementScope
    extends InheritedNotifier<TraySharedElementRegistry> {
  const TraySharedElementScope({
    super.key,
    required TraySharedElementRegistry registry,
    required this.page,
    required this.transition,
    required this.toLocalRect,
    required super.child,
  }) : registry = registry,
       super(notifier: registry);

  final TraySharedElementRegistry registry;
  final TrayPage<dynamic> page;
  final TrayPageTransition? transition;
  final Rect? Function(RenderBox renderObject) toLocalRect;

  static TraySharedElementScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TraySharedElementScope>();
  }

  @override
  bool updateShouldNotify(covariant TraySharedElementScope oldWidget) {
    return page != oldWidget.page ||
        transition?.id != oldWidget.transition?.id ||
        toLocalRect != oldWidget.toLocalRect;
  }
}

class _TraySharedElementRecord {
  const _TraySharedElementRecord({
    required this.page,
    required this.tag,
    required this.marker,
    required this.rect,
    required this.child,
    required this.flightBuilder,
  });

  final TrayPage<dynamic> page;
  final Object tag;
  final Object marker;
  final Rect rect;
  final Widget child;
  final TraySharedElementFlightBuilder? flightBuilder;

  @override
  bool operator ==(Object other) {
    return other is _TraySharedElementRecord &&
        identical(other.marker, marker) &&
        other.rect == rect &&
        other.child == child &&
        other.flightBuilder == flightBuilder;
  }

  @override
  int get hashCode => Object.hash(marker, rect, child, flightBuilder);
}

class _TraySharedElementReporter extends SingleChildRenderObjectWidget {
  const _TraySharedElementReporter({
    required this.onRectChanged,
    required this.onDetached,
    super.child,
  });

  final ValueChanged<RenderBox> onRectChanged;
  final VoidCallback onDetached;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTraySharedElementReporter(onRectChanged, onDetached);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTraySharedElementReporter renderObject,
  ) {
    renderObject
      ..onRectChanged = onRectChanged
      ..onDetached = onDetached;
  }
}

class _RenderTraySharedElementReporter extends RenderProxyBox {
  _RenderTraySharedElementReporter(this.onRectChanged, this.onDetached);

  ValueChanged<RenderBox> onRectChanged;
  VoidCallback onDetached;
  Rect? _lastRect;

  @override
  void performLayout() {
    super.performLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached || !hasSize) {
        return;
      }
      final topLeft = localToGlobal(Offset.zero);
      final rect = topLeft & size;
      if (_lastRect == rect) {
        return;
      }
      _lastRect = rect;
      onRectChanged(this);
    });
  }

  @override
  void detach() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!attached) {
        onDetached();
      }
    });
    super.detach();
  }
}
