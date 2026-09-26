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
  });

  final Size size;
  final EdgeInsets padding;
  final EdgeInsets viewInsets;
}

abstract interface class TrayGeometryResolver {
  TrayGeometry resolve(TrayLayoutContext context, Size contentSize);
}

class DefaultTrayGeometryResolver implements TrayGeometryResolver {
  const DefaultTrayGeometryResolver({
    this.horizontalMargin = 8,
    this.bottomMargin = 8,
    this.maxWidth = 360,
    this.radius = 38,
  });

  final double horizontalMargin;
  final double bottomMargin;
  final double maxWidth;
  final double radius;

  @override
  TrayGeometry resolve(TrayLayoutContext context, Size contentSize) {
    final safeTop = context.padding.top;
    final safeBottom = context.padding.bottom;
    final bottomInset = safeBottom;
    final availableHeight = (context.size.height -
            safeTop -
            bottomInset -
            bottomMargin)
        .clamp(0.0, context.size.height);
    final availableWidth = (context.size.width - horizontalMargin * 2).clamp(
      0.0,
      context.size.width,
    );
    final width = availableWidth.clamp(0.0, maxWidth).toDouble();

    final naturalHeight = contentSize.height.clamp(0.0, availableHeight);
    final height = naturalHeight;
    final safeHeight = height == 0 ? 1.0 : height;

    return TrayGeometry(
      rect: Rect.fromLTWH(
        (context.size.width - width) / 2,
        context.size.height - bottomInset - bottomMargin - safeHeight,
        width,
        safeHeight,
      ),
      borderRadius: BorderRadius.circular(radius),
    );
  }
}
