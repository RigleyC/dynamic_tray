# dynamic_tray

The first foundation for a Family-inspired, motion-driven surface navigation
system in Flutter.

```dart
final result = await showTray<String>(
  context: context,
  page: TrayPage(
    builder: (_) => const WalletPicker(),
  ),
  footer: const WalletPickerActions(),
);
```

The optional route-level `footer` is hosted by the tray surface, so it stays
mounted while pages are pushed and popped. A page can provide its own footer,
or set `hideFooter: true` to hide both its own footer and the route fallback.
Page footers occupy one persistent surface slot, so sharing the same widget
instance across pages preserves its state:

```dart
final sharedActions = const WalletPickerActions();

final firstPage = TrayPage(
  builder: (_) => const WalletPicker(),
  footer: sharedActions,
);
final detailsPage = TrayPage(
  builder: (_) => const WalletDetails(),
  footer: sharedActions,
);
```

When a page's `footer` is null, the route-level footer remains the fallback
unless `hideFooter` is true. The active footer's measured height is included in
compact tray sizing and reserved from the page viewport. `surfaceColor` can be
supplied to `showTray` when the app needs a non-white neutral surface; the
package itself does not read a Material or Cupertino theme.

`TrayHeader` is an optional layout helper. It accepts `leading`, `title`,
`subtitle`, and `trailing` widgets and does not impose icons, typography,
colors, or actions:

```dart
TrayHeader(
  leading: const AccountAvatar(),
  title: const Text('Choose account'),
  subtitle: const Text('Select where to transfer from.'),
  trailing: const Text('Done'),
)
```

Tray pages declare their layout contract. Intrinsic pages are measured from
their live content and are ideal for short forms and compact steps. Bounded
pages receive a finite viewport and must own their scrolling, which makes them
the right choice for `ListView`, `CustomScrollView`, and sliver-heavy pages:

```dart
TrayPage(
  layout: TrayPageLayout.bounded,
  builder: (_) => const WalletListPage(),
)
```

The tray does not insert a universal `SingleChildScrollView` around pages.
This avoids nested scroll views and invalid sliver geometry; the page's own
scrollable receives the viewport it needs.

Inside a tray page, navigation and presentation stay local to the surface:

```dart
final tray = context.tray;

tray.expand();
tray.fullscreen();

final value = await tray.push<String>(
  TrayPage(builder: (_) => const ConfirmPage()),
);

tray.pop(value);
```

Pages can opt into a tag-matched visual flight:

```dart
TraySharedElement(
  tag: 'wallet-avatar',
  flightBuilder: (context, child) => Material(
    type: MaterialType.transparency,
    child: child,
  ),
  child: const CircleAvatar(),
)
```

Place the same tag on the destination page. If either page does not declare a
matching tag, the normal page transition is used. The flight is visual-only;
state and pointer ownership remain in the page widgets.

The surface uses `motor` for route entry/exit, geometry, page effects, and drag settling. Page
changes combine crossfade, a subtle scale, and horizontal movement, all derived
from the same `pageProgress`. Route entry/exit and its backdrop use the route
animation; backdrop opacity also retargets with the effects motion during
fullscreen morphs and follows interactive drag distance. The default
`TrayMotionTheme.family()` defines distinct Motor profiles for route,
geometry, effects, and interactive settling. Opening and dismissal use the
same route profile in opposite directions. Keyboard-driven changes follow
the OS-reported inset directly, without a second spring. The transition
keeps the same container-transform vocabulary as Flutter's `OpenContainer`,
with a fading barrier, changing corner radius, and surface elevation. Fullscreen
is still the same tray surface, so it transforms in place instead of pushing a
second route.

The tray recalculates its target from the current content size, keeps outgoing
and incoming pages alive for the transition, and dismisses after a downward
fling. A downward gesture can start from the top drag area of the surface; on
an internal page it pops that page first, and on the root page it dismisses the
route. Back navigation follows the same rule. Load data before calling
`showTray` when the final compact height is known; otherwise an intrinsic page
is measured and the tray animates from its initial safe size to the content
size. Bounded pages start from the configured expanded fraction and keep their
viewport stable while their own scrollable loads content.
Inactive pages remain mounted for state preservation but do not overwrite the
active page's content measurement; switching pages reports the new size again.

For state restoration, use a stable page ID and codec-compatible arguments,
provide a page restorer to the controller, and insert the route with Flutter's
`Navigator.restorablePush`:

```dart
@pragma('vm:entry-point')
Route<void> buildWalletTray(BuildContext context, Object? arguments) {
  TrayPage<dynamic> restorePage(String id, Object? pageArguments) {
    return walletPageFor(id, pageArguments);
  }

  return TrayRoute<void>(
    trayController: TrayController(
      initialPage: restorePage('wallets', arguments),
      pageRestorer: restorePage,
    ),
    geometryResolver: const DefaultTrayGeometryResolver(),
    motionTheme: TrayMotionTheme.family(),
    barrierColor: const Color(0x52000000),
    barrierDismissible: true,
    restorationId: 'wallet-tray',
  );
}

Navigator.of(context).restorablePush(
  buildWalletTray,
  arguments: <String, Object?>{'accountId': 'primary'},
);
```

Each page pushed into this controller must set `restorationId` and
`restorationArguments`. Widget builders are recreated by `restorePage`; they
are not serialized. Scroll-position handoff between related pages remains a
future slice.

Run the interactive example from this package with:

```bash
cd example
flutter run
```
