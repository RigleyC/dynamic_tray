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
- The default surface uses 38 px rounded superellipse corners at the top.
  The bottom corners adapt to the device display: each radius is the display
  corner radius minus the matching 8 px side and bottom insets, clamped at zero.
  iOS values come from a model table; Android 12+ uses Flutter's per-corner
  display metrics. Without device metrics, the 38 px base radius is used to
  calculate the lower corners; iOS models missing from the table return zero.
  When the keyboard lifts the tray from the display edge, it uses the base
  radius instead.
  Call `warmUpTrayDeviceCorners()` while the app starts, before the first tray
  can be opened. Reading the plugin is a platform channel round trip, so reading
  it while a tray opens would land a rebuild in the middle of the opening
  animation. `TraySurface` also starts the read as a safety net, but a tray
  opened before it resolves uses the `MediaQuery` corners.
  The surface also keeps 24 px inner page padding and a handle. The
  footer sits 24 px from the bottom in a fixed 65 px slot.
  The outer left, right, and bottom gaps are 8 logical px. Content and footer
  use fixed 24 px bottom padding, regardless of the system safe area. With the
  keyboard open, the tray sits 8 px above it. There is no default
  width cap, so the 8 px side gaps hold on every phone; set `maxWidth` on
  the geometry resolver to opt into a centered width limit.
- Opening starts the spring as soon as the tray mounts, with a 0.94-to-1
  scale. The first measured content size is applied directly; later
  content-height changes use a spring. Incoming pages fade in with a 0.96-to-1
  scale.
- `TrayMotionTheme.original()` matches the reference: a `240/26` spring over
  `TrayTravel.fixed(1000)`, a 340 ms close, and the same 370 ms curve for
  page entry and exit. `TrayMotionTheme.snappy()` uses
  `TrayTravel.measured()` instead, so the tray starts exactly one tray height
  plus a small gap below the viewport and moves on the first frame, with a
  stiffer `400/34` spring, a 220 ms close and a 180 ms page exit.
- System back returns to the previous page, and closes the tray at the root.
  Navigation requested during a page transition runs once it settles, and a
  popped page's result is delivered after the transition, like `Navigator`.
- Dragging is attached to the handle. It dismisses the tray past 110 px or
  above 1000 px/s; otherwise it settles back with the gesture velocity. The
  backdrop fades over its own `dragFadeDistance`, not over the travel distance,
  so it stays readable for short sheets.
- `context.tray.setView` and `goBack` transition pages without pushing another
  route. The previous view remains available in the stack during the transition.
- One visual state keeps bounds, radius, scale, backdrop, keyboard/drag offset,
  and page progress synchronized. Motor drives the state through independent
  channels so each transition keeps the reference's spring or timing profile.
  `TrayMotionTheme.original()` (default) matches the reference timings;
  `TrayMotionTheme.snappy()` is a faster profile. Both can be customized.
  Per-frame travel, drag, and keyboard offsets are applied as a transform, so
  the stack lays out the tray at its resting bounds and never relayouts while it
  animates. The backdrop folds its progress into the barrier alpha instead of
  compositing a full-screen layer, and page content sits behind a
  `RepaintBoundary` so moving the tray does not repaint it.

`TrayHeader` is an optional neutral layout helper; the package does not impose
Material or Cupertino widgets, app colors, or typography on page content.

## Example

The example shows `TrayHeader` with a close icon on the first view and back
icons on later views. To run it on Android, use `cd example`, run
`flutter create --platforms android .` once to generate the local runner, then
run `flutter run`.
