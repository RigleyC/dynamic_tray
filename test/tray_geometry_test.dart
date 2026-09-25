import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dynamic_tray/dynamic_tray.dart';

void main() {
  const resolver = DefaultTrayGeometryResolver();
  const layout = TrayLayoutContext(
    size: Size(400, 800),
    padding: EdgeInsets.only(top: 24, bottom: 20),
    viewInsets: EdgeInsets.zero,
  );

  test('content geometry uses the measured size and bottom safe area', () {
    final geometry = resolver.resolve(
      layout,
      TrayPresentation.content,
      const Size(320, 240),
    );

    expect(geometry.rect, const Rect.fromLTWH(8, 532, 384, 240));
    expect(geometry.borderRadius, BorderRadius.circular(28));
  });

  test('expanded geometry has a minimum fraction of available height', () {
    final geometry = resolver.resolve(
      layout,
      TrayPresentation.expanded,
      const Size(320, 100),
    );

    expect(geometry.rect.height, closeTo(538.56, 0.001));
    expect(geometry.rect.bottom, 772);
  });

  test('fullscreen geometry occupies the whole route', () {
    final geometry = resolver.resolve(
      layout,
      TrayPresentation.fullscreen,
      const Size(320, 240),
    );

    expect(geometry.rect, const Rect.fromLTWH(0, 0, 400, 800));
    expect(geometry.borderRadius, BorderRadius.zero);
  });

  test('content geometry clamps content to available height', () {
    final geometry = resolver.resolve(
      layout,
      TrayPresentation.content,
      const Size(320, 900),
    );

    expect(geometry.rect.height, 748);
  });

  test('geometry motion converter preserves bounds and radius', () {
    const geometry = TrayGeometry(
      rect: Rect.fromLTWH(12, 34, 300, 400),
      borderRadius: BorderRadius.only(
        topLeft: Radius.elliptical(28, 20),
        topRight: Radius.circular(24),
        bottomRight: Radius.circular(16),
        bottomLeft: Radius.circular(12),
      ),
    );
    const converter = TrayGeometryMotionConverter();

    final roundTrip = converter.denormalize(converter.normalize(geometry));

    expect(roundTrip.rect, geometry.rect);
    expect(roundTrip.borderRadius, geometry.borderRadius);
  });
}
