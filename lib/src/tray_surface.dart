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

  void _updateDrag(DragUpdateDetails details) {
    _visualMotionKey.currentState?.dragBy(details.primaryDelta ?? 0);
  }

  void _endDrag(DragEndDetails details) {
    _visualMotionKey.currentState?.endDrag(details.primaryVelocity ?? 0);
  }

  void _cancelDrag() => _visualMotionKey.currentState?.endDrag(0);

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
            // takes it, and an auto page scrolls past it. A resolver that does
            // not cap the height must not make the tray taller than the
            // viewport.
            final maxContentHeight = math.max(
              0.0,
              math.min(
                    widget.geometryResolver
                        .resolve(layoutContext, const Size(0, double.infinity))
                        .rect
                        .height,
                    layoutContext.size.height,
                  ) -
                  chromeHeight,
            );
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
            final pages = widget.controller.displayedPages;
            final transition = widget.controller.transition;
            final layout = _TrayContentLayout(
              currentPage: currentPage,
              transition: transition,
              // Hidden intrinsic pages are laid out at the resting content
              // height, so they do not follow the animation.
              restingHeight: math.max(0.0, geometry.rect.height - chromeHeight),
              maxContentHeight: maxContentHeight,
              geometryFor: geometryFor,
            );
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
                barrierColor: widget.barrierColor,
                barrierBuilder: _buildBarrier,
                contentBuilder: (context, motions) => Stack(
                  key: _contentStackKey,
                  children: [
                    Positioned.fill(
                      top: _TrayChrome.top,
                      bottom: chromeHeight - _TrayChrome.top,
                      child: ScrollConfiguration(
                        behavior: _trayScrollBehavior(context),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final page in pages)
                              _buildPageLayer(
                                page,
                                _pageWidgetFor(context, page),
                                motions,
                                layout,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (transition != null)
                      Positioned.fill(
                        child: _buildSharedElementFlights(transition, motions),
                      ),
                  ],
                ),
                surfaceBuilder: (context, geometry, content) => _buildSurface(
                  geometry: geometry,
                  content: content,
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

  // Cached: a new behavior would make every scroll view in the tray replace
  // its scroll position on each surface build, such as each keyboard frame.
  ScrollBehavior? _scrollBehaviorSource;
  late ScrollBehavior _scrollBehavior;

  ScrollBehavior _trayScrollBehavior(BuildContext context) {
    final source = ScrollConfiguration.of(context);
    if (!identical(source, _scrollBehaviorSource)) {
      _scrollBehaviorSource = source;
      _scrollBehavior = source.copyWith(
        physics: _TrayScrollPhysics(
          _visualMotionKey,
          parent: source.getScrollPhysics(context),
        ),
      );
    }
    return _scrollBehavior;
  }

  Widget _buildPageLayer(
    TrayPage<dynamic> page,
    Widget pageWidget,
    _TrayMotions motions,
    _TrayContentLayout layout,
  ) {
    final current = identical(page, layout.currentPage);
    final transition = layout.transition;
    final isBounded = page.layout == TrayPageLayout.bounded;
    Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _TrayChrome.horizontal),
      child: page.layout == TrayPageLayout.auto
          ? TrayAutoScroll(
              maxHeight: layout.maxContentHeight,
              child: pageWidget,
            )
          : pageWidget,
    );
    child = TraySharedElementScope(
      registry: _sharedElementRegistry,
      page: page,
      current: current,
      transition: transition,
      toLocalRect: _toLocalRect,
      child: child,
    );
    child = TraySizeObserver(
      enabled: current,
      onSizeChanged: (size) =>
          _handlePageLaidOut(page, size, layout.geometryFor(page, size)),
      // The fade and scale below change on every frame of a page change. The
      // boundary keeps them from repainting the page itself.
      child: RepaintBoundary(child: child),
    );
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
    final scales = identical(page, scalingPage);
    final pageScale = widget.motionTheme.pageScale;
    final alwaysVisible = current || identical(page, transition?.outgoing);
    final progress = motions.progressOf(page);
    return AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) {
        final value = progress.value.clamp(0.0, 1.0);
        final visible = alwaysVisible || value > 0;
        // Hidden pages stop their tickers. Bounded and hidden pages also take
        // a fixed size, so the animating surface height does not relayout
        // them on every frame. The surface clips the layer while it animates.
        final layer = TickerMode(
          enabled: visible,
          child: Offstage(
            offstage: !visible,
            child: IgnorePointer(
              ignoring: !current,
              child: Opacity(
                opacity: value,
                child: Transform.scale(
                  scale: scales ? pageScale + (1 - pageScale) * value : 1,
                  child: child,
                ),
              ),
            ),
          ),
        );
        return Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: isBounded
              ? layout.maxContentHeight
              : visible
              ? null
              : layout.restingHeight,
          child: layer,
        );
      },
    );
  }

  // Flights share the incoming page's progress, so they land with the page
  // they reveal. Their destination is read on every frame, so it follows the
  // page's growth and scale instead of the bounds from its first layout.
  Widget _buildSharedElementFlights(
    TrayPageTransition transition,
    _TrayMotions motions,
  ) {
    final progress = motions.progressOf(transition.incoming);
    return AnimatedBuilder(
      animation: Listenable.merge([progress, motions.geometry]),
      builder: (context, _) {
        final value = progress.value.clamp(0.0, 1.0);
        return Stack(
          children: [
            for (final match in _sharedElementRegistry.matches(transition))
              Positioned.fromRect(
                key: ValueKey<(int, Object)>((transition.id, match.tag)),
                rect:
                    Rect.lerp(match.outgoingRect, match.incomingRect, value) ??
                    match.incomingRect,
                child: IgnorePointer(child: _flightChild(context, match)),
              ),
          ],
        );
      },
    );
  }

  Widget _flightChild(BuildContext context, TraySharedElementMatch match) {
    // The flight takes over the live element, so the content keeps its State.
    final live = KeyedSubtree(key: match.contentKey, child: match.child);
    return match.flightBuilder?.call(context, live) ?? live;
  }

  Widget _buildBarrier(BuildContext context, Widget backdrop) {
    return Semantics(
      label: widget.barrierDismissible ? 'Dismiss' : 'Modal barrier',
      button: widget.barrierDismissible,
      onTap: widget.barrierDismissible ? _handleBarrierTap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleBarrierTap,
        child: backdrop,
      ),
    );
  }

  Widget _buildSurface({
    required Animation<TrayGeometry> geometry,
    required Widget content,
    required Widget? footer,
    required Color surfaceColor,
    required TextStyle? textStyle,
  }) {
    final body = Material(
      type: MaterialType.transparency,
      textStyle: textStyle,
      child: flutter_material.Material(
        type: flutter_material.MaterialType.transparency,
        textStyle: textStyle,
        // Like a bottom sheet, the whole surface drags. Scroll views inside
        // keep their own drags and hand them over at their top edge.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _updateDrag,
          onVerticalDragEnd: _endDrag,
          onVerticalDragCancel: _cancelDrag,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Moving the tray does not repaint the pages.
              Positioned.fill(child: RepaintBoundary(child: content)),
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
                // Assistive tech cannot drag, so the handle closes on tap.
                child: Semantics(
                  label: 'Close',
                  button: true,
                  onTap: widget.controller.close,
                  onDismiss: widget.controller.close,
                  child: const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: _TrayChrome.handleInset),
                      child: TrayHandle(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: geometry,
        child: body,
        builder: (context, body) {
          final radius = geometry.value.borderRadius;
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: surfaceColor,
              shape: RoundedSuperellipseBorder(borderRadius: radius),
            ),
            child: ClipRSuperellipse(
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: body,
            ),
          );
        },
      ),
    );
  }
}

/// What every page layer needs from one surface build.
class _TrayContentLayout {
  const _TrayContentLayout({
    required this.currentPage,
    required this.transition,
    required this.restingHeight,
    required this.maxContentHeight,
    required this.geometryFor,
  });

  final TrayPage<dynamic> currentPage;
  final TrayPageTransition? transition;
  final double restingHeight;
  final double maxContentHeight;
  final TrayGeometry Function(TrayPage<dynamic>, Size) geometryFor;
}

/// Hands vertical drags between a scroll view in the tray and the tray.
///
/// A pull down at the scroll view's top edge moves the tray instead of
/// overscrolling, and a push up moves the tray back before the content
/// scrolls, like a bottom sheet. Content that fits does not take drags, so
/// the tray gets them.
class _TrayScrollPhysics extends ScrollPhysics {
  const _TrayScrollPhysics(this.coordinator, {super.parent});

  final GlobalKey<_TrayMotionCoordinatorState> coordinator;

  @override
  _TrayScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _TrayScrollPhysics(coordinator, parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      position.maxScrollExtent > position.minScrollExtent &&
      (parent?.shouldAcceptUserOffset(position) ?? true);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    final tray = coordinator.currentState;
    if (tray == null) return super.applyPhysicsToUserOffset(position, offset);
    // A positive offset is a pull down. The content scrolls back to its top
    // edge first, then the tray takes the rest.
    final double toTray;
    if (offset > 0) {
      final toTop = math.max(0.0, position.pixels - position.minScrollExtent);
      toTray = tray.dragOffset > 0 ? offset : math.max(0.0, offset - toTop);
    } else {
      toTray = tray.dragOffset > 0 ? offset : 0.0;
    }
    final used = toTray == 0 ? 0.0 : tray.dragBy(toTray);
    return super.applyPhysicsToUserOffset(position, offset - used);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tray = coordinator.currentState;
    if (tray != null && tray.isDragging) {
      final trayMoved = tray.dragOffset > 0;
      // Scroll velocity is positive upward, tray velocity downward.
      tray.endDrag(-velocity);
      // A release with the tray pulled down belongs to the tray.
      if (trayMoved) return null;
    }
    return super.createBallisticSimulation(position, velocity);
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
