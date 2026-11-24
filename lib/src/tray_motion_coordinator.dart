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
    required this.barrierColor,
    required this.barrierBuilder,
    required this.contentBuilder,
    required this.surfaceBuilder,
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
  final Color barrierColor;

  /// Wraps the backdrop, whose color follows the tray's position.
  final Widget Function(BuildContext, Widget backdrop) barrierBuilder;

  /// Builds the content once per coordinator build. Its parts listen to the
  /// motions they use, so a frame of motion does not rebuild it.
  final Widget Function(BuildContext, _TrayMotions) contentBuilder;

  /// Builds the surface around [content]. It runs once per coordinator build;
  /// the coordinator moves it on every frame without rebuilding it.
  final Widget Function(
    BuildContext,
    Animation<TrayGeometry> geometry,
    Widget content,
  )
  surfaceBuilder;

  @override
  State<_TrayMotionCoordinator> createState() => _TrayMotionCoordinatorState();
}

/// The motions page content listens to.
abstract interface class _TrayMotions {
  /// The page's fade progress, from 0 when hidden to 1 when shown.
  Animation<double> progressOf(TrayPage<dynamic> page);

  Animation<TrayGeometry> get geometry;
}

class _TrayMotionCoordinatorState extends State<_TrayMotionCoordinator>
    with TickerProviderStateMixin
    implements _TrayMotions {
  late final MotionController<TrayGeometry> _geometryMotion;
  late final SingleMotionController _presentationMotion;
  late final SingleMotionController _dragMotion;
  final Map<TrayPage<dynamic>, SingleMotionController> _pageMotions = {};
  final Map<TrayPage<dynamic>, double> _pageTargets = {};
  late final Listenable _surfaceMotion;

  // A page change starts once its incoming page is laid out, and settles once
  // the page motions end.
  int? _startedTransitionId;
  int? _settledTransitionId;
  bool _dismissCompleted = false;

  bool _dragging = false;
  // Downward speed of the drag that closed the tray, in pixels per second.
  double _releaseVelocity = 0;
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
    _surfaceMotion = Listenable.merge([
      _geometryMotion,
      _presentationMotion,
      _dragMotion,
    ]);
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
      _dragging = false;
      if (_presentationMotion.value <= 0.001) {
        _completeDismissAfterFrame();
      } else {
        // A fling that closes the tray keeps its speed.
        final travel = _travel;
        _presentationMotion.motion = _motion.close;
        _presentationMotion.animateTo(
          0,
          withVelocity: travel <= 0 ? 0 : -_releaseVelocity / travel,
        );
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
  Animation<double> progressOf(TrayPage<dynamic> page) =>
      _pageMotions[page] ?? kAlwaysDismissedAnimation;

  @override
  Animation<TrayGeometry> get geometry => _geometryMotion;

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
    for (final page in retainedPages) {
      if (_pageMotions.containsKey(page)) continue;
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
        _pageTargets.remove(page);
        _pageMotions.remove(page)?.dispose();
      }
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

  // Bottom sheet rules: a release past half the tray's height, or a downward
  // fling faster than this, closes the tray.
  static const _closeVelocity = 700.0;

  /// Distance from the resting position to just out of view.
  double get _travel => switch (_motion.travel) {
    FixedTrayTravel(:final distance) => distance,
    // Clears the viewport and no more, so no frame of the spring is spent
    // below the visible area.
    MeasuredTrayTravel(:final hiddenGap) => math.max(
      0.0,
      widget.viewportHeight +
          hiddenGap -
          _geometryMotion.value.rect.top +
          widget.keyboardInset,
    ),
  };

  bool get isDragging => _dragging;

  /// How far below its resting position the tray is.
  double get dragOffset => _dragMotion.value;

  /// Moves the tray down by [delta] (up when negative), never above its
  /// resting position, and returns the part of [delta] it used.
  double dragBy(double delta) {
    if (widget.closing) return 0;
    if (!_dragging) {
      _dragging = true;
      _dragMotion.stop(canceled: true);
    }
    final before = _dragMotion.value;
    final after = math.max(0.0, before + delta);
    if (after != before) _dragMotion.value = after;
    return after - before;
  }

  /// Ends a drag released at [velocity] (pixels per second, positive down).
  void endDrag(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final height = _geometryMotion.value.rect.height;
    if (velocity > _closeVelocity || _dragMotion.value > height / 2) {
      // The close keeps the release speed. close returns false while another
      // route covers the tray, and then the tray springs back.
      _releaseVelocity = math.max(0.0, velocity);
      if (widget.controller.close()) return;
      _releaseVelocity = 0;
    }
    _dragMotion.motion = _motion.interactive;
    _dragMotion.animateTo(0, withVelocity: velocity);
  }

  // The back gesture moves the tray with the same offset as a drag. Commit
  // closes or pops it; cancel springs it back. A commit that closes the tray
  // keeps the offset, so the close continues from where the gesture left.
  void _handleBackGesture() {
    final progress = widget.controller.backGesture.value;
    if (progress != null) {
      _dragMotion.stop(canceled: true);
      _dragMotion.value = progress * _geometryMotion.value.rect.height;
      return;
    }
    if (widget.controller.lifecycle == TrayLifecycle.closing) return;
    _dragMotion.motion = _motion.interactive;
    _dragMotion.animateTo(0);
  }

  /// How far the tray is from out of view, from 0 hidden to 1 at rest.
  double get _shownFraction {
    final travel = _travel;
    final hidden = travel * (1 - _presentationMotion.value) + _dragMotion.value;
    return travel <= 0 ? 1 : (1 - hidden / travel).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.surfaceBuilder(
      context,
      _geometryMotion,
      widget.contentBuilder(context, this),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: widget.barrierBuilder(
            context,
            // The position goes into the backdrop alpha. An Opacity here
            // would composite a full-screen layer on every frame.
            AnimatedBuilder(
              animation: _surfaceMotion,
              builder: (context, _) => ColoredBox(
                color: widget.barrierColor.withValues(
                  alpha: widget.barrierColor.a * _shownFraction,
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _surfaceMotion,
          child: surface,
          builder: (context, surface) {
            final presentation = _presentationMotion.value.clamp(0.0, 1.0);
            return Positioned.fromRect(
              rect: _geometryMotion.value.rect,
              // Travel, drag and keyboard offsets go through a transform, so
              // they never relayout the tray.
              child: Transform.translate(
                offset: Offset(
                  0,
                  _travel * (1 - presentation) +
                      _dragMotion.value -
                      widget.keyboardInset,
                ),
                child: surface,
              ),
            );
          },
        ),
      ],
    );
  }
}
