import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'tray_page.dart';
import 'tray_presentation.dart';

class TrayController extends ChangeNotifier {
  TrayController({
    required TrayPage<dynamic> initialPage,
    TrayPageRestorer? pageRestorer,
  }) : _pageRestorer = pageRestorer {
    _validatePage(initialPage);
    _entries.add(_TrayEntry<dynamic>(initialPage));
    _presentation = initialPage.presentation;
  }

  final List<_TrayEntry<dynamic>> _entries = [];
  final TrayPageRestorer? _pageRestorer;
  NavigatorState? _navigator;
  TrayPresentation _presentation = TrayPresentation.content;
  TrayLifecycle _lifecycle = TrayLifecycle.opening;
  TrayPageTransition? _transition;
  int _nextTransitionId = 0;

  TrayPage<dynamic> get currentPage => _entries.last.page;
  TrayPresentation get presentation => _presentation;
  TrayLifecycle get lifecycle => _lifecycle;
  bool get canPop => _entries.length > 1;
  TrayPageTransition? get transition => _transition;
  bool get isRestorable => _pageRestorer != null;

  @internal
  List<TrayPage<dynamic>> get pages => [
    for (final entry in _entries) entry.page,
  ];

  Future<T?> push<T>(TrayPage<T> page) {
    _validatePage(page);
    final outgoing = currentPage;
    final entry = _TrayEntry<T>(page);
    _entries.add(entry);
    _presentation = page.presentation;
    _transition = TrayPageTransition(
      id: _nextTransitionId++,
      outgoing: outgoing,
      incoming: page,
      isPush: true,
    );
    notifyListeners();
    return entry.completer.future;
  }

  bool pop<T>([T? result]) {
    if (!canPop) {
      dismiss(result);
      return true;
    }

    final outgoing = _entries.last.page;
    final incoming = _entries[_entries.length - 2].page;
    final entry = _entries.removeLast();
    entry.complete(result);
    _presentation = _entries.last.page.presentation;
    _transition = TrayPageTransition(
      id: _nextTransitionId++,
      outgoing: outgoing,
      incoming: incoming,
      isPush: false,
    );
    notifyListeners();
    return true;
  }

  void present(TrayPresentation presentation) {
    if (_presentation == presentation) {
      return;
    }
    _presentation = presentation;
    notifyListeners();
  }

  void expand() => present(TrayPresentation.expanded);

  void collapse() => present(TrayPresentation.content);

  void fullscreen() => present(TrayPresentation.fullscreen);

  /// Returns the current page stack in StandardMessageCodec-compatible data.
  @internal
  List<Object?> get restorationSnapshot => [
    for (var index = 0; index < _entries.length; index++)
      <String, Object?>{
        'id': _entries[index].page.restorationId,
        'arguments': _entries[index].page.restorationArguments,
        'presentation':
            (index == _entries.length - 1
                    ? _presentation
                    : _entries[index].page.presentation)
                .name,
      },
  ];

  /// Rebuilds the page stack from data previously returned by
  /// [restorationSnapshot].
  @internal
  void restoreFromSnapshot(List<Object?> snapshot, {bool notify = true}) {
    final pageRestorer = _pageRestorer;
    if (pageRestorer == null || snapshot.isEmpty) {
      return;
    }

    final restoredPages = <TrayPage<dynamic>>[];
    var restoredPresentation = TrayPresentation.content;
    for (final item in snapshot) {
      if (item is! Map) {
        throw StateError('Invalid dynamic_tray restoration entry.');
      }
      final restorationId = item['id'];
      if (restorationId is! String || restorationId.isEmpty) {
        throw StateError('A restored tray page must have a non-empty ID.');
      }
      final page = pageRestorer(restorationId, item['arguments']);
      if (page.restorationId != restorationId) {
        throw StateError(
          'The restored TrayPage must keep restorationId "$restorationId".',
        );
      }
      restoredPages.add(page);
      restoredPresentation = page.presentation;
      final savedPresentation = item['presentation'];
      if (savedPresentation is String) {
        restoredPresentation = _presentationFromName(savedPresentation);
      }
    }

    for (final entry in _entries) {
      entry.complete(null);
    }
    _entries
      ..clear()
      ..addAll([for (final page in restoredPages) _TrayEntry<dynamic>(page)]);
    _presentation = restoredPresentation;
    _transition = null;
    if (notify) {
      notifyListeners();
    }
  }

  void _validatePage(TrayPage<dynamic> page) {
    if (_pageRestorer == null) {
      return;
    }
    final restorationId = page.restorationId;
    if (restorationId == null || restorationId.isEmpty) {
      throw ArgumentError.value(
        page,
        'page',
        'A restorable tray page must define a non-empty restorationId.',
      );
    }
  }

  TrayPresentation _presentationFromName(String name) {
    for (final presentation in TrayPresentation.values) {
      if (presentation.name == name) {
        return presentation;
      }
    }
    throw StateError('Unknown dynamic_tray presentation "$name".');
  }

  @internal
  void completePageTransition(int id) {
    if (_transition?.id != id) {
      return;
    }
    _transition = null;
    notifyListeners();
  }

  void dismiss<T>([T? result]) {
    _setLifecycle(TrayLifecycle.closing);
    final navigator = _navigator;
    if (navigator == null) {
      completeRoute(result);
      return;
    }
    navigator.pop<T>(result);
  }

  void _setLifecycle(TrayLifecycle lifecycle) {
    if (_lifecycle == lifecycle) {
      return;
    }
    _lifecycle = lifecycle;
    notifyListeners();
  }

  @internal
  void markOpening() => _setLifecycle(TrayLifecycle.opening);

  @internal
  void markOpen() {
    if (_lifecycle == TrayLifecycle.opening) {
      _setLifecycle(TrayLifecycle.open);
    }
  }

  @internal
  void markClosing() => _setLifecycle(TrayLifecycle.closing);

  @internal
  void markClosed() => _setLifecycle(TrayLifecycle.closed);

  @internal
  void completeRoute([Object? result]) {
    while (_entries.length > 1) {
      _entries.removeLast().complete(null);
    }
    _entries.single.complete(result);
  }

  @internal
  void attachNavigator(NavigatorState navigator) {
    _navigator = navigator;
  }

  @internal
  void detachNavigator() {
    _navigator = null;
  }
}

enum TrayLifecycle { opening, open, closing, closed }

class _TrayEntry<T> {
  _TrayEntry(this.page);

  final TrayPage<T> page;
  final Completer<T?> completer = Completer<T?>();

  void complete(Object? result) {
    if (!completer.isCompleted) {
      completer.complete(result as T?);
    }
  }
}

class TrayPageTransition {
  const TrayPageTransition({
    required this.id,
    required this.outgoing,
    required this.incoming,
    required this.isPush,
  });

  final int id;
  final TrayPage<dynamic> outgoing;
  final TrayPage<dynamic> incoming;
  final bool isPush;
}
