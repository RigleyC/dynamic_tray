# Dynamic Tray package design

## Goal

Create a standalone Flutter package under `Desktop/projetos/dynamic_tray` that models a
tray as one modal surface with an internal page stack and a geometry target
driven by `motor`.

## Decisions

- `TrayRoute` owns only Navigator integration, barrier behavior, and lifecycle.
- `TrayController` owns the internal stack and presentation state.
- `TrayPage<T>` is the public navigation unit; it contains a builder and its
  default presentation.
- `TrayGeometry` is the render state. Height is derived from measured content,
  not stored as page configuration.
- `DefaultTrayGeometryResolver` maps content, expanded, and fullscreen states
  to bounds and border radius.
- Non-fullscreen trays default to 8 logical pixels of left, right, and bottom
  margin. Their maximum height reserves the top safe area, the bottom system
  inset (or keyboard inset), and the bottom margin. Fullscreen remains
  edge-to-edge, shortened only for an open keyboard.
- `TraySurface` is the only initial renderer and uses `MotionBuilder<TrayGeometry>`
  with a package-owned converter so bounds and corner radius share one Motor
  target.
- No nested Flutter `Navigator`, `PageView`, provider dependency, or duplicate
  route is introduced in this first slice.

## First-slice boundaries

The first slice includes route presentation, push/pop futures, presentation
commands, content measurement, vertical scrolling when content exceeds the
surface, and unit tests for controller and geometry behavior. It does not yet
include drag-to-dismiss, outgoing/incoming page choreography, shared-element
morphing, restoration, or visual golden tests.

## Verification

Run `dart format`, `flutter analyze`, and the focused unit tests. Tests assert
controller results and geometry values; they do not validate visual behavior.

## Second slice implemented

- `TrayController` exposes an internal outgoing/incoming page transition with a
  monotonic id so a renderer can safely clear only its own transition.
- `TraySurface` keeps both pages alive during a push/pop and uses Motor's
  scalar motion for opacity and horizontal offset.
- The surface accepts downward drags in non-fullscreen states, clamps the drag
  to positive displacement, settles back with Motor, or dismisses after a
  distance/velocity threshold.
- The route completes pending page futures when dismissed by back navigation or
  the barrier.

This slice still does not include shared-element morphing, restoration, or
scroll-position handoff between pages.

## Third slice implemented

- Bounds and corner radius now animate as one `TrayGeometry` target, avoiding a
  radius jump during content, expanded, and fullscreen transitions.
- Route back navigation pops the internal tray stack when a previous page is
  available; only the root page closes the route.
- The package includes an `example/` app that exercises the public route,
  presentation, stack, and dismiss APIs manually.
- Stack pages remain mounted in `Offstage` layers so StatefulWidget state and
  page-local scroll storage survive internal push/pop transitions.
- Only the current page is allowed to publish content measurement. When the
  current page changes, its measurement observer is re-enabled and reports
  once even if its render size did not change, preventing stale geometry after
  push/pop.

The current package still has no device-level visual verification; automated
coverage intentionally checks route/controller results and geometry contracts.

## Fourth slice implemented

- `TraySharedElement` pairs one tag between outgoing and incoming internal
  pages and animates the incoming visual through a Motor `RectMotionConverter`.
- Unmatched tags use the existing page fade/slide transition automatically.
- The page transition reset now protects Motor's completion callback while
  moving its controller back to zero, so transitions are not cleared before
  their forward animation starts.
- The example demonstrates a wallet avatar morph on push and pop.

Shared-element flights are intentionally visual-only: they do not transfer
state, pointer ownership, restoration, or cross-route elements.

## Fifth slice implemented

- The scroll contract is covered by a behavioral widget test with content
  taller than the resolved tray bounds.
- The existing surface drag recognizer does not prevent the page's
  `SingleChildScrollView` from moving upward through its content.
