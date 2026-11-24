part of 'tray_surface.dart';

class _TrayMotionCoordinator extends StatefulWidget {
  const _TrayMotionCoordinator({
    super.key,
    required this.controller,
    required this.motionTheme,
    required this.geometry,
    required this.geometryIsMeasured,
    required this.pages,
    required this.transition,
    required this.viewportHeight,
    required this.keyboardInset,
    required this.closing,
    required this.contentBuilder,
    required this.builder,
  });

  final TrayController controller;
  final TrayMotionTheme motionTheme;
  final TrayGeometry geometry;
  final bool geometryIsMeasured;
  final List<TrayPage<dynamic>> pages;
  final TrayPageTransition? transition;

  /// Height of the route viewport the tray is laid out in.
  final double viewportHeight;

  final double keyboardInset;
  final bool closing;
  final Widget Function(BuildContext, _TrayVisualState) contentBuilder;
  final Widget Function(BuildContext, _TrayVisualState, Widget) builder;

  @override
  State<_TrayMotionCoordinator> createState() => _TrayMotionCoordinatorState();
}

class _TrayMotionCoordinatorState extends State<_TrayMotionCoordinator>
    with TickerProviderStateMixin {
  late final MotionController<TrayGeometry> _geometryMotion;
  late final SingleMotionController _presentationMotion;
  late final SingleMotionController _dragMotion;
  final Map<TrayPage<dynamic>, SingleMotionController> _pageMotions = {};
  final Map<TrayPage<dynamic>, double> _pageTargets = {};
  // Merged once per change of _pageMotions, so the AnimatedBuilder keeps one
  // listenable across frames.
  late Listenable _allMotions;

  // A page change starts once its incoming page is laid out, and settles once
  // the page motions end.
  int? _startedTransitionId;
  int? _settledTransitionId;
  bool _dismissCompleted = false;

  double _dragOrigin = 0;
  bool _receivedFirstMeasurement = false;
  TrayGeometry? _pendingFirstGeometry;
  // Last geometry the motion was sent to. Repeated reports of the same target
  // must not restart the spring.
  TrayGeometry? _geometryTarget;

  TrayMotionTheme get _motion => widget.motionTheme;

  @override
  void initState() {
    super.initState();
    _geometryMotion = MotionController<TrayGeometry>(
      motion: _motion.geometry,
      vsync: this,
      converter: const TrayGeometryMotionConverter(),
      initialValue: widget.geometry,
    );
    _geometryTarget = widget.geometry;
    _presentationMotion = SingleMotionController(
      motion: _motion.route,
      vsync: this,
      initialValue: 0,
    )..addStatusListener(_handlePresentationStatus);
    _dragMotion = SingleMotionController(
      motion: _motion.interactive,
      vsync: this,
    );
    widget.controller.backGesture.addListener(_handleBackGesture);
    _syncPageMotions();
    // The surface is still out of view while its first layout is measured.
    if (!widget.closing) {
      _presentationMotion.animateTo(1);
    } else {
      _completeDismissAfterFrame();
    }
  }

  @override
  void didUpdateWidget(covariant _TrayMotionCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.backGesture.removeListener(_handleBackGesture);
      widget.controller.backGesture.addListener(_handleBackGesture);
    }
    if (!oldWidget.closing && widget.closing) {
      if (_presentationMotion.value <= 0.001) {
        _completeDismissAfterFrame();
      } else {
        _presentationMotion.motion = _motion.close;
        _presentationMotion.animateTo(0);
      }
      return;
    }
    // A close can begin before the first measurement arrives. That late
    // measurement must not reopen the tray.
    if (widget.closing) {
      return;
    }
    final pageSequenceChanged = !_samePageSequence(
      oldWidget.pages,
      widget.pages,
    );
    final transitionChanged = oldWidget.transition?.id != widget.transition?.id;
    if (widget.geometry != oldWidget.geometry &&
        widget.geometry != _geometryTarget &&
        (!pageSequenceChanged || widget.geometryIsMeasured)) {
      // The keyboard animates on the system side and the tray follows it on
      // each frame, so a keyboard-only change snaps instead of lagging behind.
      final keyboardOnlyChange =
          oldWidget.keyboardInset != widget.keyboardInset &&
          !transitionChanged &&
          !pageSequenceChanged;
      if (_receivedFirstMeasurement && !keyboardOnlyChange) {
        _animateGeometryTo(widget.geometry);
      } else {
        _snapGeometry(widget.geometry);
      }
    }
    if (transitionChanged || pageSequenceChanged) {
      _syncPageMotions();
    }
  }

  @override
  void dispose() {
    widget.controller.backGesture.removeListener(_handleBackGesture);
    _geometryMotion.dispose();
    _presentationMotion.dispose();
    _dragMotion.dispose();
    for (final motion in _pageMotions.values) {
      motion.dispose();
    }
    super.dispose();
  }

  void _animateGeometryTo(TrayGeometry geometry) {
    _geometryTarget = geometry;
    _geometryMotion.motion = _motion.geometry;
    _geometryMotion.animateTo(geometry);
  }

  void _snapGeometry(TrayGeometry geometry) {
    _geometryTarget = geometry;
    _geometryMotion.value = geometry;
  }

  /// Runs during layout when the current page reports a new size.
  ///
  /// Starting a motion here is safe: Motor starts at the current value and
  /// does not notify listeners until its first tick.
  void reportMeasuredGeometry(TrayGeometry geometry) {
    if (!mounted || widget.closing) return;
    if (!_receivedFirstMeasurement || _pendingFirstGeometry != null) {
      // The tray is still out of view, so the first size snaps. Setting the
      // value notifies listeners, which must not happen during layout.
      final scheduled = _pendingFirstGeometry != null;
      _pendingFirstGeometry = geometry;
      if (scheduled) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pending = _pendingFirstGeometry;
        _pendingFirstGeometry = null;
        _receivedFirstMeasurement = true;
        if (mounted && !widget.closing && pending != null) {
          _snapGeometry(pending);
        }
      });
      return;
    }
    if (geometry != _geometryTarget) {
      _animateGeometryTo(geometry);
    }
  }

  /// Runs during layout when [page] is current and reports its size. A page
  /// change waits for this, so its incoming page and shared elements exist.
  /// Starting the motion here, in the same frame, keeps the first frame of the
  /// change from being an idle one.
  void pageLaidOut(TrayPage<dynamic> page) {
    final transition = widget.transition;
    if (transition == null ||
        !identical(transition.incoming, page) ||
        _startedTransitionId == transition.id) {
      return;
    }
    _startedTransitionId = transition.id;
    _syncPageMotions();
  }

  bool _samePageSequence(
    List<TrayPage<dynamic>> first,
    List<TrayPage<dynamic>> second,
  ) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (!identical(first[index], second[index])) return false;
    }
    return true;
  }

  void _handlePresentationStatus(AnimationStatus status) {
    // Motor reports a return to 0 as completed when 0 was not the initial
    // value, so the value decides which end was reached.
    if (!mounted || status.isAnimating) return;
    final value = _presentationMotion.value;
    if (widget.closing && value <= 0.001) {
      _completeDismissAfterFrame();
    } else if (value >= 0.999) {
      widget.controller.markOpen();
    }
  }

  void _completeDismissAfterFrame() {
    if (_dismissCompleted) return;
    _dismissCompleted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.completeDismissAnimation();
    });
  }

  void _syncPageMotions() {
    final transition = widget.transition;
    final retainedPages = widget.pages.toSet();
    var keysChanged = false;
    for (final page in retainedPages) {
      if (_pageMotions.containsKey(page)) continue;
      keysChanged = true;
      _pageTargets[page] = 0;
      _pageMotions[page] = SingleMotionController(
        motion: _motion.effects,
        vsync: this,
        // The first page is already present when the tray opens. Only later
        // page changes fade.
        initialValue:
            transition == null && identical(page, widget.controller.currentPage)
            ? 1
            : 0,
      )..addStatusListener(_handlePageMotionStatus);
    }
    for (final page in _pageMotions.keys.toList()) {
      if (!retainedPages.contains(page)) {
        keysChanged = true;
        _pageTargets.remove(page);
        _pageMotions.remove(page)?.dispose();
      }
    }
    if (keysChanged) {
      _allMotions = Listenable.merge([
        _geometryMotion,
        _presentationMotion,
        _dragMotion,
        ..._pageMotions.values,
      ]);
    }
    if (transition != null && _startedTransitionId != transition.id) {
      return;
    }
    for (final MapEntry(key: page, value: motion) in _pageMotions.entries) {
      final target = identical(page, widget.controller.currentPage) ? 1.0 : 0.0;
      if (_pageTargets[page] == target) continue;
      _pageTargets[page] = target;
      if ((motion.value - target).abs() < 0.001 && !motion.isAnimating) {
        continue;
      }
      motion.motion = target == 1 ? _motion.effects : _motion.effectsExit;
      motion.animateTo(target);
    }
    _trySettleTransition();
  }

  void _handlePageMotionStatus(AnimationStatus status) {
    if (!status.isAnimating) _trySettleTransition();
  }

  // The height may still be moving. Shared-element flights read their
  // destination live in the same content space, so they hand over without a
  // jump, and the next navigation does not wait for the height spring.
  void _trySettleTransition() {
    final transitionId = widget.transition?.id;
    if (transitionId == null ||
        _startedTransitionId != transitionId ||
        _settledTransitionId == transitionId ||
        _pageMotions.values.any((motion) => motion.isAnimating)) {
      return;
    }
    _settledTransitionId = transitionId;
    // Status listeners and layout callbacks run mid-frame; the controller
    // notifies its listeners, so it waits for the frame to end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.completePageTransition(transitionId);
    });
  }

  void beginDrag() {
    _dragOrigin = _dragMotion.value;
    _dragMotion.stop(canceled: true);
  }

  void dragTo(double translationY) {
    _dragMotion.value = math.max(0.0, _dragOrigin + translationY);
  }

  // The back gesture moves the tray with the same offset as a handle drag.
  // Commit closes or pops it; cancel springs it back. A commit that closes the
  // tray keeps the offset, so the close continues from where the gesture left.
  void _handleBackGesture() {
    final progress = widget.controller.backGesture.value;
    if (progress != null) {
      _dragMotion.stop(canceled: true);
      _dragMotion.value = progress * _geometryMotion.value.rect.height;
      return;
    }
    if (widget.controller.lifecycle == TrayLifecycle.closing) return;
    cancelDrag();
  }

  // The Expo Dynamic Tray thresholds.
  static const _dismissDistance = 110.0;
  static const _dismissVelocity = 1000.0;

  void settleDrag(double velocityY) {
    if (_dragMotion.value > _dismissDistance || velocityY > _dismissVelocity) {
      widget.controller.dismiss();
      // The controller refuses a dismiss while another route covers the tray.
      if (widget.controller.lifecycle == TrayLifecycle.closing) return;
    }
    _dragMotion.motion = _motion.interactive;
    _dragMotion.animateTo(0, withVelocity: velocityY);
  }

  void cancelDrag() {
    _dragMotion.motion = _motion.interactive;
    _dragMotion.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _allMotions,
      builder: (context, _) {
        final geometry = _geometryMotion.value;
        final presentation = _presentationMotion.value.clamp(0.0, 1.0);
        final travel = switch (_motion.travel) {
          FixedTrayTravel(:final distance) => distance,
          // Clears the viewport and no more, so no frame of the spring is
          // spent below the visible area.
          MeasuredTrayTravel(:final hiddenGap) => math.max(
            0.0,
            widget.viewportHeight +
                hiddenGap -
                geometry.rect.top +
                widget.keyboardInset,
          ),
        };
        final dragFade = _motion.dragFadeDistance <= 0
            ? 0.0
            : (_dragMotion.value / _motion.dragFadeDistance).clamp(0.0, 1.0);
        final visualState = _TrayVisualState(
          geometry: geometry,
          surfaceOffset: Offset(
            0,
            travel * (1 - presentation) +
                _dragMotion.value -
                widget.keyboardInset,
          ),
          backdropOpacity: (presentation * (1 - 0.6 * dragFade)).clamp(
            0.0,
            1.0,
          ),
          pageProgresses: {
            for (final MapEntry(key: page, value: motion)
                in _pageMotions.entries)
              page: motion.value,
          },
        );
        final content = widget.contentBuilder(context, visualState);
        return widget.builder(context, visualState, content);
      },
    );
  }
}

class _TrayVisualState {
  const _TrayVisualState({
    required this.geometry,
    required this.surfaceOffset,
    required this.backdropOpacity,
    required this.pageProgresses,
  });

  /// Resting bounds and corners of the surface.
  final TrayGeometry geometry;

  /// Per-frame translation applied on top of [geometry].
  final Offset surfaceOffset;

  final double backdropOpacity;
  final Map<TrayPage<dynamic>, double> pageProgresses;
}
