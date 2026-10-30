import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'tray_controller.dart';
import 'tray_page.dart';

typedef TraySharedElementFlightBuilder =
    Widget Function(BuildContext context, Widget child);

/// An element shared between two tray pages.
///
/// A [TraySharedElement] with a [child] owns the content. The content is one
/// live element, so its State survives the transition: it flies inside the
/// tray and lands in the destination. The destination declares a
/// [TraySharedElement.target] with the bounds it reserves, and receives that
/// live content instead of building its own.
class TraySharedElement extends StatefulWidget {
  const TraySharedElement({
    super.key,
    required this.tag,
    required this.child,
    this.flightBuilder,
  }) : width = null,
       height = null;

  /// An empty destination for the content of the same [tag] on another page.
  ///
  /// It reserves [width] by [height] and shows the live content while the
  /// page is current.
  const TraySharedElement.target({
    super.key,
    required this.tag,
    required this.width,
    required this.height,
    this.flightBuilder,
  }) : child = null;

  final Object tag;
  final Widget? child;
  final double? width;
  final double? height;
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

  Widget _reservedBounds(Size? size) {
    return SizedBox(width: size?.width, height: size?.height);
  }

  @override
  Widget build(BuildContext context) {
    final scope = TraySharedElementScope.maybeOf(context);
    if (scope == null) {
      return widget.child ??
          _reservedBounds(
            widget.width == null ? null : Size(widget.width!, widget.height!),
          );
    }

    final registry = scope.registry;
    return _TraySharedElementReporter(
      onLayout: (renderObject) {
        registry.register(
          page: scope.page,
          tag: widget.tag,
          marker: _marker,
          renderBox: renderObject,
          measure: scope.toLocalRect,
          child: widget.child,
          flightBuilder: widget.flightBuilder,
        );
      },
      onDetached: () {
        registry.unregister(
          page: scope.page,
          tag: widget.tag,
          marker: _marker,
        );
      },
      child: ListenableBuilder(
        listenable: registry,
        builder: (context, _) {
          final showsContent = registry.showsContent(
            page: scope.page,
            tag: widget.tag,
            marker: _marker,
            current: scope.current,
            transition: scope.transition,
          );
          final content = showsContent
              ? widget.child ?? registry.contentChildFor(widget.tag)
              : null;
          if (content == null) {
            final target = widget.width == null
                ? null
                : Size(widget.width!, widget.height!);
            return _reservedBounds(
              target ??
                  registry.sizeOf(
                    page: scope.page,
                    tag: widget.tag,
                    marker: _marker,
                  ),
            );
          }
          final live = KeyedSubtree(
            key: registry.contentKeyFor(widget.tag),
            child: content,
          );
          if (widget.child != null) {
            return live;
          }
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: live,
          );
        },
      ),
    );
  }
}

@internal
class TraySharedElementRegistry extends ChangeNotifier {
  final Map<TrayPage<dynamic>, Map<Object, List<_TraySharedElementRecord>>>
  _records = {};
  // Pages whose content has been laid out. A transition waits for the incoming
  // page before it starts, so its destinations exist when the flight begins.
  final Set<TrayPage<dynamic>> _laidOutPages = {};
  // One key per tag. The live content keeps its element when it moves between
  // the owner, the flight and the destination, so its State survives.
  final Map<Object, GlobalKey> _contentKeys = {};
  final Map<Object, Widget> _contentChildren = {};
  // Outgoing rects are read once, when their transition starts, while the
  // outgoing page is still at rest. Incoming rects are read live, every frame,
  // because the incoming page grows and scales while the flight runs.
  final Map<Object, Rect> _outgoingRects = {};
  final Map<Object, Rect> _lastIncomingRects = {};
  int? _snapshotTransitionId;
  bool _notifyScheduled = false;
  bool _disposed = false;

  GlobalKey contentKeyFor(Object tag) {
    return _contentKeys.putIfAbsent(tag, () => GlobalKey());
  }

  /// The most recent content of [tag], used by destinations that own none.
  Widget? contentChildFor(Object tag) => _contentChildren[tag];

  Size? sizeOf({
    required TrayPage<dynamic> page,
    required Object tag,
    required Object marker,
  }) {
    final records = _records[page]?[tag];
    if (records == null) {
      return null;
    }
    for (final record in records) {
      if (identical(record.marker, marker)) {
        return record.size;
      }
    }
    return null;
  }

  /// Records a shared element once its page has laid it out. The notification
  /// waits for the end of the frame, so no rebuild runs during layout.
  void register({
    required TrayPage<dynamic> page,
    required Object tag,
    required Object marker,
    required RenderBox renderBox,
    required Rect? Function(RenderBox renderObject) measure,
    required Widget? child,
    required TraySharedElementFlightBuilder? flightBuilder,
  }) {
    if (_disposed) {
      return;
    }
    if (child != null) {
      _contentChildren[tag] = child;
    }
    final pageRecords = _records.putIfAbsent(page, () => {});
    final next = _TraySharedElementRecord(
      page: page,
      tag: tag,
      marker: marker,
      renderBox: renderBox,
      measure: measure,
      child: child,
      flightBuilder: flightBuilder,
      size: renderBox.size,
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
    _scheduleNotify();
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
    _scheduleNotify();
  }

  /// Marks [page] as laid out, which lets a transition to it start.
  void pageLaidOut(TrayPage<dynamic> page) {
    if (!_disposed && _laidOutPages.add(page)) {
      _scheduleNotify();
    }
  }

  /// Drops the layout state of pages that left the stack.
  void retainPages(Set<TrayPage<dynamic>> pages) {
    _laidOutPages.removeWhere((page) => !pages.contains(page));
  }

  /// Whether [transition] can start: its incoming page is laid out and every
  /// shared element it shares with the outgoing page has a measured rect.
  bool isReady(TrayPageTransition transition) {
    if (_disposed) {
      return false;
    }
    beginTransition(transition);
    if (!_laidOutPages.contains(transition.incoming)) {
      return false;
    }
    final outgoing = _records[transition.outgoing];
    final incoming = _records[transition.incoming];
    if (outgoing == null || incoming == null) {
      return true;
    }
    for (final tag in outgoing.keys) {
      final incomingRecords = incoming[tag];
      if (incomingRecords != null &&
          incomingRecords.isNotEmpty &&
          incomingRecords.first.rect == null) {
        return false;
      }
    }
    return true;
  }

  /// Whether the element [marker] on [page] renders the live content now.
  ///
  /// At rest, the current page's first element shows it. During a transition
  /// the flight shows it while the pair matches, and the outgoing element keeps
  /// it when nothing matches, so it leaves with its page.
  bool showsContent({
    required TrayPage<dynamic> page,
    required Object tag,
    required Object marker,
    required bool current,
    required TrayPageTransition? transition,
  }) {
    final records = _records[page]?[tag];
    if (records == null ||
        records.isEmpty ||
        !identical(records.first.marker, marker)) {
      return false;
    }
    if (transition == null) {
      return current;
    }
    if (_match(transition, tag) != null) {
      return false;
    }
    return identical(page, transition.outgoing);
  }

  /// Reads the outgoing rects. Call it as the transition starts, before a frame
  /// moves the outgoing page, so the flight starts from the page's resting bounds.
  /// The read repeats until the outgoing page has registered, because a page
  /// pushed in the same frame it is laid out registers after the push.
  void beginTransition(TrayPageTransition transition) {
    if (_disposed) {
      return;
    }
    if (_snapshotTransitionId != transition.id) {
      _snapshotTransitionId = transition.id;
      _outgoingRects.clear();
      _lastIncomingRects.clear();
    }
    if (_outgoingRects.isNotEmpty) {
      return;
    }
    final outgoing = _records[transition.outgoing];
    if (outgoing == null) {
      return;
    }
    for (final entry in outgoing.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final rect = entry.value.first.rect;
      if (rect != null) {
        _outgoingRects[entry.key] = rect;
      }
    }
  }

  List<TraySharedElementMatch> matches(TrayPageTransition transition) {
    if (_disposed) {
      return const [];
    }
    beginTransition(transition);
    final outgoing = _records[transition.outgoing];
    final incoming = _records[transition.incoming];
    if (outgoing == null || incoming == null) {
      return const [];
    }

    final matches = <TraySharedElementMatch>[];
    for (final entry in incoming.entries) {
      final outgoingRect = _outgoingRects[entry.key];
      final outgoingRecords = outgoing[entry.key];
      if (outgoingRect == null ||
          outgoingRecords == null ||
          outgoingRecords.isEmpty ||
          entry.value.isEmpty) {
        continue;
      }
      // The live content comes from the outgoing element, or from the most
      // recent owner when the outgoing element is a destination.
      final content = outgoingRecords.first.child ?? _contentChildren[entry.key];
      final incomingRecord = entry.value.first;
      final incomingRect = incomingRecord.rect ?? _lastIncomingRects[entry.key];
      if (content == null || incomingRect == null) {
        continue;
      }
      _lastIncomingRects[entry.key] = incomingRect;
      matches.add(
        TraySharedElementMatch(
          tag: entry.key,
          outgoingRect: outgoingRect,
          incomingRect: incomingRect,
          child: content,
          contentKey: contentKeyFor(entry.key),
          flightBuilder: incomingRecord.flightBuilder,
        ),
      );
    }
    return matches;
  }

  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) {
      return;
    }
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _records.clear();
    _laidOutPages.clear();
    _outgoingRects.clear();
    _lastIncomingRects.clear();
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
    required this.contentKey,
    required this.flightBuilder,
  });

  final Object tag;
  final Rect outgoingRect;
  final Rect incomingRect;
  final Widget child;
  final GlobalKey contentKey;
  final TraySharedElementFlightBuilder? flightBuilder;
}

@internal
class TraySharedElementScope
    extends InheritedNotifier<TraySharedElementRegistry> {
  const TraySharedElementScope({
    super.key,
    required TraySharedElementRegistry registry,
    required this.page,
    required this.current,
    required this.transition,
    required this.toLocalRect,
    required super.child,
  }) : registry = registry,
       super(notifier: registry);

  final TraySharedElementRegistry registry;
  final TrayPage<dynamic> page;
  final bool current;
  final TrayPageTransition? transition;
  final Rect? Function(RenderBox renderObject) toLocalRect;

  static TraySharedElementScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TraySharedElementScope>();
  }

  @override
  bool updateShouldNotify(covariant TraySharedElementScope oldWidget) {
    return page != oldWidget.page ||
        current != oldWidget.current ||
        transition?.id != oldWidget.transition?.id ||
        toLocalRect != oldWidget.toLocalRect;
  }
}

class _TraySharedElementRecord {
  const _TraySharedElementRecord({
    required this.page,
    required this.tag,
    required this.marker,
    required this.renderBox,
    required this.measure,
    required this.child,
    required this.flightBuilder,
    required this.size,
  });

  final TrayPage<dynamic> page;
  final Object tag;
  final Object marker;
  final RenderBox renderBox;
  final Rect? Function(RenderBox renderObject) measure;
  final Widget? child;
  final TraySharedElementFlightBuilder? flightBuilder;
  final Size size;

  /// Current bounds in the tray's content space. Read at the time of the call,
  /// so the transforms of the page are included while the surface stays out.
  Rect? get rect => renderBox.attached && renderBox.hasSize
      ? measure(renderBox)
      : null;

  @override
  bool operator ==(Object other) {
    return other is _TraySharedElementRecord &&
        identical(other.marker, marker) &&
        identical(other.renderBox, renderBox) &&
        other.measure == measure &&
        other.child == child &&
        other.flightBuilder == flightBuilder &&
        other.size == size;
  }

  @override
  int get hashCode =>
      Object.hash(marker, renderBox, measure, child, flightBuilder, size);
}

class _TraySharedElementReporter extends SingleChildRenderObjectWidget {
  const _TraySharedElementReporter({
    required this.onLayout,
    required this.onDetached,
    super.child,
  });

  final ValueChanged<RenderBox> onLayout;
  final VoidCallback onDetached;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTraySharedElementReporter(onLayout, onDetached);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTraySharedElementReporter renderObject,
  ) {
    renderObject
      ..onLayout = onLayout
      ..onDetached = onDetached;
  }
}

class _RenderTraySharedElementReporter extends RenderProxyBox {
  _RenderTraySharedElementReporter(this.onLayout, this.onDetached);

  ValueChanged<RenderBox> onLayout;
  VoidCallback onDetached;

  @override
  void performLayout() {
    super.performLayout();
    if (hasSize) {
      onLayout(this);
    }
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
