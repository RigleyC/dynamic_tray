import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderProxyBox;
import 'package:motor/motor.dart';

import 'tray_controller.dart';
import 'tray_corner_radii.dart';
import 'tray_geometry.dart';
import 'tray_handle.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';
import 'tray_restoration.dart';
import 'tray_shared_element.dart';
import 'tray_theme.dart';

part 'tray_motion_coordinator.dart';

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
  // Built once per page and reused on every rebuild. Rebuilds happen on each
  // controller notify and on each MediaQuery change, such as the keyboard, and
  // the builders must not run again for those.
  final Map<TrayPage<dynamic>, Widget> _pageWidgets = {};
  final Map<TrayPage<dynamic>, Widget?> _footers = {};
  bool _hasInitialMeasurement = false;

  /// Fixed space reserved for the footer, independent of its real height.
  static const double _footerReserve = 65;
  bool _isDragging = false;
  double _dragTranslation = 0;
  bool _contentDragActive = false;
  double _contentDragTranslation = 0;
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
    // Safety net for apps that did not call warmUpTrayDeviceCorners during
    // startup. Deliberately not awaited and never followed by a setState: the
    // value is read synchronously on each build, so a tray opened before it
    // resolves keeps the MediaQuery corners instead of rebuilding mid-flight.
    unawaited(warmUpTrayDeviceCorners());
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
    _pageWidgets.removeWhere((page, _) => !retainedPages.contains(page));
    _footers.removeWhere((page, _) => !retainedPages.contains(page));
  }

  @override
  void didUpdateWidget(covariant TraySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      _pageWidgets.clear();
      _footers.clear();
    }
    if (oldWidget.footer != widget.footer ||
        oldWidget.footerBuilder != widget.footerBuilder) {
      _footers.clear();
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

  TrayGeometry _geometryForContentSize(
    TrayPage<dynamic> page,
    Size size,
    TrayLayoutContext layoutContext,
    double activeFooterHeight,
  ) {
    const innerBottomPadding = 24.0;
    final viewportBottomGap = layoutContext.viewInsets.bottom + 8.0;
    final boundedFallbackHeight =
        (layoutContext.size.height -
                layoutContext.padding.top -
                viewportBottomGap -
                activeFooterHeight -
                36 -
                innerBottomPadding)
            .clamp(0.0, layoutContext.size.height)
            .toDouble();
    final measuredContentSize = page.layout == TrayPageLayout.bounded
        ? Size(size.width, boundedFallbackHeight)
        : size;
    return widget.geometryResolver.resolve(
      layoutContext,
      Size(
        measuredContentSize.width,
        measuredContentSize.height +
            activeFooterHeight +
            36 +
            innerBottomPadding,
      ),
    );
  }

  void _updateContentSize(
    TrayPage<dynamic> page,
    Size size,
    TrayGeometry geometry,
  ) {
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
    // A bounded page's height comes from the viewport, not from its content,
    // and build already derives that same height for the geometry. Reporting
    // a height-only change would only repeat the geometry build computed (and
    // would run during layout on every keyboard frame), so only the initial
    // measurement or a width change (rotation, split view) is reported.
    final isBoundedHeightOnlyChange =
        page.layout == TrayPageLayout.bounded &&
        !isInitialMeasurement &&
        previousSize?.width == size.width;
    _contentSizes[page] = size;
    if (isCurrentPage) {
      _contentSize = size;
    }
    if (isBoundedHeightOnlyChange) {
      return;
    }
    if (isInitialMeasurement) _hasInitialMeasurement = true;
    _visualMotionKey.currentState?.reportMeasuredGeometry(
      geometry,
      firstMeasurement: isInitialMeasurement,
    );
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

  // A list at its top keeps the extra pull as overscroll. That pull drags the
  // tray, like the handle does, so the content and the tray hand off without a
  // gap. Pulls that the list scrolls itself are left alone.
  bool _handleContentScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical ||
        metrics.axisDirection != AxisDirection.down) {
      return false;
    }
    final coordinator = _visualMotionKey.currentState;
    if (notification is OverscrollNotification) {
      if (metrics.extentBefore > 0 || notification.overscroll >= 0) {
        return false;
      }
      if (!_contentDragActive) {
        _contentDragActive = true;
        _contentDragTranslation = 0;
        coordinator?.beginDrag();
      }
      _contentDragTranslation -= notification.overscroll;
      coordinator?.dragTo(_contentDragTranslation);
    } else if (notification is ScrollEndNotification && _contentDragActive) {
      _contentDragActive = false;
      coordinator?.settleDrag(notification.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  Widget _buildPageLayer({
    required BuildContext context,
    required Widget page,
    required TrayPage<dynamic> pageEntry,
    required double width,
    required double height,
    required double boundedHeight,
    required bool measure,
    required TrayGeometry Function(Size) geometryForSize,
    required bool visible,
    required bool interactive,
    required double opacity,
    required double pageScale,
    required bool inFront,
    required TrayPageTransition? transition,
  }) {
    // An auto page is capped at the available height. Content that fits keeps
    // its height, and a scroll view fills the cap, so the tray sizes to it.
    final isAuto = pageEntry.layout == TrayPageLayout.auto;
    Widget child = SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: isAuto
            ? ConstrainedBox(
                constraints: BoxConstraints(maxHeight: boundedHeight),
                child: page,
              )
            : page,
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
      deferCallback: false,
      onSizeChanged: (size) =>
          _updateContentSize(pageEntry, size, geometryForSize(size)),
      child: child,
    );
    final isBounded = pageEntry.layout == TrayPageLayout.bounded;
    if (!isBounded) {
      child = Align(alignment: Alignment.topCenter, child: child);
    }

    final progress = opacity.clamp(0.0, 1.0).toDouble();
    // A hidden page sits behind the current one (smaller) or in front of it
    // (larger), and reaches 1 as it becomes visible, on the crossfade's curve.
    final depth = (1 - pageScale) * (1 - progress);
    final scale = inFront ? 1 + depth : 1 - depth;
    final layer = Offstage(
      offstage: !visible,
      child: IgnorePointer(
        ignoring: !interactive,
        child: Opacity(
          opacity: progress,
          child: Transform.scale(scale: scale, child: child),
        ),
      ),
    );
    // Hidden pages stop their tickers. Bounded and hidden pages also take a
    // fixed size, so the animating surface height does not relayout them on
    // every frame. The surface clips the layer while it animates.
    final gatedLayer = TickerMode(enabled: visible, child: layer);
    if (isBounded || !visible) {
      return Positioned(
        left: 0,
        top: 0,
        width: width,
        height: height,
        child: gatedLayer,
      );
    }
    return Positioned(left: 0, right: 0, top: 0, child: gatedLayer);
  }

  Widget _buildContent({
    required BuildContext context,
    required double width,
    required List<TrayPage<dynamic>> pages,
    required List<Widget> pageWidgets,
    required int currentIndex,
    required TrayPageTransition? transition,
    required Map<TrayPage<dynamic>, double> pageProgresses,
    required double restingHeight,
    required double boundedHeight,
    required double pageScale,
    required TrayGeometry Function(TrayPage<dynamic>, Size) geometryForSize,
  }) {
    final outgoingIndex = transition == null
        ? -1
        : pages.indexOf(transition.outgoing);
    final layers = <Widget>[];
    for (var index = 0; index < pageWidgets.length; index++) {
      final page = pages[index];
      final isCurrent = index == currentIndex;
      final isOutgoing = index == outgoingIndex;
      final progress = (pageProgresses[page] ?? 0).clamp(0.0, 1.0).toDouble();
      final visible = isCurrent || isOutgoing || progress > 0;
      layers.add(
        _buildPageLayer(
          context: context,
          page: pageWidgets[index],
          pageEntry: page,
          width: width,
          height: page.layout == TrayPageLayout.bounded
              ? boundedHeight
              : restingHeight,
          measure: isCurrent,
          boundedHeight: boundedHeight,
          geometryForSize: (size) => geometryForSize(page, size),
          visible: visible,
          interactive: isCurrent,
          opacity: progress,
          pageScale: pageScale,
          // Forward, the outgoing page leaves toward the viewer. Back, the
          // incoming page arrives from there.
          inFront:
              transition != null &&
              (transition.isPush ? isOutgoing : isCurrent),
          transition: transition,
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleContentScroll,
      child: Stack(fit: StackFit.expand, children: layers),
    );
  }

  Widget _pageWidgetFor(BuildContext context, TrayPage<dynamic> page) {
    return _pageWidgets.putIfAbsent(
      page,
      () => KeyedSubtree(key: ObjectKey(page), child: page.builder(context)),
    );
  }

  Widget? _footerFor(BuildContext context, TrayPage<dynamic> page) {
    if (_footers.containsKey(page)) {
      return _footers[page];
    }
    final footer = page.hideFooter
        ? null
        : page.footerBuilder?.call(context) ??
              page.footer ??
              widget.footerBuilder?.call(context) ??
              widget.footer;
    _footers[page] = footer;
    return footer;
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
            // Read only the aspects the tray depends on. MediaQuery.of listens
            // to every aspect, so a text scale or accessibility change would
            // rebuild the tray and every page builder it holds.
            final mediaQueryPadding = MediaQuery.paddingOf(context);
            final viewInsets = MediaQuery.viewInsetsOf(context);
            final currentPage = widget.controller.currentPage;
            final footer = _footerFor(context, currentPage);
            final activeFooterHeight = footer == null ? 0.0 : _footerReserve;
            // Theme lookups run once per surface build. The motion coordinator
            // calls the builder on every frame, so per-frame lookups would
            // repeat the same work.
            final surfaceColor =
                widget.surfaceColor ?? traySurfaceColorOf(context);
            final textStyle = trayTextStyleOf(context);
            const innerBottomPadding = 24.0;
            final viewportBottomGap = viewInsets.bottom + 8.0;
            final layoutContext = TrayLayoutContext(
              size: constraints.biggest,
              padding: mediaQueryPadding,
              viewInsets: viewInsets,
              displayCornerRadii:
                  trayDeviceCornerRadii ??
                  MediaQuery.displayCornerRadiiOf(context),
            );
            final boundedFallbackHeight =
                (layoutContext.size.height -
                        mediaQueryPadding.top -
                        viewportBottomGap -
                        activeFooterHeight -
                        36 -
                        innerBottomPadding)
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
              measuredContentSize.height +
                  activeFooterHeight +
                  36 +
                  innerBottomPadding,
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
              for (final page in pages) _pageWidgetFor(context, page),
            ];
            // The tray's resting content height for the active page. Hidden
            // intrinsic pages are laid out at this height so they do not follow
            // the animation.
            final restingHeight =
                (geometry.rect.height -
                        activeFooterHeight -
                        36 -
                        innerBottomPadding)
                    .clamp(0.0, geometry.rect.height)
                    .toDouble();

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
                      geometryIsMeasured: _contentSizes.containsKey(
                        currentPage,
                      ),
                      pages: pages,
                      transition: transition,
                      geometryMotion: widget.motionTheme.geometry,
                      effectsMotion: widget.motionTheme.effects,
                      effectsExitMotion: widget.motionTheme.effectsExit,
                      routeMotion: widget.motionTheme.route,
                      closeMotion: widget.motionTheme.close,
                      interactiveMotion: widget.motionTheme.interactive,
                      dragFadeDistance: widget.motionTheme.dragFadeDistance,
                      travel: widget.motionTheme.travel,
                      viewportHeight: layoutContext.size.height,
                      keyboardInset: viewInsets.bottom
                          .clamp(0.0, double.infinity)
                          .toDouble(),
                      closing:
                          widget.controller.lifecycle == TrayLifecycle.closing,
                      onTransitionSettled:
                          widget.controller.completePageTransition,
                      contentBuilder: (context, visualState) {
                        final rect = visualState.geometry.rect;
                        return Positioned.fill(
                          top: 36,
                          bottom: footer == null
                              ? innerBottomPadding
                              : activeFooterHeight + innerBottomPadding,
                          child: _buildContent(
                            context: context,
                            width: rect.width,
                            pages: pages,
                            pageWidgets: pageWidgets,
                            currentIndex: pages.indexOf(currentPage),
                            transition: transition,
                            pageProgresses: visualState.pageProgresses,
                            restingHeight: restingHeight,
                            // Bounded pages keep this height for the whole
                            // motion. It is the height a bounded page has as the
                            // current page, whatever page is shown now, so the
                            // surface reveals it instead of relaying it out.
                            boundedHeight: boundedFallbackHeight,
                            pageScale: widget.motionTheme.pageScale,
                            geometryForSize: (page, size) =>
                                _geometryForContentSize(
                                  page,
                                  size,
                                  layoutContext,
                                  footer == null ? 0.0 : _footerReserve,
                                ),
                          ),
                        );
                      },
                      builder: (context, visualState, content) {
                        final surfaceRadius = visualState.surfaceRadius;
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: Semantics(
                                label: widget.barrierDismissible
                                    ? 'Dismiss'
                                    : 'Modal barrier',
                                button: widget.barrierDismissible,
                                onTap: widget.barrierDismissible
                                    ? _handleBarrierTap
                                    : null,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: widget.barrierDismissible
                                      ? _handleBarrierTap
                                      : () {},
                                  // Fold the presentation progress into the
                                  // barrier alpha. An Opacity here would composite
                                  // a full-screen layer on every animated frame.
                                  child: ColoredBox(
                                    color: widget.barrierColor.withValues(
                                      alpha:
                                          widget.barrierColor.a *
                                          visualState.backdropOpacity,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fromRect(
                              // Layout uses the resting bounds only. The
                              // per-frame travel, drag and keyboard offsets go
                              // through a transform so the stack never relayouts
                              // while the tray animates.
                              rect: visualState.surfaceRect,
                              child: Transform.translate(
                                offset: visualState.surfaceOffset,
                                child: Transform.scale(
                                  scale: visualState.surfaceScale,
                                  // Keeps the moving surface in its own layer,
                                  // separate from the barrier.
                                  child: RepaintBoundary(
                                    child: DecoratedBox(
                                      decoration: ShapeDecoration(
                                        color: surfaceColor,
                                        shape: RoundedSuperellipseBorder(
                                          borderRadius: surfaceRadius,
                                        ),
                                      ),
                                      child: ClipRSuperellipse(
                                        borderRadius: surfaceRadius,
                                        clipBehavior: Clip.antiAlias,
                                        // Gives Material widgets (TextField,
                                        // InkWell, ListTile) and text styles a
                                        // Material ancestor inside the tray.
                                        child: Material(
                                          type: MaterialType.transparency,
                                          textStyle: textStyle,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Positioned.fill(
                                                // Isolates the pages from the
                                                // surface transform, so moving
                                                // the tray does not repaint them.
                                                child: RepaintBoundary(
                                                  child: Stack(
                                                    children: [content],
                                                  ),
                                                ),
                                              ),
                                              if (footer != null)
                                                Positioned(
                                                  bottom: innerBottomPadding,
                                                  left: 24,
                                                  right: 24,
                                                  child: footer,
                                                ),
                                              Positioned(
                                                top: 8,
                                                left: 0,
                                                right: 0,
                                                height: 28,
                                                // The drag is the only way to
                                                // close from the handle, so
                                                // expose a dismiss action for
                                                // assistive tech.
                                                child: Semantics(
                                                  label: 'Close',
                                                  button: true,
                                                  onTap:
                                                      widget.controller.close,
                                                  onDismiss:
                                                      widget.controller.close,
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
                                                          details.primaryVelocity ??
                                                              0,
                                                        ),
                                                    onVerticalDragCancel:
                                                        _cancelDrag,
                                                    child: const Align(
                                                      alignment:
                                                          Alignment.topCenter,
                                                      child: Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                              top: 8,
                                                            ),
                                                        child: TrayHandle(),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
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

class TraySizeObserver extends SingleChildRenderObjectWidget {
  const TraySizeObserver({
    super.key,
    required this.enabled,
    required this.onSizeChanged,
    this.deferCallback = true,
    super.child,
  });

  final bool enabled;
  final ValueChanged<Size> onSizeChanged;
  final bool deferCallback;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTraySizeObserver(enabled, onSizeChanged, deferCallback);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTraySizeObserver renderObject,
  ) {
    final wasEnabled = renderObject.enabled;
    renderObject.enabled = enabled;
    renderObject.onSizeChanged = onSizeChanged;
    renderObject.deferCallback = deferCallback;
    if (!wasEnabled && enabled) {
      renderObject.resetReportedSize();
    }
  }
}

class RenderTraySizeObserver extends RenderProxyBox {
  RenderTraySizeObserver(this.enabled, this.onSizeChanged, this.deferCallback);

  bool enabled;
  ValueChanged<Size> onSizeChanged;
  bool deferCallback;
  Size? _lastSize;

  void reportSize() {
    if (!deferCallback) {
      if (attached && enabled && hasSize) onSizeChanged(size);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && enabled) {
        onSizeChanged(size);
      }
    });
  }

  void resetReportedSize() {
    _lastSize = null;
    markNeedsLayout();
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
