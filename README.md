# dynamic_tray

A Flutter tray inspired by Expo Dynamic Tray. One route owns the complete tray
session; pages, content-driven sizing, keyboard movement, dragging, backdrop,
and dismissal stay coordinated on that surface.

## Open a tray

```dart
final result = await context.openTray<String>(
  builder: (_) => const WalletDetailsPage(),
);
```

Inside a page, use `context.tray` to replace the current view, navigate back,
or close the entire tray:

```dart
context.tray.setView(
  viewId: 'choose-category',
  builder: (_) => const ChooseCategoryPage(),
);

context.tray.goBack();
context.tray.close('saved');
```

`goBack` returns to the previous view within the same tray. `close` and
`dismiss` close the whole session. Android system back also dismisses the tray.

## Layout and behavior

- Intrinsic pages size the tray to their measured content. If content changes
  after loading, the tray resizes with the reference height spring.
- `TrayPageLayout.bounded` gives scrolling pages a finite viewport that fills
  the available safe height. Use it for a root `ListView` or
  `CustomScrollView`; the page owns its scrolling behavior.
- The default surface follows the reference's 360 px maximum width, 38 px
  corner radius, 24 px inner page padding, handle, and persistent 65 px footer
  slot. The only spacing override is an 8 px gap from the device edges and
  keyboard, in addition to system safe-area insets.
- Opening uses the reference spring, 0.94-to-1 scale, and a 1000 px travel.
  Closing uses its 340 ms timing curve. Content-height changes use a spring;
  page changes use a 370 ms fade and 0.96-to-1 scale.
- Dragging is attached to the handle. It dismisses the tray past 110 px or
  above 1000 px/s; otherwise it settles back with the gesture velocity.
- `context.tray.setView` and `goBack` transition pages without pushing another
  route. The previous view remains available in the stack during the transition.
- Motion is implemented through Motor. `TrayMotionTheme.family()` provides
  the reference profiles, and `TrayMotionTheme` can be customized when needed.

`TrayHeader` is an optional neutral layout helper; the package does not impose
Material or Cupertino widgets, app colors, or typography on page content.

## Example

Run the interactive example with `cd example` and `flutter run`.
