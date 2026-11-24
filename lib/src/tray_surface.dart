import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
// material_ui ships its own Material. Flutter's TextField, Checkbox and other
// material widgets look up Flutter's Material, so the tray provides both.
import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter/rendering.dart' show RenderBox, RenderProxyBox;
import 'package:motor/motor.dart';

import 'tray_auto_scroll.dart';
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

/// Space the tray reserves around page content.
abstract final class _TrayChrome {
  static const double handleInset = 8;
  static const double handleHeight = 28;

  /// The handle area above the page.
  static const double top = handleInset + handleHeight;
  static const double bottom = 24;
  static const double horizontal = 24;

  /// Fixed space for the footer, independent of its real height.
  static const double footer = 65;

  static double height({required bool hasFooter}) =>
      top + bottom + (hasFooter ? footer : 0);
}

class _TraySurfaceState extends State<TraySurface> with RestorationMixin {
  // The last size the current page reported. A page that has not been laid out
  // yet sizes the tray with it, so the tray does not collapse while it builds.
  Size _lastMeasuredSize = Size.zero;
  final Map<TrayPage<dynamic>, Size> _contentSizes = {};
  // Built once per page. The tray rebuilds on each controller change and on
  // each MediaQuery change, such as the keyboard, and the page builders must
  // not run again for those.
  final Map<TrayPage<dynamic>, Widget> _pageWidgets = {};
  final Map<TrayPage<dynamic>, Widget?> _footers = {};
  double _dragTranslation = 0;
  bool _isDragging = false;
  bool _contentDragActive = false;
  double _contentDragTranslation = 0;
  // The stack that holds the pages and the shared-element flights. Its
  // coordinates ignore the surface's offset and drag, so flights measured here
  // move with the tray.
  final GlobalKey _contentStackKey = GlobalKey();
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
    // startup. Never followed by a setState: a tray opened before it resolves
    // keeps the MediaQuery corners instead of rebuilding mid-flight.
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
    final retainedPages = widget.controller.displayedPages.toSet();
    final transition = widget.controller.transition;
    _contentSizes.removeWhere((page, _) => !retainedPages.contains(page));
    _pageWidgets.removeWhere((page, _) => !retainedPages.contains(page));
    _footers.removeWhere((page, _) => !retainedPages.contains(page));
    if (transition != null) {
      // Runs before any frame moves the outgoing page, so its rect is at rest.
      _sharedElementRegistry.beginTransition(transition);
    }
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
    final content = _contentStackKey.currentContext?.findRenderObject();
    if (content is! RenderBox || !content.hasSize || !renderObject.attached) {
      return null;
    }
    final topLeft = content.globalToLocal(
      renderObject.localToGlobal(Offset.zero),
    );
    final bottomRight = content.globalToLocal(
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero)),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// Runs during layout, each time the current page reports a new size.
  void _handlePageLaidOut(
    TrayPage<dynamic> page,
    Size size,
    TrayGeometry geometry,
  ) {
    if (!mounted || !identical(widget.controller.currentPage, page)) {
      return;
    }
    final coordinator = _visualMotionKey.currentState;
    coordinator?.pageLaidOut(page);
    _contentSizes[page] = size;
    _lastMeasuredSize = size;
    coordinator?.reportMeasuredGeometry(geometry);
  }

  void _startDrag(DragStartDetails details) {
    _isDragging = true;
    _dragTranslation = 0;
    _visualMotionKey.currentState?.beginDrag();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_isDragging) return;
    _dragTranslation += details.primaryDelta ?? 0;
    _visualMotionKey.currentState?.dragTo(_dragTranslation);
  }

  void _cancelDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    _visualMotionKey.currentState?.cancelDrag();
  }

  void _settleDrag(DragEndDetails details) {
    if (!_isDragging) return;
    _isDragging = false;
    _visualMotionKey.currentState?.settleDrag(details.primaryVelocity ?? 0);
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
    required Widget page,
    required TrayPage<dynamic> pageEntry,
    required double width,
    required double height,
    required double maxHeight,
    required bool current,
    required bool visible,
    required double progress,
    required double pageScale,
    required TrayPageTransition? transition,
    required ValueChanged<Size> onLaidOut,
  }) {
    Widget child = SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _TrayChrome.horizontal),
        child: pageEntry.layout == TrayPageLayout.auto
            ? TrayAutoScroll(maxHeight: maxHeight, child: page)
            : page,
      ),
    );
    child = TraySharedElementScope(
      registry: _sharedElementRegistry,
      page: pageEntry,
      current: current,
      transition: transition,
      toLocalRect: _toLocalRect,
      child: child,
    );
    child = TraySizeObserver(
      enabled: current,
      onSizeChanged: onLaidOut,
      // The fade and scale below change on every frame of a page change. The
      // boundary keeps them from repainting the page itself.
      child: RepaintBoundary(child: child),
    );
    final isBounded = pageEntry.layout == TrayPageLayout.bounded;
    if (!isBounded) {
      child = Align(alignment: Alignment.topCenter, child: child);
    }

    // On a forward change only the entering page grows from pageScale to 1.
    // On a back change only the leaving page shrinks from 1 to pageScale.
    final scalingPage = switch (transition) {
      null => null,
      TrayPageTransition(isPush: true, :final incoming) => incoming,
      TrayPageTransition(:final outgoing) => outgoing,
    };
    final scale = identical(pageEntry, scalingPage)
        ? pageScale + (1 - pageScale) * progress
        : 1.0;
    // Hidden pages stop their tickers. Bounded and hidden pages also take a
    // fixed size, so the animating surface height does not relayout them on
    // every frame. The surface clips the layer while it animates.
    final layer = TickerMode(
      enabled: visible,
      child: Offstage(
        offstage: !visible,
        child: IgnorePointer(
          ignoring: !current,
          child: Opacity(
            opacity: progress,
            child: Transform.scale(scale: scale, child: child),
          ),
        ),
      ),
    );
    if (isBounded || !visible) {
      return Positioned(
        left: 0,
        top: 0,
        width: width,
        height: height,
        child: layer,
      );
    }
    return Positioned(left: 0, right: 0, top: 0, child: layer);
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
    if (widget.barrierDismissible) {
      widget.controller.close();
    }
  }

  // Flights share the incoming page's progress, so they land with the page
  // they reveal. Their destination is read on every frame, so it follows the
  // page's growth and scale instead of the bounds from its first layout.
  List<Widget> _buildSharedElementFlights(
    BuildContext context,
    TrayPageTransition? transition,
    Map<TrayPage<dynamic>, double> pageProgresses,
  ) {
    if (transition == null) {
      return const [];
    }
    final progress = (pageProgresses[transition.incoming] ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    return [
      for (final match in _sharedElementRegistry.matches(transition))
        _TraySharedElementFlight(
          key: ValueKey<(int, Object)>((transition.id, match.tag)),
          from: match.outgoingRect,
          to: match.incomingRect,
          progress: progress,
          child: _flightChild(context, match),
        ),
    ];
  }

  Widget _flightChild(BuildContext context, TraySharedElementMatch match) {
    // The flight takes over the live element, so the content keeps its State.
    final live = KeyedSubtree(key: match.contentKey, child: match.child);
    return match.flightBuilder?.call(context, live) ?? live;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // MediaQuery.of listens to every aspect, so a text scale change
            // would rebuild the tray. Read only the aspects it uses.
            final viewInsets = MediaQuery.viewInsetsOf(context);
            final layoutContext = TrayLayoutContext(
              size: constraints.biggest,
              padding: MediaQuery.paddingOf(context),
              viewInsets: viewInsets,
              displayCornerRadii:
                  trayDeviceCornerRadii ??
                  MediaQuery.displayCornerRadiiOf(context),
            );
            final currentPage = widget.controller.currentPage;
            final footer = _footerFor(context, currentPage);
            final chromeHeight = _TrayChrome.height(hasFooter: footer != null);
            // The tallest content the tray can hold. A bounded page always
            // takes it, and an auto page scrolls past it.
            // A resolver that does not cap the height must not make the tray
            // taller than the viewport.
            final maxContentHeight =
                (widget.geometryResolver
                            .resolve(
                              layoutContext,
                              const Size(0, double.infinity),
                            )
                            .rect
                            .height
                            .clamp(0.0, layoutContext.size.height) -
                        chromeHeight)
                    .clamp(0.0, double.infinity)
                    .toDouble();
            TrayGeometry geometryFor(TrayPage<dynamic> page, Size size) =>
                widget.geometryResolver.resolve(
                  layoutContext,
                  Size(
                    size.width,
                    (page.layout == TrayPageLayout.bounded
                            ? maxContentHeight
                            : size.height) +
                        chromeHeight,
                  ),
                );
            final geometry = geometryFor(
              currentPage,
              _contentSizes[currentPage] ?? _lastMeasuredSize,
            );
            // Hidden intrinsic pages are laid out at the resting content
            // height, so they do not follow the animation.
            final restingHeight = math.max(
              0.0,
              geometry.rect.height - chromeHeight,
            );
            final transition = widget.controller.transition;
            final pages = widget.controller.displayedPages;
            final pageWidgets = [
              for (final page in pages) _pageWidgetFor(context, page),
            ];
            // Theme lookups run once per surface build, not once per frame.
            final surfaceColor =
                widget.surfaceColor ?? traySurfaceColorOf(context);
            final textStyle = trayTextStyleOf(context);

            return ListenableBuilder(
              listenable: _sharedElementRegistry,
              builder: (context, _) => _TrayMotionCoordinator(
                key: _visualMotionKey,
                controller: widget.controller,
                motionTheme: widget.motionTheme,
                geometry: geometry,
                geometryIsMeasured: _contentSizes.containsKey(currentPage),
                pages: pages,
                transition: transition,
                viewportHeight: layoutContext.size.height,
                keyboardInset: math.max(0.0, viewInsets.bottom),
                closing: widget.controller.lifecycle == TrayLifecycle.closing,
                contentBuilder: (context, visualState) => Positioned.fill(
                  top: _TrayChrome.top,
                  bottom: chromeHeight - _TrayChrome.top,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleContentScroll,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        for (var index = 0; index < pages.length; index++)
                          _buildPageLayerFor(
                            pages[index],
                            pageWidgets[index],
                            currentPage: currentPage,
                            transition: transition,
                            visualState: visualState,
                            restingHeight: restingHeight,
                            maxContentHeight: maxContentHeight,
                            geometryFor: geometryFor,
                          ),
                      ],
                    ),
                  ),
                ),
                builder: (context, visualState, content) => _buildSurface(
                  context,
                  visualState: visualState,
                  content: content,
                  transition: transition,
                  footer: footer,
                  surfaceColor: surfaceColor,
                  textStyle: textStyle,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPageLayerFor(
    TrayPage<dynamic> page,
    Widget pageWidget, {
    required TrayPage<dynamic> currentPage,
    required TrayPageTransition? transition,
    required _TrayVisualState visualState,
    required double restingHeight,
    required double maxContentHeight,
    required TrayGeometry Function(TrayPage<dynamic>, Size) geometryFor,
  }) {
    final current = identical(page, currentPage);
    final progress = (visualState.pageProgresses[page] ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    return _buildPageLayer(
      page: pageWidget,
      pageEntry: page,
      width: visualState.geometry.rect.width,
      height: page.layout == TrayPageLayout.bounded
          ? maxContentHeight
          : restingHeight,
      maxHeight: maxContentHeight,
      current: current,
      visible: current || identical(page, transition?.outgoing) || progress > 0,
      progress: progress,
      pageScale: widget.motionTheme.pageScale,
      transition: transition,
      onLaidOut: (size) =>
          _handlePageLaidOut(page, size, geometryFor(page, size)),
    );
  }

  Widget _buildSurface(
    BuildContext context, {
    required _TrayVisualState visualState,
    required Widget content,
    required TrayPageTransition? transition,
    required Widget? footer,
    required Color surfaceColor,
    required TextStyle? textStyle,
  }) {
    final radius = visualState.geometry.borderRadius;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Semantics(
            label: widget.barrierDismissible ? 'Dismiss' : 'Modal barrier',
            button: widget.barrierDismissible,
            onTap: widget.barrierDismissible ? _handleBarrierTap : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleBarrierTap,
              // The progress goes into the barrier alpha. An Opacity here
              // would composite a full-screen layer on every animated frame.
              child: ColoredBox(
                color: widget.barrierColor.withValues(
                  alpha: widget.barrierColor.a * visualState.backdropOpacity,
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: visualState.geometry.rect,
          // Travel, drag and keyboard offsets go through a transform, so they
          // never relayout the tray.
          child: Transform.translate(
            offset: visualState.surfaceOffset,
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: surfaceColor,
                  shape: RoundedSuperellipseBorder(borderRadius: radius),
                ),
                child: ClipRSuperellipse(
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    type: MaterialType.transparency,
                    textStyle: textStyle,
                    child: flutter_material.Material(
                      type: flutter_material.MaterialType.transparency,
                      textStyle: textStyle,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            // Moving the tray does not repaint the pages.
                            child: RepaintBoundary(
                              child: Stack(
                                key: _contentStackKey,
                                children: [
                                  content,
                                  ..._buildSharedElementFlights(
                                    context,
                                    transition,
                                    visualState.pageProgresses,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (footer != null)
                            Positioned(
                              bottom: _TrayChrome.bottom,
                              left: _TrayChrome.horizontal,
                              right: _TrayChrome.horizontal,
                              child: footer,
                            ),
                          Positioned(
                            top: _TrayChrome.handleInset,
                            left: 0,
                            right: 0,
                            height: _TrayChrome.handleHeight,
                            // The drag is the only way to close from the
                            // handle, so assistive tech gets a dismiss action.
                            child: Semantics(
                              label: 'Close',
                              button: true,
                              onTap: widget.controller.close,
                              onDismiss: widget.controller.close,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragStart: _startDrag,
                                onVerticalDragUpdate: _updateDrag,
                                onVerticalDragEnd: _settleDrag,
                                onVerticalDragCancel: _cancelDrag,
                                child: const Align(
                                  alignment: Alignment.topCenter,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: _TrayChrome.handleInset,
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
      ],
    );
  }
}

/// Reports its child's size during layout while [enabled], each time the size
/// changes and once more when it becomes enabled.
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
    renderObject
      ..enabled = enabled
      ..onSizeChanged = onSizeChanged;
  }
}

class RenderTraySizeObserver extends RenderProxyBox {
  RenderTraySizeObserver(this._enabled, this.onSizeChanged);

  ValueChanged<Size> onSizeChanged;
  Size? _reportedSize;

  bool get enabled => _enabled;
  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) return;
    _enabled = value;
    if (value) {
      _reportedSize = null;
      markNeedsLayout();
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    if (!enabled || _reportedSize == size) return;
    _reportedSize = size;
    onSizeChanged(size);
  }
}

class _TraySharedElementFlight extends StatelessWidget {
  const _TraySharedElementFlight({
    super.key,
    required this.from,
    required this.to,
    required this.progress,
    required this.child,
  });

  final Rect from;
  final Rect to;
  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rect = Rect.lerp(from, to, progress) ?? to;
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(child: child),
    );
  }
}
