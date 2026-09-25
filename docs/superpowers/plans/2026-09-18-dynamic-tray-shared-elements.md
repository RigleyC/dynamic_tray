# Dynamic Tray Shared Elements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional tag-matched shared-element flights to internal tray page transitions.

**Architecture:** `TraySurface` owns a registry keyed by page identity and tag. Page-scoped `TraySharedElement` markers report surface-local rectangles after layout, while a top overlay renders matching incoming widgets through Motor's `RectMotionConverter`. Missing matches fall back to the existing fade/slide choreography.

**Tech Stack:** Flutter 3.47+, Dart 3.13+, `motor: ^1.1.0`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-18-dynamic-tray-shared-elements-design.md`

## Global Constraints

- Keep the package dependency surface to Flutter plus `motor`.
- Do not add visual/golden tests.
- Support only one marker per tag on each page; ignore later duplicates.
- Keep interactive ownership in the page layers; the flight shuttle is visual-only.
- Do not introduce a nested Navigator, Hero controller, screenshot capture, or restoration behavior in this slice.

---

### Task 1: Shared-element public marker and registry

**Files:**
- Create: `lib/src/tray_shared_element.dart`
- Modify: `lib/dynamic_tray.dart`
- Test: `test/tray_shared_element_test.dart`

**Interfaces:**
- Produces `TraySharedElement({required Object tag, required Widget child, TraySharedElementFlightBuilder? flightBuilder})`.
- Produces an internal registry that stores `{page, tag, rect, child, flightBuilder}` and exposes matching/visibility queries to the surface.

- [x] **Step 1: Write the failing widget test**

Add a public-API test that renders `TraySharedElement` outside a tray and inside
a tray page, asserting the supplied child remains present and the marker does
not require a special ancestor for normal rendering.

- [x] **Step 2: Run the focused test and verify it fails**

Run `flutter test test/tray_shared_element_test.dart` from the package root.
Expected: compilation fails because `TraySharedElement` is not exported yet.

- [x] **Step 3: Implement the marker contract**

Create:

```dart
typedef TraySharedElementFlightBuilder = Widget Function(
  BuildContext context,
  Widget child,
);

class TraySharedElement extends StatelessWidget {
  const TraySharedElement({
    super.key,
    required this.tag,
    required this.child,
    this.flightBuilder,
  });

  final Object tag;
  final Widget child;
  final TraySharedElementFlightBuilder? flightBuilder;
}
```

Keep the marker's ordinary build path equal to `child` until a page-scoped
registry is supplied by `TraySurface`.

- [x] **Step 4: Add registry behavior and pass the focused test**

Implement the internal registry with page identity, first-registration-wins
semantics, removal by marker identity, and a `isFlying(page, tag)` query. Add
the export to `lib/dynamic_tray.dart`, then run the focused test again.

- [x] **Step 5: Format and analyze the task**

Run `dart format lib test` and `flutter analyze`. Expected: no analyzer issues.

### Task 2: Register page-scoped marker bounds

**Files:**
- Modify: `lib/src/tray_shared_element.dart`
- Modify: `lib/src/tray_surface.dart`
- Test: `test/tray_shared_element_test.dart`

**Interfaces:**
- Consumes `TrayPage<dynamic>` identities and `TrayPageTransition` from the
  existing controller.
- Produces page-local registry records with a `Rect` and marker widget.

- [x] **Step 1: Add a failing registration test**

Create a root page that contains a marker, pushes a child page with the same
tag, and give the marker a `flightBuilder` returning a child with
`const ValueKey<String>('avatar-flight')`. Assert `find.byKey` finds that
shuttle while the transition is active. Keep assertions behavioral: verify the
match exists, not its pixel position.

- [x] **Step 2: Implement the page scope and render-object reporter**

Add an internal inherited scope carrying the registry, current page identity,
and a callback that converts a marker's global bounds into surface-local
coordinates. The marker should use a render-object reporter that schedules one
post-frame registration after layout and removes its record on detach.

- [x] **Step 3: Wrap the existing page layers**

Give `TraySurface` a stable `GlobalKey` for its local coordinate space. Wrap
each page layer with the page-scoped registry before the existing
`TraySizeObserver`, preserving the current keyed `Offstage` structure.

- [x] **Step 4: Complete the focused registration test**

Run `flutter test test/tray_shared_element_test.dart`; expected: the matching
tag is observed during push and disappears after the transition is cleared.

### Task 3: Render Motor-backed flights with fallback

**Files:**
- Modify: `lib/src/tray_shared_element.dart`
- Modify: `lib/src/tray_surface.dart`
- Modify: `test/tray_shared_element_test.dart`

**Interfaces:**
- Consumes registry matches and `TrayMotionTheme.effects`.
- Produces a `TraySharedElementFlight` keyed by transition id and tag.

- [x] **Step 1: Add matching and unmatched behavior tests**

Assert that a matching pair produces one shuttle built by `flightBuilder`, an
unmatched tag produces no shuttle, and a pop uses the same matching mechanism
in reverse. Do not assert animation frames or exact visual geometry.

- [x] **Step 2: Implement the flight widget**

Render the incoming child in a `MotionBuilder<Rect>` using
`const RectMotionConverter()` and `widget.motionTheme.effects`. Position the
shuttle with `Positioned.fromRect`; use a `ValueKey` containing the transition
id and tag so a new push/pop restarts the flight.

- [x] **Step 3: Hide only matched source/destination markers**

Make the page-scoped marker consult `registry.isFlying(page, tag)` and return
an `Opacity(opacity: 0, child: child)` while its flight exists. Leave all
unmatched markers and the existing page layers unchanged.

- [x] **Step 4: Remove flights with the existing transition lifecycle**

Render flights only while `controller.transition` is non-null. Let the current
`completePageTransition` callback remove them after the page motion completes;
do not add a second transition lifecycle to the controller.

- [x] **Step 5: Run the focused tests**

Run `flutter test test/tray_shared_element_test.dart`; expected: all matching,
fallback, pop, and cleanup assertions pass.

### Task 4: Example, documentation, and full verification

**Files:**
- Modify: `example/lib/main.dart`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-18-dynamic-tray-design.md`
- Modify: `docs/superpowers/plans/2026-09-18-dynamic-tray.md`

- [x] **Step 1: Add a small example flow**

Use a stable tag around the example wallet icon/title on the root and pushed
pages, and use `flightBuilder` only for a visual decoration. Keep the example
usable when no shared element is declared.

- [x] **Step 2: Document the public contract and limitation**

Explain tag matching, the optional flight builder, unmatched fallback, and the
fact that shuttle state/pointer ownership stays with the page layers.

- [x] **Step 3: Run the complete verification**

Run `dart format lib test example/lib`, `flutter analyze`, `flutter test`, and
`flutter analyze` from `example`. Expected: no formatting/analyzer issues and
all behavioral tests pass. No visual/device success claim is made.
