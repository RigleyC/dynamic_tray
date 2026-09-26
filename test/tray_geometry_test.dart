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

  test('measured content keeps the reference radius and edge spacing', () {
    final geometry = resolver.resolve(layout, const Size(320, 240));

    expect(geometry.rect, const Rect.fromLTWH(20, 532, 360, 240));
    expect(geometry.borderRadius, BorderRadius.circular(38));
  });

  test('narrow tray keeps the requested eight-pixel edge spacing', () {
    final geometry = resolver.resolve(
      const TrayLayoutContext(
        size: Size(360, 800),
        padding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      const Size(320, 240),
    );

    expect(geometry.rect, const Rect.fromLTWH(8, 552, 344, 240));
  });

  test('long measured content fills the available height', () {
    final geometry = resolver.resolve(layout, const Size(320, 900));

    expect(geometry.rect.height, 748);
    expect(geometry.rect.bottom, 772);
  });

  test('long content is capped at the safe available height', () {
    final geometry = resolver.resolve(layout, const Size(320, 900));

    expect(geometry.rect.height, 748);
    expect(geometry.rect.top, 24);
    expect(geometry.borderRadius, BorderRadius.circular(38));
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
