import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

import 'tray_presentation.dart';

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
      value.rect.left,
      value.rect.top,
      value.rect.right,
      value.rect.bottom,
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

    return TrayGeometry(
      rect: Rect.fromLTRB(values[0], values[1], values[2], values[3]),
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
  });

  final Size size;
  final EdgeInsets padding;
  final EdgeInsets viewInsets;
}

abstract interface class TrayGeometryResolver {
  TrayGeometry resolve(
    TrayLayoutContext context,
    TrayPresentation presentation,
    Size contentSize,
  );
}

class DefaultTrayGeometryResolver implements TrayGeometryResolver {
  const DefaultTrayGeometryResolver({
    this.horizontalMargin = 8,
    this.bottomMargin = 8,
    this.expandedFraction = 0.72,
    this.fullscreenRadius = 0,
    this.contentRadius = 28,
  });

  final double horizontalMargin;
  final double bottomMargin;
  final double expandedFraction;
  final double fullscreenRadius;
  final double contentRadius;

  @override
  TrayGeometry resolve(
    TrayLayoutContext context,
    TrayPresentation presentation,
    Size contentSize,
  ) {
    final viewInsets = context.viewInsets;
    final safeTop = context.padding.top;
    final bottomInset =
        viewInsets.bottom > 0 ? viewInsets.bottom : context.padding.bottom;
    final availableHeight =
        (context.size.height - safeTop - bottomInset - bottomMargin).clamp(
          0.0,
          context.size.height,
        );
    final width = (context.size.width - horizontalMargin * 2).clamp(
      0.0,
      context.size.width,
    );

    if (presentation == TrayPresentation.fullscreen) {
      final fullscreenHeight =
          viewInsets.bottom > 0
              ? context.size.height - viewInsets.bottom
              : context.size.height;
      return TrayGeometry(
        rect: Rect.fromLTWH(0, 0, context.size.width, fullscreenHeight),
        borderRadius: BorderRadius.circular(fullscreenRadius),
      );
    }

    final naturalHeight = contentSize.height.clamp(0.0, availableHeight);
    final height =
        presentation == TrayPresentation.expanded
            ? naturalHeight.clamp(
              availableHeight * expandedFraction,
              availableHeight,
            )
            : naturalHeight;
    final safeHeight = height == 0 ? 1.0 : height;

    return TrayGeometry(
      rect: Rect.fromLTWH(
        horizontalMargin,
        context.size.height - bottomInset - bottomMargin - safeHeight,
        width,
        safeHeight,
      ),
      borderRadius: BorderRadius.circular(contentRadius),
    );
  }
}
