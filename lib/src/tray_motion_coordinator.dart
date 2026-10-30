part of 'tray_surface.dart';

class _TrayMotionCoordinator extends StatefulWidget {
  const _TrayMotionCoordinator({
    super.key,
    required this.controller,
    required this.geometry,
    required this.geometryIsMeasured,
    required this.transitionReady,
    required this.pages,
    required this.transition,
    required this.geometryMotion,
    required this.effectsMotion,
    required this.effectsExitMotion,
    required this.routeMotion,
    required this.closeMotion,
    required this.interactiveMotion,
    required this.dragFadeDistance,
    required this.travel,
    required this.viewportHeight,
    required this.keyboardInset,
    required this.closing,
    required this.onTransitionSettled,
    required this.contentBuilder,
    required this.builder,
  });

  final TrayController controller;
  final TrayGeometry geometry;
  final bool geometryIsMeasured;

  /// Whether the transition may start moving. A transition waits until its
  /// incoming page and shared elements are measured.
  final bool transitionReady;
  final List<TrayPage<dynamic>> pages;
  final TrayPageTransition? transition;
  final Motion geometryMotion;
  final Motion effectsMotion;
  final Motion effectsExitMotion;
  final Motion routeMotion;
  final Motion closeMotion;
  final Motion interactiveMotion;

  /// Drag distance over which the backdrop fades out.
  final double dragFadeDistance;

  final TrayTravel travel;

  /// Height of the route viewport the tray is laid out in.
  final double viewportHeight;

  final double keyboardInset;
  final bool closing;
  final ValueChanged<int> onTransitionSettled;
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
  int? _transitionId;
  bool _dismissCompleted = false;

  double _dragOrigin = 0;
  bool _receivedFirstMeasurement = false;
  bool _firstGeometrySnapScheduled = false;
  TrayGeometry? _pendingFirstGeometry;
  // Last geometry the motion was sent to (animated or snapped). Comparing
  // against it stops repeated reports of the same target from restarting the
  // curve, which would otherwise reset its near-flat start on every frame.
  TrayGeometry? _geometryTarget;

  void _animateGeometryTo(TrayGeometry geometry) {
    _geometryTarget = geometry;
    _geometryMotion.motion = widget.geometryMotion;
    _geometryMotion.animateTo(geometry);
  }

  void _snapGeometry(TrayGeometry geometry) {
    _geometryTarget = geometry;
    _geometryMotion.value = geometry;
  }

  void reportMeasuredGeometry(
    TrayGeometry geometry, {
    required bool firstMeasurement,
  }) {
    if (!mounted || widget.closing) return;
    if (firstMeasurement ||
        !_receivedFirstMeasurement ||
        _firstGeometrySnapScheduled) {
      _receivedFirstMeasurement = true;
      _pendingFirstGeometry = geometry;
      if (!_firstGeometrySnapScheduled) {
        _firstGeometrySnapScheduled = true;
        // Content and footer observers can report in either order during this
        // layout. Apply the latest combined geometry after all layout callbacks.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _firstGeometrySnapScheduled = false;
          final pendingGeometry = _pendingFirstGeometry;
          _pendingFirstGeometry = null;
          if (mounted && !widget.closing && pendingGeometry != null) {
            _snapGeometry(pendingGeometry);
          }
        });
      }
      return;
    }
    _receivedFirstMeasurement = true;
    if (geometry != _geometryTarget) {
      _animateGeometryTo(geometry);
    }
  }

  // Rebuilt only when the page motion keys change, in _syncPageMotions, so the
  // AnimatedBuilder keeps one listenable across frames.
  late Listenable _allMotions;

  Listenable _buildAllMotions() => Listenable.merge([
    _geometryMotion,
    _presentationMotion,
    _dragMotion,
    ..._pageMotions.values,
  ]);

  @override
  void initState() {
    super.initState();
    _transitionId = widget.transition?.id;
    _geometryMotion = MotionController<TrayGeometry>(
      motion: widget.geometryMotion,
      vsync: this,
      converter: const TrayGeometryMotionConverter(),
      initialValue: widget.geometry,
    );
    _geometryTarget = widget.geometry;
    _presentationMotion = SingleMotionController(
      motion: widget.routeMotion,
      vsync: this,
      initialValue: 0,
    )..addStatusListener(_handlePresentationStatus);
    _dragMotion = SingleMotionController(
      motion: widget.interactiveMotion,
      vsync: this,
    );
    widget.controller.backGesture.addListener(_handleBackGesture);
    // A transition ends only once the height has settled, so a shared element
    // is never handed over while its destination is still moving.
    _geometryMotion.addStatusListener((_) => _tryCompletePageTransition());
    _syncPageMotions();
    // Start presentation as soon as the coordinator mounts. The surface is
    // still offscreen while its first intrinsic layout is measured.
    if (!widget.closing) {
      _presentationMotion.animateTo(1);
    } else {
      _completeDismissAfterFrame();
    }
  }

  @override
  void didUpdateWidget(covariant _TrayMotionCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final geometryChanged = oldWidget.geometry != widget.geometry;
    final pageSequenceChanged = !_samePageSequence(
      oldWidget.pages,
      widget.pages,
    );
    final transitionChanged = oldWidget.transition?.id != widget.transition?.id;
    final readyChanged = oldWidget.transitionReady != widget.transitionReady;
    final keyboardChanged = oldWidget.keyboardInset != widget.keyboardInset;
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.backGesture.removeListener(_handleBackGesture);
      widget.controller.backGesture.addListener(_handleBackGesture);
    }
    final closingStarted = !oldWidget.closing && widget.closing;
    if (closingStarted) {
      if (_presentationMotion.value <= 0.001) {
        _completeDismissAfterFrame();
      } else {
        _presentationMotion.motion = widget.closeMotion;
        _presentationMotion.animateTo(0);
      }
      return;
    }
    // A close can begin before the first layout measurement arrives. Ignore
    // that late measurement for presentation so it cannot reopen the tray.
    if (widget.closing) {
      return;
    }
    // The keyboard animates on the system side and the tray follows it each
    // frame through viewInsets. Animating the geometry as well would make the
    // tray lag behind the keyboard, so a keyboard-only change snaps.
    final keyboardOnlyChange =
        keyboardChanged && !transitionChanged && !pageSequenceChanged;
    if (geometryChanged &&
        widget.geometry != _geometryTarget &&
        (!pageSequenceChanged || widget.geometryIsMeasured)) {
      if (_receivedFirstMeasurement && !keyboardOnlyChange) {
        _animateGeometryTo(widget.geometry);
      } else {
        _snapGeometry(widget.geometry);
      }
    }
    if (transitionChanged || pageSequenceChanged || readyChanged) {
      _syncPageMotions();
    }
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
    final reachedZero =
        status == AnimationStatus.dismissed &&
        _presentationMotion.value <= 0.001;
    if ((status != AnimationStatus.completed && !reachedZero) || !mounted) {
      return;
    }
    if (widget.closing && _presentationMotion.value <= 0.001) {
      _completeDismissAfterFrame();
      return;
    }
    if (_presentationMotion.value >= 0.999) {
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
    final retainedPages = <TrayPage<dynamic>>{
      ...widget.pages,
      if (widget.transition != null) widget.transition!.outgoing,
    };
    var keysChanged = false;
    for (final page in retainedPages) {
      if (_pageMotions.containsKey(page)) continue;
      keysChanged = true;
      _pageTargets[page] = 0;
      _pageMotions[page] = SingleMotionController(
        motion: widget.effectsMotion,
        vsync: this,
        // The first page is already present when the tray opens. The Expo
        // package only applies this crossfade to subsequent view changes.
        initialValue:
            widget.transition == null &&
                identical(page, widget.controller.currentPage)
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
      _allMotions = _buildAllMotions();
    }
    _transitionId = widget.transition?.id;
    // Waits for the incoming page and its shared elements. didUpdateWidget runs
    // this again once the transition is ready.
    if (widget.transition != null && !widget.transitionReady) {
      return;
    }
    for (final entry in _pageMotions.entries) {
      final target = identical(entry.key, widget.controller.currentPage)
          ? 1.0
          : 0.0;
      if (_pageTargets[entry.key] == target) {
        continue;
      }
      _pageTargets[entry.key] = target;
      if ((entry.value.value - target).abs() < 0.001 &&
          !entry.value.isAnimating) {
        continue;
      }
      final motion = target == 1
          ? widget.effectsMotion
          : widget.effectsExitMotion;
      if (entry.value.motion != motion) {
        entry.value.motion = motion;
      }
      entry.value.animateTo(target);
    }
    _tryCompletePageTransition();
  }

  void _handlePageMotionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _tryCompletePageTransition();
    }
  }

  void _tryCompletePageTransition() {
    final transitionId = _transitionId;
    if (transitionId != null &&
        widget.transitionReady &&
        !_geometryMotion.isAnimating &&
        _pageMotions.values.every((motion) => !motion.isAnimating)) {
      _transitionId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onTransitionSettled(transitionId);
      });
    }
  }

  void beginDrag() {
    _dragOrigin = _dragMotion.value;
    _dragMotion.stop(canceled: true);
  }

  void dragTo(double translationY) {
    _dragMotion.value = (_dragOrigin + translationY)
        .clamp(0.0, double.infinity)
        .toDouble();
  }

  // The back gesture moves the tray with the same drag offset as a handle drag.
  // Commit closes or pops it; cancel springs it back. A commit that closes the
  // tray keeps the offset, so the close animation continues from where the
  // gesture left off.
  void _handleBackGesture() {
    final progress = widget.controller.backGesture.value;
    if (progress != null) {
      _dragMotion.stop(canceled: true);
      _dragMotion.value = progress * _geometryMotion.value.rect.height;
      return;
    }
    if (widget.controller.lifecycle == TrayLifecycle.closing) return;
    _dragMotion.motion = widget.interactiveMotion;
    _dragMotion.animateTo(0);
  }

  // Dismisses when dragged past 110 px, or flung faster than 1000 px/s. These
  // are the Expo Dynamic Tray thresholds.
  static const _dismissDistance = 110.0;
  static const _dismissVelocity = 1000.0;

  bool _shouldDismiss(double velocityY) =>
      _dragMotion.value > _dismissDistance || velocityY > _dismissVelocity;

  void settleDrag(double velocityY) {
    if (_shouldDismiss(velocityY)) {
      widget.controller.dismiss();
      return;
    }
    _dragMotion.motion = widget.interactiveMotion;
    _dragMotion.animateTo(0, withVelocity: velocityY);
  }

  void cancelDrag() {
    _dragMotion.motion = widget.interactiveMotion;
    _dragMotion.animateTo(0);
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _allMotions,
      builder: (context, _) {
        final geometry = _geometryMotion.value;
        final routeProgress = _presentationMotion.value;
        final clampedProgress = routeProgress.clamp(0.0, 1.0).toDouble();
        final travel = switch (widget.travel) {
          FixedTrayTravel(:final distance) => distance,
          // Clears the viewport and no more, so no frame of the spring is
          // spent below the visible area.
          MeasuredTrayTravel(:final hiddenGap) =>
            (widget.viewportHeight +
                    hiddenGap -
                    geometry.rect.top +
                    widget.keyboardInset)
                .clamp(0.0, double.infinity)
                .toDouble(),
        };
        final dragProgress = widget.dragFadeDistance <= 0
            ? 0.0
            : (_dragMotion.value / widget.dragFadeDistance).clamp(0.0, 1.0);
        final keyboardLift = widget.keyboardInset;
        final pageProgresses = <TrayPage<dynamic>, double>{
          for (final entry in _pageMotions.entries)
            entry.key: entry.value.value,
        };
        final visualState = _TrayVisualState(
          geometry: geometry,
          surfaceRect: geometry.rect,
          surfaceOffset: Offset(
            0,
            travel * (1 - clampedProgress) + _dragMotion.value - keyboardLift,
          ),
          surfaceScale: 0.94 + 0.06 * clampedProgress,
          surfaceRadius: geometry.borderRadius,
          backdropOpacity: (clampedProgress * (1 - 0.6 * dragProgress))
              .clamp(0.0, 1.0)
              .toDouble(),
          pageProgresses: pageProgresses,
        );
        // A settled spring can finish without a status change the listener
        // sees, so each build checks whether the transition can end.
        if (widget.transition != null && !_geometryMotion.isAnimating) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _tryCompletePageTransition(),
          );
        }
        final content = widget.contentBuilder(context, visualState);
        return widget.builder(context, visualState, content);
      },
    );
  }
}

class _TrayVisualState {
  const _TrayVisualState({
    required this.geometry,
    required this.surfaceRect,
    required this.surfaceOffset,
    required this.surfaceScale,
    required this.surfaceRadius,
    required this.backdropOpacity,
    required this.pageProgresses,
  });

  final TrayGeometry geometry;

  /// Resting bounds of the surface. Stable while the tray animates.
  final Rect surfaceRect;

  /// Per-frame translation applied on top of [surfaceRect].
  final Offset surfaceOffset;

  final double surfaceScale;
  final BorderRadius surfaceRadius;
  final double backdropOpacity;
  final Map<TrayPage<dynamic>, double> pageProgresses;
}
