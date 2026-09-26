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
Give repeatedly reachable views a stable `viewId` so tapping the same
destination again reuses its page instead of adding another history entry.

## Layout and behavior

- Intrinsic pages size the tray to their measured content. If content changes
  after loading, the tray resizes with the reference height spring.
- `TrayPageLayout.bounded` gives scrolling pages a finite viewport that fills
  the available safe height. Use it for a root `ListView` or
  `CustomScrollView`; the page owns its scrolling behavior.
- The default surface follows the reference's 38 px
  rounded superellipse corners, 24 px inner page padding, and handle. The
  footer stays in a persistent slot whose actual height is measured for sizing.
  The outer left and right gaps are 8 logical px. The bottom gap is 8 logical
  px beyond the system safe area or above the keyboard. There is no default
  width cap; set `maxWidth` on the geometry resolver to opt into a centered
  width limit.
- Opening uses the reference spring, 0.94-to-1 scale, and a 1000 px travel.
  Closing uses a faster 200 ms ease-in curve without overshoot. Content-height
  changes use a spring; incoming pages use a 370 ms fade and 0.96-to-1 scale,
  while outgoing pages fade over 180 ms with an ease-in curve.
- Dragging is attached to the handle. It dismisses the tray past 110 px or
  above 1000 px/s; otherwise it settles back with the gesture velocity.
- `context.tray.setView` and `goBack` transition pages without pushing another
  route. The previous view remains available in the stack during the transition.
- One visual state keeps bounds, radius, scale, backdrop, keyboard/drag offset,
  and page progress synchronized. Motor drives the state through independent
  channels so each transition keeps the reference's spring or timing profile.
  `TrayMotionTheme.family()` provides those profiles and can be customized.

`TrayHeader` is an optional neutral layout helper; the package does not impose
Material or Cupertino widgets, app colors, or typography on page content.

## Example

The example shows `TrayHeader` with a close icon on the first view and back
icons on later views. To run it on Android, use `cd example`, run
`flutter create --platforms android .` once to generate the local runner, then
run `flutter run`.
