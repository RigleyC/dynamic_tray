# Dynamic Tray shared-element design

## Goal

Allow two pages inside the same tray to animate a matching visual element
between their local bounds during an internal push or pop, while preserving the
existing page transition as the fallback.

## Scope

- Shared elements participate only in internal `TrayController.push` and
  `TrayController.pop` transitions.
- Route presentation changes, route opening, route dismissal, and unmatched
  elements keep their current behavior.
- A match is identified by an `Object` tag. At most one element per tag is
  supported on each page.
- The flight uses the incoming element's widget as its visual shuttle. The
  package does not attempt to transfer state or pointer ownership between the
  two page subtrees.
- A page may provide `flightBuilder` for a lightweight, non-interactive visual
  representation of the shuttle.

## Public API

```dart
TraySharedElement(
  tag: 'wallet-avatar',
  flightBuilder: (context, child) => DecoratedBox(
    decoration: const BoxDecoration(shape: BoxShape.circle),
    child: child,
  ),
  child: const CircleAvatar(),
)
```

`TraySharedElement` renders its `child` normally outside a tray and inside the
tray when no matching transition is active. During a matching transition, the
source and destination copies are hidden and the shuttle is painted above the
page layers.

## Architecture

`TraySurface` owns one internal `TraySharedElementRegistry`. Each page layer is
wrapped in a page-scoped inherited registry. A `TraySharedElement` reports its
surface-local `Rect` after layout. The registry pairs the outgoing and
incoming records using the transition's page identities and tag.

The surface renders one `TraySharedElementFlight` for each pair. Its target is
an ordinary `Rect` and uses Motor's `RectMotionConverter` with the existing
effects motion. The overlay is removed when `TrayController` clears the page
transition. If either record is missing, the ordinary fade/slide page
transition remains visible and no overlay is created.

## Safety rules

- Duplicate tags on one page are ignored after the first record.
- Registrations are removed when a marker is detached.
- Rect callbacks are ignored when the marker or surface is detached.
- The flight shuttle is visual-only; interactive behavior remains owned by the
  page layers.
- No new dependency, nested `Navigator`, Hero controller, screenshot, or
  visual/golden test is introduced.

## Verification

Behavioral widget tests cover normal rendering, matching push/pop flights,
unmatched fallback, and registration cleanup. `flutter analyze`, `flutter
test`, and the example analyzer remain required. Device-level visual smoothness
is not claimed by these tests.
