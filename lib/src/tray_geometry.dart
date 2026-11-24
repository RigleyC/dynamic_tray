import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

class TrayGeometry {
  const TrayGeometry({required this.rect, required this.borderRadius});

  final Rect rect;
  final BorderRadius borderRadius;

  static TrayGeometry lerp(TrayGeometry a, TrayGeometry b, double t) {
    return TrayGeometry(
      rect: Rect.lerp(a.rect, b.rect, t) ?? b.rect,
      borderRadius:
          BorderRadius.lerp(a.borderRadius, b.borderRadius, t) ??
          b.borderRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrayGeometry &&
      rect == other.rect &&
      borderRadius == other.borderRadius;

  @override
  int get hashCode => Object.hash(rect, borderRadius);
}

class TrayGeometryMotionConverter extends MotionConverter<TrayGeometry> {
  const TrayGeometryMotionConverter();

  @override
  List<double> normalize(TrayGeometry value) {
    return [
      value.rect.center.dx,
      value.rect.bottom,
      value.rect.width,
      value.rect.height,
      value.borderRadius.topLeft.x,
      value.borderRadius.topLeft.y,
      value.borderRadius.topRight.x,
      value.borderRadius.topRight.y,
      value.borderRadius.bottomRight.x,
      value.borderRadius.bottomRight.y,
      value.borderRadius.bottomLeft.x,
      value.borderRadius.bottomLeft.y,
    ];
  }

  @override
  TrayGeometry denormalize(List<double> values) {
    Radius safeRadius(int x, int y) => Radius.elliptical(
      values[x].clamp(0.0, double.infinity).toDouble(),
      values[y].clamp(0.0, double.infinity).toDouble(),
    );

    final width = values[2].clamp(0.0, double.infinity).toDouble();
    final height = values[3].clamp(0.0, double.infinity).toDouble();
    return TrayGeometry(
      rect: Rect.fromLTWH(
        values[0] - width / 2,
        values[1] - height,
        width,
        height,
      ),
      borderRadius: BorderRadius.only(
        topLeft: safeRadius(4, 5),
        topRight: safeRadius(6, 7),
        bottomRight: safeRadius(8, 9),
        bottomLeft: safeRadius(10, 11),
      ),
    );
  }
}

class TrayLayoutContext {
  const TrayLayoutContext({
    required this.size,
    required this.padding,
    required this.viewInsets,
    this.displayCornerRadii,
  });

  final Size size;
  final EdgeInsets padding;
  final EdgeInsets viewInsets;

  /// Device display corner radii in logical pixels, when available.
  ///
  /// Resolvers can use these to make surfaces concentric with the display.
  final BorderRadius? displayCornerRadii;
}

abstract interface class TrayGeometryResolver {
  /// The tray's resting bounds for content of [contentSize], chrome included.
  ///
  /// The tray also asks with an infinite height to learn the tallest bounds it
  /// can take, so the result must cap the height.
  TrayGeometry resolve(TrayLayoutContext context, Size contentSize);
}

class DefaultTrayGeometryResolver implements TrayGeometryResolver {
  const DefaultTrayGeometryResolver({
    this.horizontalMargin = 8,
    this.bottomMargin = 8,
    this.maxWidth = double.infinity,
    this.radius = 38,
  });

  /// Gap from the left and right edges of the route viewport.
  final double horizontalMargin;

  /// Gap from the viewport bottom, or from the keyboard when it is open.
  final double bottomMargin;

  /// Centered width limit. Infinite by default so the tray always keeps
  /// [horizontalMargin] from both edges, which the concentric bottom corners
  /// rely on.
  final double maxWidth;

  /// Base radius for the top corners and fallback display geometry.
  final double radius;

  @override
  TrayGeometry resolve(TrayLayoutContext context, Size contentSize) {
    // The motion coordinator lifts the tray above the keyboard with a
    // transform, so the keyboard only shrinks the height here.
    final keyboardInset = math.max(0.0, context.viewInsets.bottom);
    final availableHeight = math.max(
      0.0,
      context.size.height - context.padding.top - bottomMargin - keyboardInset,
    );
    final width = math.max(
      0.0,
      math.min(context.size.width - horizontalMargin * 2, maxWidth),
    );
    final height = math.max(1.0, math.min(contentSize.height, availableHeight));
    final displayCorners =
        context.displayCornerRadii ?? BorderRadius.circular(radius);

    // Concentric with the display while the tray rests at its edge.
    Radius bottomCorner(Radius display) => keyboardInset > 0
        ? Radius.circular(radius)
        : Radius.elliptical(
            math.max(0.0, display.x - horizontalMargin),
            math.max(0.0, display.y - bottomMargin),
          );

    return TrayGeometry(
      rect: Rect.fromLTWH(
        (context.size.width - width) / 2,
        context.size.height - bottomMargin - height,
        width,
        height,
      ),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
        bottomRight: bottomCorner(displayCorners.bottomRight),
        bottomLeft: bottomCorner(displayCorners.bottomLeft),
      ),
    );
  }
}
