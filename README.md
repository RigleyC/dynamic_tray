# dynamic_tray

A Flutter tray inspired by Expo Dynamic Tray: one modal session that adapts to
its content and changes views in place. Open it directly from a `BuildContext`;
inside the route, use `context.tray` to change views or close the session.

## Quick start

Open a tray from any button. The returned future completes with the optional
result when the session closes. No root widget or manually-created controller
is required:

```dart
final result = await context.openTray<String>(
  builder: (_) => const WalletDetailsPage(),
  footer: (context) => SizedBox(
    height: 65,
    child: FilledButton(
      onPressed: () => context.tray.setView(
        viewId: 'choose-category',
        builder: (_) => const ChooseCategoryPage(),
      ),
      child: const Text('Change category'),
    ),
  ),
);
```

Change views inside the same tray surface, go back, or close with a result:

```dart
context.tray.setView(
  viewId: 'choose-category',
  builder: (_) => const ChooseCategoryPage(),
);

context.tray.goBack();
context.tray.close('saved');
```

The common path does not require a manually-created controller, view IDs,
layout/presentation flags, or animation configuration. Intrinsic content sizes
the tray automatically; when it exceeds 72% of the available height, the tray
morphs to fullscreen for that page visit, avoiding threshold oscillation when
fullscreen width changes text wrapping. A `ListView` or `CustomScrollView` at the page root needs
the optional `layout: TrayPageLayout.bounded`, which provides a finite viewport
for scrolling. Add `viewId` only when a view should be reused after revisiting
it. A footer is optional and occupies the reference's fixed 65 px slot.

## Motion and behavior goals

The implementation target is the Expo reference behavior, not merely matching
its spring constants:

- One tray session and one surface while switching views; visited views stay
  mounted for that session and are released when it closes.
- One visual coordinator composes independent Motor controllers for bounds,
  presentation, backdrop, page crossfade, and drag. Retargeting one channel
  does not restart another, and each action keeps the reference's own profile.
- Drag begins from the handle, uses the reference distance/velocity thresholds,
  and returns with gesture velocity when it is cancelled.
- Tray geometry follows live keyboard inset updates and adds the reference
  45-point lift above its safe-area gap. Keyboard timing still needs device
  verification.
- Default sizing, footer reservation, safe areas, and view transitions follow
  the Expo tray. Flutter-specific restoration and shared elements remain
  optional; fullscreen is reached by explicit presentation or tall intrinsic
  content, and returning from a stacked fullscreen page morphs to its prior view.

These are code-level behavior targets, not a claim of verified visual parity.
Confirm the experience on-device for opening, closing,
content resizing, both directions of view changes, drag/cancel, keyboard, and
Android back before calling the port complete.

## Optional widgets

`TrayHeader` is a neutral layout helper: the caller supplies each widget, so the
package does not impose app typography, colors, or icon choices.

```dart
TrayHeader(
  leading: const AccountAvatar(),
  title: const Text('Choose account'),
  subtitle: const Text('Select where to transfer from.'),
  trailing: const Text('Done'),
)
```

The Expo sample's trigger, handle, and action buttons are useful interaction
patterns, but their app-specific styling should not become mandatory package
configuration. A trigger convenience widget may be added later; opening through
`context.openTray` remains the basic API.

## Example

Run the interactive example from this package with `cd example` and
`flutter run`.
