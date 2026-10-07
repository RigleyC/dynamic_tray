import 'dart:async';

import 'package:flutter/rendering.dart' show RenderBox, RenderProxyBox;
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'tray_controller.dart';
import 'tray_corner_radii.dart';
import 'tray_geometry.dart';
import 'tray_handle.dart';
import 'tray_motion_theme.dart';
import 'tray_page.dart';
import 'tray_restoration.dart';
import 'tray_shared_element.dart';

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
  bool _hasInitialMeasurement = false;

  /// Fixed space reserved for the footer, independent of its real height.
  static const double _footerReserve = 65;
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
    _contentSizes[page] = size;
    if (isCurrentPage) {
      _contentSize = size;
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

  Widget _buildPageLayer({
    required BuildContext context,
    required Widget page,
    required TrayPage<dynamic> pageEntry,
    required double width,
    required double height,
    required bool measure,
    required TrayGeometry Function(Size) geometryForSize,
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
      deferCallback: false,
      onSizeChanged: (size) =>
          _updateContentSize(pageEntry, size, geometryForSize(size)),
      child: child,
    );
    // Both layouts get a viewport of the available height. Intrinsic pages
    // size to their content, and scroll when that content is taller than the
    // viewport. Bounded pages own their scrolling.
    child = SizedBox(
      width: width,
      height: height,
      child: pageEntry.layout == TrayPageLayout.bounded
          ? child
          : SingleChildScrollView(child: child),
    );

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
      layers.add(
        _buildPageLayer(
          context: context,
          page: pageWidgets[index],
          pageEntry: page,
          width: rect.width,
          height: rect.height,
          measure: isCurrent,
          geometryForSize: (size) => geometryForSize(page, size),
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
            // Read only the aspects the tray depends on. MediaQuery.of listens
            // to every aspect, so a text scale or accessibility change would
            // rebuild the tray and every page builder it holds.
            final mediaQueryPadding = MediaQuery.paddingOf(context);
            final viewInsets = MediaQuery.viewInsetsOf(context);
            final currentPage = widget.controller.currentPage;
            final footer = currentPage.hideFooter
                ? null
                : currentPage.footerBuilder?.call(context) ??
                      currentPage.footer ??
                      widget.footerBuilder?.call(context) ??
                      widget.footer;
            final activeFooterHeight = footer == null ? 0.0 : _footerReserve;
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
                            rect: Rect.fromLTWH(
                              0,
                              0,
                              rect.width,
                              (rect.height -
                                      activeFooterHeight -
                                      36 -
                                      innerBottomPadding)
                                  .clamp(0.0, rect.height)
                                  .toDouble(),
                            ),
                            pages: pages,
                            pageWidgets: pageWidgets,
                            currentIndex: pages.indexOf(currentPage),
                            transition: transition,
                            pageProgresses: visualState.pageProgresses,
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
                                  child: DecoratedBox(
                                    decoration: ShapeDecoration(
                                      color:
                                          widget.surfaceColor ??
                                          const Color(0xFF141414),
                                      shape: RoundedSuperellipseBorder(
                                        borderRadius: surfaceRadius,
                                      ),
                                    ),
                                    child: ClipRSuperellipse(
                                      borderRadius: surfaceRadius,
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Positioned.fill(
                                            // Isolates the pages from the
                                            // surface transform, so moving the
                                            // tray does not repaint them.
                                            child: RepaintBoundary(
                                              child: Stack(children: [content]),
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
                                            // The drag is the only way to close
                                            // from the handle, so expose a
                                            // dismiss action for assistive tech.
                                            child: Semantics(
                                              label: 'Close',
                                              button: true,
                                              onTap: widget.controller.close,
                                              onDismiss:
                                                  widget.controller.close,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onVerticalDragStart: _startDrag,
                                                onVerticalDragUpdate:
                                                    _updateDrag,
                                                onVerticalDragEnd: (details) =>
                                                    _settleDrag(
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
                                          ),
                                        ],
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
