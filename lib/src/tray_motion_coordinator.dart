import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import 'tray_controller.dart';
import 'tray_geometry.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';

class _TrayMotionCoordinator extends StatefulWidget {
  const _TrayMotionCoordinator({
    super.key,
    required this.controller,
    required this.geometry,
    required this.geometryIsMeasured,
    required this.pages,
    required this.transition,
    required this.geometryMotion,
    required this.effectsMotion,
    required this.effectsExitMotion,
    required this.routeMotion,
    required this.closeMotion,
    required this.interactiveMotion,
    required this.hiddenGap,
    required this.dragFadeDistance,
    required this.fixedTravel,
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
  final List<TrayPage<dynamic>> pages;
  final TrayPageTransition? transition;
  final Motion geometryMotion;
  final Motion effectsMotion;
  final Motion effectsExitMotion;
  final Motion routeMotion;
  final Motion closeMotion;
  final Motion interactiveMotion;

  /// Pixels the tray travels past the viewport bottom once hidden.
  final double hiddenGap;

  /// Drag distance over which the backdrop fades out.
  final double dragFadeDistance;

  /// When non-null, replaces the measured travel distance.
  final double? fixedTravel;

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
            _geometryMotion.value = pendingGeometry;
          }
        });
      }
      return;
    }
    _receivedFirstMeasurement = true;
    if (_geometryMotion.value != geometry) {
      _geometryMotion.motion = widget.geometryMotion;
      _geometryMotion.animateTo(geometry);
    }
  }

  Listenable get _allMotions => Listenable.merge([
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
    _presentationMotion = SingleMotionController(
      motion: widget.routeMotion,
      vsync: this,
      initialValue: 0,
    )..addStatusListener(_handlePresentationStatus);
    _dragMotion = SingleMotionController(
      motion: widget.interactiveMotion,
      vsync: this,
    );
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
    final pageSequenceChanged =
        !_samePageSequence(oldWidget.pages, widget.pages);
    final transitionChanged = oldWidget.transition?.id != widget.transition?.id;
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
    if (geometryChanged &&
        _geometryMotion.value != widget.geometry &&
        (!pageSequenceChanged || widget.geometryIsMeasured)) {
      if (_receivedFirstMeasurement) {
        _geometryMotion.motion = widget.geometryMotion;
        _geometryMotion.animateTo(widget.geometry);
      } else {
        _geometryMotion.value = widget.geometry;
      }
    }
    if (transitionChanged || pageSequenceChanged) {
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
    for (final page in retainedPages) {
      _pageMotions.putIfAbsent(page, () {
        _pageTargets[page] = 0;
        return SingleMotionController(
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
      });
    }
    for (final page in _pageMotions.keys.toList()) {
      if (!retainedPages.contains(page)) {
        _pageTargets.remove(page);
        _pageMotions.remove(page)?.dispose();
      }
    }
    _transitionId = widget.transition?.id;
    for (final entry in _pageMotions.entries) {
      final target =
          identical(entry.key, widget.controller.currentPage) ? 1.0 : 0.0;
      if (_pageTargets[entry.key] == target) {
        continue;
      }
      _pageTargets[entry.key] = target;
      if ((entry.value.value - target).abs() < 0.001 &&
          !entry.value.isAnimating) {
        continue;
      }
      final motion =
          target == 1 ? widget.effectsMotion : widget.effectsExitMotion;
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
    _dragMotion.value =
        (_dragOrigin + translationY).clamp(0.0, double.infinity).toDouble();
  }

  void settleDrag(double velocityY) {
    if (_dragMotion.value > 110 || velocityY > 1000) {
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
        // Travel only as far as it takes to clear the viewport, plus a small
        // margin. A fixed long distance keeps the first frames of the spring
        // below the visible area, which reads as dead time before the tray
        // appears, and wastes most of the close on pixels nobody sees.
        final travel =
            widget.fixedTravel ??
            (widget.viewportHeight +
                    widget.hiddenGap -
                    geometry.rect.top +
                    widget.keyboardInset)
                .clamp(0.0, double.infinity)
                .toDouble();
        final dragProgress =
            widget.dragFadeDistance <= 0
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
            travel * (1 - clampedProgress) +
                _dragMotion.value -
                keyboardLift,
          ),
          surfaceScale: 0.94 + 0.06 * clampedProgress,
          surfaceRadius: geometry.borderRadius,
          backdropOpacity:
              (clampedProgress * (1 - 0.6 * dragProgress))
                  .clamp(0.0, 1.0)
                  .toDouble(),
          pageProgresses: pageProgresses,
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
