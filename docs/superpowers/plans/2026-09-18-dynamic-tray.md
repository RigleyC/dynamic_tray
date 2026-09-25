# Dynamic Tray Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first usable `dynamic_tray` Flutter package foundation.

**Architecture:** A `PopupRoute` presents one `TraySurface`. A `TrayController`
owns a small future-aware page stack and presentation state. The surface resolves
content-driven geometry and sends its `Rect` target through Motor's
`MotionBuilder`/`RectMotionConverter`.

**Tech Stack:** Flutter 3.32+, Dart 3.7+, `motor: ^1.1.0`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-18-dynamic-tray-design.md`

## Global Constraints

- Keep the package dependency surface to Flutter plus `motor`.
- Do not add visual/golden tests.
- Keep stack state separate from motion/rendering state.
- Prefer direct public components over private wrappers.

### Task 1: Package contracts and controller

**Files:**
- Create: `pubspec.yaml`
- Create: `lib/dynamic_tray.dart`
- Create: `lib/src/tray_page.dart`
- Create: `lib/src/tray_presentation.dart`
- Create: `lib/src/tray_controller.dart`
- Test: `test/tray_controller_test.dart`

- [x] Define `TrayPage<T>`, `TrayPresentation`, and the public export surface.
- [x] Implement `TrayController.push`, `pop`, `present`, convenience methods,
  and route dismissal with completers.
- [x] Test push/pop result delivery, root dismissal, and presentation changes.

### Task 2: Geometry and motion contracts

**Files:**
- Create: `lib/src/tray_geometry.dart`
- Create: `lib/src/tray_motion_theme.dart`
- Test: `test/tray_geometry_test.dart`

- [x] Implement content, expanded, and fullscreen geometry resolution.
- [x] Use the current `motor` 1.1 API for Cupertino motion presets.
- [x] Test bounds, clamping, safe-area/inset handling, and fullscreen radius.

### Task 3: Route, scope, surface, and measurement

**Files:**
- Create: `lib/src/tray_scope.dart`
- Create: `lib/src/tray_route.dart`
- Create: `lib/src/tray_surface.dart`
- Create: `README.md`

- [x] Add `showTray`, `TrayRoute`, and `TrayScope`/`BuildContext.tray`.
- [x] Render the current page in one surface with a scrollable measured body.
- [x] Animate target `TrayGeometry` changes with a Motor converter.
- [x] Document the supported API and explicit first-slice boundaries.

### Task 4: Focused verification

**Files:**
- Modify: package source only if analyzer exposes an integration mismatch.

- [x] Run `dart format` over package Dart files.
- [x] Run `flutter pub get`.
- [x] Run `flutter analyze`.
- [x] Run `flutter test` and confirm only behavioral/unit assertions are used.

### Task 5: Page choreography and drag settling

**Files:**
- Modify: `lib/src/tray_controller.dart`
- Modify: `lib/src/tray_surface.dart`
- Modify: `lib/src/tray_route.dart`
- Modify: `README.md`
- Modify: `test/tray_controller_test.dart`

- [x] Expose a guarded outgoing/incoming transition for push and pop.
- [x] Animate page opacity and offset with Motor's `SingleMotionBuilder`.
- [x] Add downward drag tracking with immediate touch response and Motor-based
  settle or dismissal.
- [x] Complete pending page futures when the route is dismissed externally.
- [x] Verify controller transition state with behavioral unit tests.

### Task 6: Geometry continuity and internal back navigation

**Files:**
- Modify: `lib/src/tray_geometry.dart`
- Modify: `lib/src/tray_surface.dart`
- Modify: `lib/src/tray_route.dart`
- Modify: `test/tray_geometry_test.dart`

- [x] Animate bounds and corner radius through one `TrayGeometry` converter.
- [x] Make route back navigation pop an internal page before dismissing the
  root route.

### Task 7: Interactive example

**Files:**
- Create: `example/pubspec.yaml`
- Create: `example/analysis_options.yaml`
- Create: `example/lib/main.dart`
- Modify: `README.md`

- [x] Provide a local path dependency example with Material 3.
- [x] Exercise expand, fullscreen, push/pop result, back navigation, and
  dismiss behavior through the public API.
- [x] Verify the package and example independently with `flutter analyze`.

### Task 8: Preserve internal page state

**Files:**
- Modify: `lib/src/tray_controller.dart`
- Modify: `lib/src/tray_surface.dart`
- Modify: `test/tray_route_test.dart`

- [x] Expose the internal page list to the renderer without exposing stack
  entries or completers.
- [x] Keep every page mounted in a stable keyed `Offstage` layer.
- [x] Preserve each page's scroll storage key while only the current page
  drives content measurement.
- [x] Verify a StatefulWidget is initialized once across push/pop.

### Task 9: Keep content measurement current

**Files:**
- Modify: `lib/src/tray_surface.dart`
- Modify: `test/tray_route_test.dart`

- [x] Disable measurement callbacks for mounted but inactive pages.
- [x] Force the newly active page to report its size when the stack changes,
  even when that page's render size is unchanged.
- [x] Verify geometry measurement across root → child → root page changes with
  a behavioral widget test.

### Task 10: Shared-element flights

The detailed implementation plan is
`docs/superpowers/plans/2026-09-18-dynamic-tray-shared-elements.md`.

- [x] Add the public `TraySharedElement` marker and optional flight builder.
- [x] Register page-local bounds and pair matching tags for push/pop.
- [x] Render Motor-backed `Rect` flights with unmatched fallback.
- [x] Demonstrate the flight in the example and verify behavior without
  visual/golden tests.

### Task 11: Verify scroll interaction

**Files:**
- Create: `test/tray_scroll_test.dart`

- [x] Verify a page taller than the resolved tray can scroll upward through
  the public route without visual/golden assertions.

### Task 12: Restoration

The detailed implementation plan is
`docs/superpowers/plans/2026-09-18-dynamic-tray-restoration.md`.

- [x] Add stable page IDs, serializable arguments, and a page restorer.
- [x] Persist and rebuild the internal page stack through Flutter restoration.
- [x] Verify a `Navigator.restorablePush` route after `restartAndRestore`.
- [x] Document the restorable route composition.
