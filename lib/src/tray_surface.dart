import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'tray_controller.dart';
import 'tray_geometry.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';
import 'tray_presentation.dart';
import 'tray_restoration.dart';
import 'tray_shared_element.dart';

typedef TraySurfaceBuilder =
    Widget Function(
      BuildContext context,
      BorderRadius borderRadius,
      Widget child,
    );

class TraySurface extends StatefulWidget {
  const TraySurface({
    super.key,
    required this.controller,
    required this.routeAnimation,
    required this.geometryResolver,
    required this.motionTheme,
    required this.onInitialMeasurement,
    this.footer,
    this.surfaceColor,
    this.surfaceBuilder,
    required this.barrierColor,
    required this.barrierDismissible,
    this.restorationId,
  });

  final TrayController controller;
  final Animation<double> routeAnimation;
  final TrayGeometryResolver geometryResolver;
  final TrayMotionTheme motionTheme;
  final VoidCallback onInitialMeasurement;
  final Widget? footer;
  final Color? surfaceColor;
  final TraySurfaceBuilder? surfaceBuilder;
  final Color barrierColor;
  final bool barrierDismissible;
  final String? restorationId;

  @override
  State<TraySurface> createState() => _TraySurfaceState();
}

class _TraySurfaceState extends State<TraySurface>
    with TickerProviderStateMixin, RestorationMixin {
  Size _contentSize = Size.zero;
  double _footerHeight = 0;
  final Map<TrayPage<dynamic>, Size> _contentSizes = {};
  bool _hasInitialMeasurement = false;
  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;
  final GlobalKey _surfaceKey = GlobalKey();
  final TraySharedElementRegistry _sharedElementRegistry =
      TraySharedElementRegistry();
  late final MotionController<Offset> _dragMotion;
  late final TrayRestorableSnapshot _restorableSnapshot =
      TrayRestorableSnapshot(widget.controller.restorationSnapshot);
  bool _applyingRestoration = false;
  bool _restorationRegistered = false;

  @override
  String? get restorationId => widget.restorationId;

  @override
  void initState() {
    super.initState();
    _dragMotion = MotionController<Offset>(
      motion: widget.motionTheme.interactive,
      vsync: this,
      converter: const OffsetMotionConverter(),
      initialValue: Offset.zero,
    );
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
    if (oldWidget.motionTheme.interactive != widget.motionTheme.interactive) {
      _dragMotion.motion = widget.motionTheme.interactive;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _dragMotion.dispose();
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
      if (isCurrentPage || isOutgoingPage) {
        _contentSize = size;
      }
      if (isInitialMeasurement) {
        _hasInitialMeasurement = true;
      }
    });
    if (isInitialMeasurement) {
      widget.onInitialMeasurement();
    }
  }

  void _updateFooterSize(Size size) {
    if (!mounted || _footerHeight == size.height) {
      return;
    }
    setState(() => _footerHeight = size.height);
  }

  void _startDrag(DragStartDetails details) {
    setState(() {
      _isDragging = true;
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_isDragging) {
      return;
    }
    setState(() {
      final nextDy = _dragOffset.dy + (details.primaryDelta ?? 0);
      _dragOffset = Offset(0, nextDy.clamp(0.0, double.infinity));
      _dragMotion.value = _dragOffset;
    });
  }

  void _settleDrag(BuildContext context, [double velocity = 0]) {
    if (!_isDragging) {
      return;
    }

    const dismissOffset = 92.0;
    final shouldDismiss = _dragOffset.dy > dismissOffset || velocity > 840;
    final shouldPop = shouldDismiss && widget.controller.canPop;

    if (shouldPop) {
      // Keep this route/surface alive and reverse its page transition now.
      // Animating the whole fullscreen page offscreen before popping makes
      // the previous page appear to disappear and then reopen as a modal.
      setState(() {
        _isDragging = false;
        _dragOffset = Offset.zero;
      });
      _dragMotion.animateTo(Offset.zero, withVelocity: Offset(0, velocity));
      widget.controller.pop();
      return;
    }

    if (shouldDismiss) {
      // Begin the route reverse immediately so the barrier and surface leave
      // together. Keep the released drag offset as the route animation's
      // starting position instead of running a second, delayed spring.
      setState(() => _isDragging = false);
      widget.controller.dismiss();
      return;
    }

    setState(() {
      _isDragging = false;
      _dragOffset = Offset.zero;
    });
    _dragMotion.animateTo(Offset.zero, withVelocity: Offset(0, velocity));
  }

  bool _handleScrollNotification(
    BuildContext context,
    ScrollNotification notification,
  ) {
    final canDrag =
        widget.controller.canPop ||
        widget.controller.presentation != TrayPresentation.fullscreen;
    if (!canDrag || notification.depth != 0) {
      return false;
    }

    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      if (!_isDragging) {
        _startDrag(DragStartDetails());
      }
      setState(() {
        _dragOffset = Offset(0, _dragOffset.dy - notification.overscroll);
        _dragMotion.value = _dragOffset;
      });
    } else if (notification is ScrollEndNotification && _isDragging) {
      _settleDrag(context);
    }
    return false;
  }

  Widget _buildPageLayer({
    required BuildContext context,
    required Widget page,
    required TrayPage<dynamic> pageEntry,
    required double width,
    required double height,
    required bool measure,
    required bool visible,
    required double opacity,
    required Offset translation,
    required double scale,
    required TrayPageTransition? transition,
  }) {
    Widget child = SizedBox(width: width, child: page);
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
    child = NotificationListener<ScrollNotification>(
      onNotification:
          (notification) => _handleScrollNotification(context, notification),
      child: child,
    );
    child =
        pageEntry.layout == TrayPageLayout.bounded
            ? SizedBox(width: width, height: height, child: child)
            : Align(alignment: Alignment.topCenter, child: child);

    final layer = Offstage(
      offstage: !visible,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: Transform.translate(offset: translation, child: child),
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
    required double pageProgress,
    required double contentOpacity,
    required bool motionIsAnimating,
  }) {
    final outgoingIndex =
        transition == null ? -1 : pages.indexOf(transition.outgoing);
    final outgoingWidget =
        transition == null || outgoingIndex >= 0
            ? null
            : KeyedSubtree(
              key: ObjectKey(transition.outgoing),
              child: transition.outgoing.builder(context),
            );

    List<Widget> buildLayers(double progress) {
      final layers = <Widget>[];
      final isPush = transition?.isPush ?? true;
      final incomingProgress = isPush ? progress : 1 - progress;
      final outgoingProgress = isPush ? 1 - progress : progress;
      for (var index = 0; index < pageWidgets.length; index++) {
        final isCurrent = index == currentIndex;
        final isOutgoing = index == outgoingIndex;
        final isVisible = isCurrent || isOutgoing;
        final opacity =
            transition == null
                ? (isCurrent ? contentOpacity : 0.0)
                : isCurrent
                ? incomingProgress * contentOpacity
                : isOutgoing
                ? outgoingProgress * contentOpacity
                : 0.0;
        final translation = Offset.zero;
        final scale =
            transition == null
                ? 1.0
                : 0.96 +
                    0.04 * (isCurrent ? incomingProgress : outgoingProgress);

        layers.add(
          _buildPageLayer(
            context: context,
            page: pageWidgets[index],
            pageEntry: pages[index],
            width: rect.width,
            height: rect.height,
            measure: isCurrent && !motionIsAnimating,
            visible: isVisible,
            opacity: opacity,
            translation: translation,
            scale: scale,
            transition: transition,
          ),
        );
      }

      if (outgoingWidget != null) {
        layers.add(
          _buildPageLayer(
            context: context,
            page: outgoingWidget,
            pageEntry: transition!.outgoing,
            width: rect.width,
            height: rect.height,
            measure: false,
            visible: true,
            opacity: outgoingProgress * contentOpacity,
            translation: Offset.zero,
            scale: 0.96 + 0.04 * outgoingProgress,
            transition: transition,
          ),
        );
      }
      return layers;
    }

    return Stack(
      fit: StackFit.expand,
      children: buildLayers(pageProgress.clamp(0.0, 1.0).toDouble()),
    );
  }

  void _handleBarrierTap() {
    if (!widget.barrierDismissible) {
      return;
    }
    if (widget.controller.canPop) {
      widget.controller.pop();
    } else {
      widget.controller.dismiss();
    }
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
            final layoutContext = TrayLayoutContext(
              size: constraints.biggest,
              padding: mediaQuery.padding,
              viewInsets: mediaQuery.viewInsets,
            );
            final currentPage = widget.controller.pages.last;
            final footer =
                currentPage.hideFooter
                    ? null
                    : currentPage.footer ?? widget.footer;
            final footerHeight = footer == null ? 0.0 : _footerHeight;
            final bottomInset =
                mediaQuery.viewInsets.bottom > 0
                    ? mediaQuery.viewInsets.bottom
                    : mediaQuery.padding.bottom;
            var boundedFallbackHeight =
                (layoutContext.size.height -
                        mediaQuery.padding.top -
                        bottomInset)
                    .clamp(0.0, layoutContext.size.height)
                    .toDouble() *
                0.72;
            final resolver = widget.geometryResolver;
            if (resolver is DefaultTrayGeometryResolver) {
              boundedFallbackHeight =
                  (layoutContext.size.height -
                          mediaQuery.padding.top -
                          bottomInset)
                      .clamp(0.0, layoutContext.size.height)
                      .toDouble() *
                  resolver.expandedFraction;
            }
            final measuredContentSize =
                currentPage.layout == TrayPageLayout.bounded
                    ? Size(
                      _contentSizes[currentPage]?.width ?? _contentSize.width,
                      boundedFallbackHeight,
                    )
                    : _contentSizes[currentPage] ?? _contentSize;
            final contentSize = Size(
              measuredContentSize.width,
              measuredContentSize.height + footerHeight,
            );
            final geometry = widget.geometryResolver.resolve(
              layoutContext,
              widget.controller.presentation,
              contentSize,
            );
            final pages = widget.controller.pages;
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
                final transition = widget.controller.transition;
                return Stack(
                  key: _surfaceKey,
                  fit: StackFit.expand,
                  children: [
                    _TrayVisualMotionBuilder(
                      geometry: geometry,
                      transition: transition,
                      geometryMotion: widget.motionTheme.geometry,
                      effectsMotion: widget.motionTheme.effects,
                      presentation: widget.controller.presentation,
                      routeAnimation: widget.routeAnimation,
                      dragMotion: _dragMotion,
                      viewportSize: layoutContext.size,
                      geometryResolver: widget.geometryResolver,
                      active:
                          widget.controller.lifecycle != TrayLifecycle.opening,
                      onTransitionSettled:
                          widget.controller.completePageTransition,
                      contentBuilder: (
                        context,
                        visualState,
                        motionIsAnimating,
                      ) {
                        final rect = visualState.geometry.rect;
                        return Positioned.fill(
                          bottom: footer == null ? 0 : footerHeight,
                          child: _buildContent(
                            context: context,
                            rect: Rect.fromLTWH(
                              0,
                              0,
                              rect.width,
                              (rect.height - footerHeight)
                                  .clamp(0.0, rect.height)
                                  .toDouble(),
                            ),
                            pages: pages,
                            pageWidgets: pageWidgets,
                            currentIndex: pageWidgets.length - 1,
                            transition: transition,
                            pageProgress: visualState.pageProgress,
                            contentOpacity: visualState.contentOpacity,
                            motionIsAnimating: motionIsAnimating,
                          ),
                        );
                      },
                      builder: (
                        context,
                        visualState,
                        motionIsAnimating,
                        content,
                      ) {
                        final surfaceRadius = visualState.surfaceRadius;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: Opacity(
                                opacity: visualState.backdropOpacity,
                                child:
                                    widget.barrierDismissible
                                        ? Semantics(
                                          label: 'Dismiss',
                                          button: true,
                                          onTap: _handleBarrierTap,
                                          child: ExcludeSemantics(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: _handleBarrierTap,
                                              child: ColoredBox(
                                                color: widget.barrierColor,
                                              ),
                                            ),
                                          ),
                                        )
                                        : IgnorePointer(
                                          child: ColoredBox(
                                            color: widget.barrierColor,
                                          ),
                                        ),
                              ),
                            ),
                            Positioned.fromRect(
                              rect: visualState.surfaceRect,
                              child: Transform.scale(
                                scale: visualState.surfaceScale,
                                child: Transform.translate(
                                  offset: visualState.dragOffset,
                                  child: Builder(
                                    builder: (context) {
                                      final rect = visualState.geometry.rect;
                                      final canDrag =
                                          widget.controller.canPop ||
                                          widget.controller.presentation !=
                                              TrayPresentation.fullscreen;
                                      final surface = DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: widget.surfaceColor,
                                          borderRadius: surfaceRadius,
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x26000000),
                                              blurRadius: 24,
                                              offset: Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: surfaceRadius,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              content,
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                child: TraySizeObserver(
                                                  enabled: footer != null,
                                                  onSizeChanged:
                                                      _updateFooterSize,
                                                  child: SizedBox(
                                                    width: rect.width,
                                                    child:
                                                        footer ??
                                                        const SizedBox.shrink(),
                                                  ),
                                                ),
                                              ),
                                              if (canDrag)
                                                Positioned(
                                                  top: 0,
                                                  left: (rect.width - 64) / 2,
                                                  width: 64,
                                                  height: 32,
                                                  child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onVerticalDragStart:
                                                        _startDrag,
                                                    onVerticalDragUpdate:
                                                        _updateDrag,
                                                    onVerticalDragEnd:
                                                        (
                                                          details,
                                                        ) => _settleDrag(
                                                          context,
                                                          details.primaryVelocity ??
                                                              0,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onVerticalDragStart:
                                            canDrag ? _startDrag : null,
                                        onVerticalDragUpdate:
                                            canDrag ? _updateDrag : null,
                                        onVerticalDragEnd:
                                            canDrag
                                                ? (details) => _settleDrag(
                                                  context,
                                                  details.primaryVelocity ?? 0,
                                                )
                                                : null,
                                        child:
                                            widget.surfaceBuilder?.call(
                                              context,
                                              surfaceRadius,
                                              surface,
                                            ) ??
                                            surface,
                                      );
                                    },
                                  ),
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

class _TrayVisualMotionBuilder extends StatefulWidget {
  const _TrayVisualMotionBuilder({
    required this.geometry,
    required this.transition,
    required this.geometryMotion,
    required this.effectsMotion,
    required this.presentation,
    required this.routeAnimation,
    required this.dragMotion,
    required this.viewportSize,
    required this.geometryResolver,
    required this.active,
    required this.onTransitionSettled,
    required this.contentBuilder,
    required this.builder,
  });

  final TrayGeometry geometry;
  final TrayPageTransition? transition;
  final Motion geometryMotion;
  final Motion effectsMotion;
  final TrayPresentation presentation;
  final Animation<double> routeAnimation;
  final MotionController<Offset> dragMotion;
  final Size viewportSize;
  final TrayGeometryResolver geometryResolver;
  final bool active;
  final ValueChanged<int> onTransitionSettled;
  final Widget Function(BuildContext, _TrayVisualState, bool) contentBuilder;
  final Widget Function(BuildContext, _TrayVisualFrame, bool, Widget) builder;

  @override
  State<_TrayVisualMotionBuilder> createState() =>
      _TrayVisualMotionBuilderState();
}

class _TrayVisualMotionBuilderState extends State<_TrayVisualMotionBuilder>
    with TickerProviderStateMixin {
  late final MotionController<_TrayVisualState> _motion;
  int? _transitionId;
  final _TrayVisualStateConverter _converter =
      const _TrayVisualStateConverter();

  _TrayVisualState _targetFor(_TrayVisualMotionBuilder widget) {
    return _TrayVisualState(
      geometry: widget.geometry,
      pageProgress:
          widget.transition == null || widget.transition!.isPush ? 1 : 0,
      contentOpacity: 1,
      backdropFactor:
          widget.presentation == TrayPresentation.fullscreen ? 0 : 1,
    );
  }

  List<Motion> _motions() => [
    for (var i = 0; i < 12; i++) widget.geometryMotion,
    widget.effectsMotion,
    widget.effectsMotion,
    widget.geometryMotion,
  ];

  @override
  void initState() {
    super.initState();
    _transitionId = widget.transition?.id;
    _motion = MotionController<_TrayVisualState>.motionPerDimension(
      motionPerDimension: _motions(),
      vsync: this,
      converter: _converter,
      initialValue: _targetFor(widget),
    )..addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(covariant _TrayVisualMotionBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _motion.motionPerDimension = _motions();

    final target = _targetFor(widget);
    final geometryChanged = oldWidget.geometry != widget.geometry;
    final backdropChanged = oldWidget.presentation != widget.presentation;
    final transitionChanged = oldWidget.transition?.id != widget.transition?.id;
    _transitionId = widget.transition?.id;

    if (!widget.active) {
      _motion.value = target;
      return;
    }
    if (widget.transition == null &&
        transitionChanged &&
        !geometryChanged &&
        !backdropChanged) {
      _motion.value = target;
      return;
    }
    if (!geometryChanged && !transitionChanged && !backdropChanged) {
      return;
    }

    final current = _motion.value;
    final currentVelocity = _motion.velocity;
    final start = current.copyWith(
      pageProgress:
          transitionChanged && widget.transition != null
              ? (widget.transition!.isPush ? 0 : 1)
              : widget.transition == null
              ? target.pageProgress
              : current.pageProgress,
      contentOpacity: geometryChanged ? 0.88 : current.contentOpacity,
    );
    final velocity = currentVelocity.copyWith(
      pageProgress:
          transitionChanged || widget.transition == null
              ? 0
              : currentVelocity.pageProgress,
      contentOpacity: geometryChanged ? 0 : currentVelocity.contentOpacity,
    );
    _motion.animateTo(target, from: start, withVelocity: velocity);
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) {
      return;
    }
    final transitionId = _transitionId;
    if (transitionId != null) {
      widget.onTransitionSettled(transitionId);
    }
  }

  BorderRadius _surfaceRadius(TrayGeometry geometry) {
    final resolver = widget.geometryResolver;
    if (resolver is! DefaultTrayGeometryResolver ||
        resolver.horizontalMargin <= 0) {
      return geometry.borderRadius;
    }
    final inset = (widget.viewportSize.width - geometry.rect.width) / 2;
    final fraction = (inset / resolver.horizontalMargin).clamp(0.0, 1.0);
    final radius =
        resolver.fullscreenRadius +
        (resolver.contentRadius - resolver.fullscreenRadius) * fraction;
    return BorderRadius.circular(radius);
  }

  @override
  void dispose() {
    _motion
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _motion,
        widget.routeAnimation,
        widget.dragMotion,
      ]),
      child: ListenableBuilder(
        listenable: _motion,
        builder:
            (context, _) => widget.contentBuilder(
              context,
              _motion.value,
              _motion.isAnimating,
            ),
      ),
      builder: (context, child) {
        final visual = _motion.value;
        final routeProgress =
            widget.routeAnimation.value.clamp(0.0, 1.0).toDouble();
        final travel =
            widget.viewportSize.height > 1000
                ? widget.viewportSize.height
                : 1000.0;
        final dragOffset = widget.dragMotion.value;
        final projectedRect = visual.geometry.rect.shift(
          Offset(0, travel * (1 - routeProgress)),
        );
        final frame = _TrayVisualFrame(
          geometry: visual.geometry,
          pageProgress: visual.pageProgress,
          contentOpacity: visual.contentOpacity,
          routeProgress: routeProgress,
          dragOffset: dragOffset,
          surfaceRect: projectedRect,
          surfaceScale: 0.94 + 0.06 * routeProgress,
          surfaceRadius: _surfaceRadius(visual.geometry),
          backdropOpacity:
              (routeProgress *
                      visual.backdropFactor.clamp(0.0, 1.0) *
                      (1 -
                          (dragOffset.dy / widget.viewportSize.height).clamp(
                            0.0,
                            1.0,
                          )))
                  .clamp(0.0, 1.0)
                  .toDouble(),
        );
        return widget.builder(context, frame, _motion.isAnimating, child!);
      },
    );
  }
}

class _TrayVisualFrame {
  const _TrayVisualFrame({
    required this.geometry,
    required this.pageProgress,
    required this.contentOpacity,
    required this.routeProgress,
    required this.dragOffset,
    required this.surfaceRect,
    required this.surfaceScale,
    required this.surfaceRadius,
    required this.backdropOpacity,
  });

  final TrayGeometry geometry;
  final double pageProgress;
  final double contentOpacity;
  final double routeProgress;
  final Offset dragOffset;
  final Rect surfaceRect;
  final double surfaceScale;
  final BorderRadius surfaceRadius;
  final double backdropOpacity;
}

class _TrayVisualState {
  const _TrayVisualState({
    required this.geometry,
    required this.pageProgress,
    required this.contentOpacity,
    required this.backdropFactor,
  });

  final TrayGeometry geometry;
  final double pageProgress;
  final double contentOpacity;
  final double backdropFactor;

  _TrayVisualState copyWith({double? pageProgress, double? contentOpacity}) {
    return _TrayVisualState(
      geometry: geometry,
      pageProgress: pageProgress ?? this.pageProgress,
      contentOpacity: contentOpacity ?? this.contentOpacity,
      backdropFactor: backdropFactor,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _TrayVisualState &&
      geometry == other.geometry &&
      pageProgress == other.pageProgress &&
      contentOpacity == other.contentOpacity &&
      backdropFactor == other.backdropFactor;

  @override
  int get hashCode =>
      Object.hash(geometry, pageProgress, contentOpacity, backdropFactor);
}

class _TrayVisualStateConverter extends MotionConverter<_TrayVisualState> {
  const _TrayVisualStateConverter();

  static const _geometryConverter = TrayGeometryMotionConverter();

  @override
  List<double> normalize(_TrayVisualState value) => [
    ..._geometryConverter.normalize(value.geometry),
    value.pageProgress,
    value.contentOpacity,
    value.backdropFactor,
  ];

  @override
  _TrayVisualState denormalize(List<double> values) => _TrayVisualState(
    geometry: _geometryConverter.denormalize(values),
    pageProgress: values[12],
    contentOpacity: values[13],
    backdropFactor: values[14],
  );
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
