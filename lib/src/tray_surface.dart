import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'tray_controller.dart';
import 'tray_geometry.dart';
import 'tray_handle.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';
import 'tray_restoration.dart';
import 'tray_shared_element.dart';

class TraySurface extends StatefulWidget {
  const TraySurface({
    super.key,
    required this.controller,
    required this.geometryResolver,
    required this.motionTheme,
    this.footer,
    this.footerBuilder,
    this.surfaceColor,
    required this.barrierColor,
    required this.barrierDismissible,
    this.restorationId,
  });

  final TrayController controller;
  final TrayGeometryResolver geometryResolver;
  final TrayMotionTheme motionTheme;
  final Widget? footer;
  final WidgetBuilder? footerBuilder;
  final Color? surfaceColor;
  final Color barrierColor;
  final bool barrierDismissible;
  final String? restorationId;

  @override
  State<TraySurface> createState() => _TraySurfaceState();
}

class _TraySurfaceState extends State<TraySurface> with RestorationMixin {
  Size _contentSize = Size.zero;
  final Map<TrayPage<dynamic>, Size> _contentSizes = {};
  bool _hasInitialMeasurement = false;
  bool _isDragging = false;
  double _dragTranslation = 0;
  final GlobalKey _surfaceKey = GlobalKey();
  final TraySharedElementRegistry _sharedElementRegistry =
      TraySharedElementRegistry();
  final GlobalKey<_TrayMotionCoordinatorState> _visualMotionKey =
      GlobalKey<_TrayMotionCoordinatorState>();
  late final TrayRestorableSnapshot _restorableSnapshot =
      TrayRestorableSnapshot(widget.controller.restorationSnapshot);
  bool _applyingRestoration = false;
  bool _restorationRegistered = false;

  @override
  String? get restorationId => widget.restorationId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_restorableSnapshot, 'page-stack');
    _restorationRegistered = true;
    if (_restorableSnapshot.value.isEmpty || !widget.controller.isRestorable) {
      return;
    }
    _applyingRestoration = true;
    try {
      widget.controller.restoreFromSnapshot(
        _restorableSnapshot.value,
        notify: false,
      );
    } finally {
      _applyingRestoration = false;
    }
  }

  void _handleControllerChanged() {
    if (_restorationRegistered && !_applyingRestoration) {
      _restorableSnapshot.value = widget.controller.restorationSnapshot;
    }
    final retainedPages = widget.controller.pages.toSet();
    final transition = widget.controller.transition;
    if (transition != null) {
      retainedPages.add(transition.outgoing);
    }
    _contentSizes.removeWhere((page, _) => !retainedPages.contains(page));
  }

  @override
  void didUpdateWidget(covariant TraySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _sharedElementRegistry.dispose();
    super.dispose();
  }

  Rect? _toLocalRect(RenderBox renderObject) {
    final surface = _surfaceKey.currentContext?.findRenderObject();
    if (surface is! RenderBox || !surface.hasSize || !renderObject.attached) {
      return null;
    }
    final topLeft = surface.globalToLocal(
      renderObject.localToGlobal(Offset.zero),
    );
    final bottomRight = surface.globalToLocal(
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero)),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _updateContentSize(TrayPage<dynamic> page, Size size) {
    if (!mounted) {
      return;
    }
    final isCurrentPage = identical(widget.controller.currentPage, page);
    final isOutgoingPage = identical(
      widget.controller.transition?.outgoing,
      page,
    );
    if (!isCurrentPage && !isOutgoingPage) {
      return;
    }
    final isInitialMeasurement = isCurrentPage && !_hasInitialMeasurement;
    final updatesFallbackSize =
        (isCurrentPage || isOutgoingPage) && _contentSize != size;
    final previousSize = _contentSizes[page];
    if (previousSize == size && !isInitialMeasurement && !updatesFallbackSize) {
      return;
    }
    setState(() {
      _contentSizes[page] = size;
      if (isCurrentPage) {
        _contentSize = size;
      }
      if (isInitialMeasurement) {
        _hasInitialMeasurement = true;
      }
    });
  }

  void _startDrag(DragStartDetails details) {
    _dragTranslation = 0;
    _visualMotionKey.currentState?.beginDrag();
    setState(() {
      _isDragging = true;
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_isDragging) {
      return;
    }
    _dragTranslation += details.primaryDelta ?? 0;
    _visualMotionKey.currentState?.dragTo(_dragTranslation);
  }

  void _cancelDrag() {
    if (!_isDragging) {
      return;
    }
    setState(() => _isDragging = false);
    _visualMotionKey.currentState?.cancelDrag();
  }

  void _settleDrag([double velocity = 0]) {
    if (!_isDragging) {
      return;
    }

    setState(() => _isDragging = false);
    _visualMotionKey.currentState?.settleDrag(velocity);
  }

  Widget _buildPageLayer({
    required BuildContext context,
    required Widget page,
    required TrayPage<dynamic> pageEntry,
    required double width,
    required double height,
    required bool measure,
    required bool visible,
    required bool interactive,
    required double opacity,
    required Offset translation,
    required double scale,
    required TrayPageTransition? transition,
  }) {
    Widget child = SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: page,
      ),
    );
    child = TraySharedElementScope(
      registry: _sharedElementRegistry,
      page: pageEntry,
      transition: transition,
      toLocalRect: _toLocalRect,
      child: child,
    );
    child = TraySizeObserver(
      enabled: measure,
      onSizeChanged: (size) => _updateContentSize(pageEntry, size),
      child: child,
    );
    child =
        pageEntry.layout == TrayPageLayout.bounded
            ? SizedBox(width: width, height: height, child: child)
            : Align(alignment: Alignment.topCenter, child: child);

    final layer = Offstage(
      offstage: !visible,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: Transform.translate(offset: translation, child: child),
          ),
        ),
      ),
    );
    return pageEntry.layout == TrayPageLayout.bounded
        ? Positioned.fill(child: layer)
        : Positioned(left: 0, right: 0, top: 0, child: layer);
  }

  Widget _buildContent({
    required BuildContext context,
    required Rect rect,
    required List<TrayPage<dynamic>> pages,
    required List<Widget> pageWidgets,
    required int currentIndex,
    required TrayPageTransition? transition,
    required Map<TrayPage<dynamic>, double> pageProgresses,
  }) {
    final outgoingIndex =
        transition == null ? -1 : pages.indexOf(transition.outgoing);
    final layers = <Widget>[];
    for (var index = 0; index < pageWidgets.length; index++) {
      final page = pages[index];
      final isCurrent = index == currentIndex;
      final isOutgoing = index == outgoingIndex;
      final progress = (pageProgresses[page] ?? 0).clamp(0.0, 1.0).toDouble();
      layers.add(
        _buildPageLayer(
          context: context,
          page: pageWidgets[index],
          pageEntry: page,
          width: rect.width,
          height: rect.height,
          measure: isCurrent,
          visible: isCurrent || isOutgoing || progress > 0,
          interactive: isCurrent,
          opacity: progress,
          translation: Offset.zero,
          scale: 0.96 + 0.04 * progress,
          transition: transition,
        ),
      );
    }

    return Stack(fit: StackFit.expand, children: layers);
  }

  void _handleBarrierTap() {
    if (!widget.barrierDismissible) {
      return;
    }
    widget.controller.close();
  }

  List<Widget> _buildSharedElementFlights(
    BuildContext context,
    TrayPageTransition? transition,
  ) {
    if (transition == null) {
      return const [];
    }
    return [
      for (final match in _sharedElementRegistry.matches(transition))
        _TraySharedElementFlight(
          key: ValueKey<Object>(
            _TraySharedElementFlightKey(transition.id, match.tag),
          ),
          from: match.outgoingRect,
          to: match.incomingRect,
          motion: widget.motionTheme.effects,
          child: match.flightBuilder?.call(context, match.child) ?? match.child,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final mediaQuery = MediaQuery.of(context);
            final currentPage = widget.controller.currentPage;
            const estimatedFooterHeight = 65.0;
            final footer =
                currentPage.hideFooter
                    ? null
                    : currentPage.footerBuilder?.call(context) ??
                        currentPage.footer ??
                        widget.footerBuilder?.call(context) ??
                        widget.footer;
            final activeFooterHeight =
                footer == null ? 0.0 : estimatedFooterHeight;
            final safeBottom = mediaQuery.padding.bottom;
            final layoutContext = TrayLayoutContext(
              size: constraints.biggest,
              padding: mediaQuery.padding,
              viewInsets: mediaQuery.viewInsets,
            );
            var boundedFallbackHeight =
                (layoutContext.size.height -
                        mediaQuery.padding.top -
                        safeBottom)
                    .clamp(0.0, layoutContext.size.height)
                    .toDouble();
            final measuredContentSize =
                currentPage.layout == TrayPageLayout.bounded
                    ? Size(
                      _contentSizes[currentPage]?.width ?? _contentSize.width,
                      boundedFallbackHeight,
                    )
                    : _contentSizes[currentPage] ?? _contentSize;
            final contentSize = Size(
              measuredContentSize.width,
              measuredContentSize.height + activeFooterHeight + 60,
            );
            final geometry = widget.geometryResolver.resolve(
              layoutContext,
              contentSize,
            );
            final transition = widget.controller.transition;
            final pages = [
              ...widget.controller.pages,
              if (transition != null &&
                  !widget.controller.pages.contains(transition.outgoing))
                transition.outgoing,
            ];
            final pageWidgets = [
              for (final page in pages)
                KeyedSubtree(
                  key: ObjectKey(page),
                  child: page.builder(context),
                ),
            ];

            return ListenableBuilder(
              listenable: _sharedElementRegistry,
              builder: (context, _) {
                return Stack(
                  key: _surfaceKey,
                  fit: StackFit.expand,
                  children: [
                    _TrayMotionCoordinator(
                      key: _visualMotionKey,
                      controller: widget.controller,
                      geometry: geometry,
                      pages: pages,
                      transition: transition,
                      geometryMotion: widget.motionTheme.geometry,
                      effectsMotion: widget.motionTheme.effects,
                      routeMotion: widget.motionTheme.route,
                      closeMotion: widget.motionTheme.close,
                      interactiveMotion: widget.motionTheme.interactive,
                      keyboardInset: mediaQuery.viewInsets.bottom,
                      safeBottomInset: safeBottom,
                      initialMeasurementReady: _hasInitialMeasurement,
                      closing:
                          widget.controller.lifecycle == TrayLifecycle.closing,
                      onTransitionSettled:
                          widget.controller.completePageTransition,
                      contentBuilder: (context, visualState) {
                        final rect = visualState.geometry.rect;
                        return Positioned.fill(
                          top: 36,
                          bottom: footer == null ? 24 : activeFooterHeight + 24,
                          child: _buildContent(
                            context: context,
                            rect: Rect.fromLTWH(
                              0,
                              0,
                              rect.width,
                              (rect.height - activeFooterHeight - 60)
                                  .clamp(0.0, rect.height)
                                  .toDouble(),
                            ),
                            pages: pages,
                            pageWidgets: pageWidgets,
                            currentIndex: pages.indexOf(currentPage),
                            transition: transition,
                            pageProgresses: visualState.pageProgresses,
                          ),
                        );
                      },
                      builder: (context, visualState, content) {
                        final surfaceRadius = visualState.surfaceRadius;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: Opacity(
                                opacity: visualState.backdropOpacity,
                                child: Semantics(
                                  label:
                                      widget.barrierDismissible
                                          ? 'Dismiss'
                                          : 'Modal barrier',
                                  button: widget.barrierDismissible,
                                  onTap:
                                      widget.barrierDismissible
                                          ? _handleBarrierTap
                                          : null,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap:
                                        widget.barrierDismissible
                                            ? _handleBarrierTap
                                            : () {},
                                    child: ColoredBox(
                                      color: widget.barrierColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fromRect(
                              rect: visualState.surfaceRect,
                              child: Transform.scale(
                                scale: visualState.surfaceScale,
                                child: Builder(
                                  builder: (context) {
                                    final surface = DecoratedBox(
                                      decoration: BoxDecoration(
                                        color:
                                            widget.surfaceColor ??
                                            const Color(0xFF141414),
                                        borderRadius: surfaceRadius,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: surfaceRadius,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Positioned.fill(
                                              child: Stack(children: [content]),
                                            ),
                                            if (footer != null)
                                              Positioned(
                                                bottom: 24,
                                                left: 24,
                                                right: 24,
                                                child: footer,
                                              ),
                                            Positioned(
                                              top: 8,
                                              left: 0,
                                              right: 0,
                                              height: 28,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onVerticalDragStart: _startDrag,
                                                onVerticalDragUpdate:
                                                    _updateDrag,
                                                onVerticalDragEnd:
                                                    (details) => _settleDrag(
                                                      details.primaryVelocity ??
                                                          0,
                                                    ),
                                                onVerticalDragCancel:
                                                    _cancelDrag,
                                                child: const Align(
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 8,
                                                    ),
                                                    child: TrayHandle(),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    return surface;
                                  },
                                ),
                              ),
                            ),
                            ..._buildSharedElementFlights(context, transition),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TrayMotionCoordinator extends StatefulWidget {
  const _TrayMotionCoordinator({
    super.key,
    required this.controller,
    required this.geometry,
    required this.pages,
    required this.transition,
    required this.geometryMotion,
    required this.effectsMotion,
    required this.routeMotion,
    required this.closeMotion,
    required this.interactiveMotion,
    required this.keyboardInset,
    required this.safeBottomInset,
    required this.initialMeasurementReady,
    required this.closing,
    required this.onTransitionSettled,
    required this.contentBuilder,
    required this.builder,
  });

  final TrayController controller;
  final TrayGeometry geometry;
  final List<TrayPage<dynamic>> pages;
  final TrayPageTransition? transition;
  final Motion geometryMotion;
  final Motion effectsMotion;
  final Motion routeMotion;
  final Motion closeMotion;
  final Motion interactiveMotion;
  final double keyboardInset;
  final double safeBottomInset;
  final bool initialMeasurementReady;
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
    if (widget.initialMeasurementReady && !widget.closing) {
      _presentationMotion.animateTo(1);
    } else if (widget.closing) {
      _completeDismissAfterFrame();
    }
  }

  @override
  void didUpdateWidget(covariant _TrayMotionCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final geometryChanged = oldWidget.geometry != widget.geometry;
    final transitionChanged = oldWidget.transition?.id != widget.transition?.id;
    final openingStarted =
        !oldWidget.initialMeasurementReady && widget.initialMeasurementReady;
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
    if (!widget.initialMeasurementReady) {
      if (geometryChanged) {
        _geometryMotion.value = widget.geometry;
      }
      if (transitionChanged ||
          !_samePageSequence(oldWidget.pages, widget.pages)) {
        _syncPageMotions();
      }
      return;
    }
    if (openingStarted) {
      _geometryMotion.motion = widget.geometryMotion;
      _geometryMotion.animateTo(widget.geometry);
      if (transitionChanged ||
          !_samePageSequence(oldWidget.pages, widget.pages)) {
        _syncPageMotions();
      }
      _presentationMotion.motion = widget.routeMotion;
      _presentationMotion.animateTo(1);
      return;
    }
    if (geometryChanged) {
      _geometryMotion.motion = widget.geometryMotion;
      _geometryMotion.animateTo(widget.geometry);
    }
    if (transitionChanged ||
        !_samePageSequence(oldWidget.pages, widget.pages)) {
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
          initialValue: 0,
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
      if (entry.value.motion != widget.effectsMotion) {
        entry.value.motion = widget.effectsMotion;
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
        const travel = 1000.0;
        final dragProgress = (_dragMotion.value / travel).clamp(0.0, 1.0);
        final keyboardLift =
            (widget.keyboardInset - widget.safeBottomInset)
                .clamp(0.0, double.infinity)
                .toDouble();
        final projectedRect = geometry.rect.shift(
          Offset(
            0,
            travel * (1 - clampedProgress) + _dragMotion.value - keyboardLift,
          ),
        );
        final pageProgresses = <TrayPage<dynamic>, double>{
          for (final entry in _pageMotions.entries)
            entry.key: entry.value.value,
        };
        final visualState = _TrayVisualState(
          geometry: geometry,
          surfaceRect: projectedRect,
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
    required this.surfaceScale,
    required this.surfaceRadius,
    required this.backdropOpacity,
    required this.pageProgresses,
  });

  final TrayGeometry geometry;
  final Rect surfaceRect;
  final double surfaceScale;
  final BorderRadius surfaceRadius;
  final double backdropOpacity;
  final Map<TrayPage<dynamic>, double> pageProgresses;
}

class TraySizeObserver extends SingleChildRenderObjectWidget {
  const TraySizeObserver({
    super.key,
    required this.enabled,
    required this.onSizeChanged,
    super.child,
  });

  final bool enabled;
  final ValueChanged<Size> onSizeChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTraySizeObserver(enabled, onSizeChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTraySizeObserver renderObject,
  ) {
    final wasEnabled = renderObject.enabled;
    renderObject.enabled = enabled;
    renderObject.onSizeChanged = onSizeChanged;
    if (!wasEnabled && enabled) {
      renderObject.reportSize();
    }
  }
}

class RenderTraySizeObserver extends RenderProxyBox {
  RenderTraySizeObserver(this.enabled, this.onSizeChanged);

  bool enabled;
  ValueChanged<Size> onSizeChanged;
  Size? _lastSize;

  void reportSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && enabled) {
        onSizeChanged(size);
      }
    });
  }

  @override
  void performLayout() {
    super.performLayout();
    if (!enabled || _lastSize == size) {
      return;
    }
    _lastSize = size;
    reportSize();
  }
}

class _TraySharedElementFlight extends StatelessWidget {
  const _TraySharedElementFlight({
    super.key,
    required this.from,
    required this.to,
    required this.motion,
    required this.child,
  });

  final Rect from;
  final Rect to;
  final Motion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MotionBuilder<Rect>(
      value: to,
      from: from,
      converter: const RectMotionConverter(),
      motion: motion,
      child: IgnorePointer(child: child),
      builder: (context, rect, child) {
        return Positioned.fromRect(rect: rect, child: child!);
      },
    );
  }
}

class _TraySharedElementFlightKey {
  const _TraySharedElementFlightKey(this.transitionId, this.tag);

  final int transitionId;
  final Object tag;

  @override
  bool operator ==(Object other) {
    return other is _TraySharedElementFlightKey &&
        other.transitionId == transitionId &&
        other.tag == tag;
  }

  @override
  int get hashCode => Object.hash(transitionId, tag);
}
