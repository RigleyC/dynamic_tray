# Dynamic Tray restoration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a restorable tray route and its internal page stack from serializable page descriptors.

**Architecture:** `TrayPage` carries optional restoration metadata. `TrayController` validates and serializes its entries, while `_TraySurfaceState` owns the Flutter `RestorationMixin` and applies restored descriptors through a caller-provided page factory. The route remains compatible with existing `showTray` callers and is restorable only when inserted through Flutter's restorable navigation API.

**Tech Stack:** Flutter 3.47 restoration APIs, Dart `RestorableValue`, `StandardMessageCodec`-compatible primitives, existing `Motor` motion layer.

**Spec:** `docs/superpowers/specs/2026-09-18-dynamic-tray-restoration-design.md`

## Global Constraints

- Preserve the existing non-restorable `showTray` API.
- Do not serialize widget builders or arbitrary Dart objects.
- Use behavioral tests only; do not add golden or visual tests.
- Keep the implementation package-local and avoid a nested Navigator.

---

### Task 1: Add restorable page contracts

**Files:**
- Modify: `lib/src/tray_page.dart`
- Modify: `lib/src/tray_controller.dart`
- Test: `test/tray_controller_test.dart`

**Interfaces:**
- `TrayPage` exposes `restorationId` and `restorationArguments`.
- `TrayPageRestorer` has signature `TrayPage<dynamic> Function(String, Object?)`.
- `TrayController` accepts an optional `TrayPageRestorer`, exposes a serializable
  snapshot, and can replace its stack from restored descriptors.

- [x] **Step 1: Write behavioral tests** for valid descriptors, rejected pages
  without IDs on a restorable controller, and rebuilding a stack through the
  page restorer.
- [x] **Step 2: Run the focused controller test and verify the new tests fail.**
- [x] **Step 3: Implement metadata, validation, snapshot encoding, and restore.**
- [x] **Step 4: Run `rtk flutter test test/tray_controller_test.dart`.**

### Task 2: Persist the surface stack with Flutter restoration

**Files:**
- Modify: `lib/src/tray_surface.dart`
- Create: `lib/src/tray_restoration.dart`
- Test: `test/tray_restoration_test.dart`

**Interfaces:**
- `TraySurface` receives an optional restoration ID and page restorer.
- A custom `RestorableValue<List<Object?>>` stores controller snapshots.

- [x] **Step 1: Write a restart-and-restore widget test** with a restorable
  `MaterialApp`, a restorable route, and a two-page tray stack.
- [x] **Step 2: Run the focused test and verify restoration fails.**
- [x] **Step 3: Register the restorable snapshot and synchronize it whenever the
  controller changes.**
- [x] **Step 4: Run the focused restoration test and verify the page ID and stack
  are restored.**

### Task 3: Wire restoration through `TrayRoute`

**Files:**
- Modify: `lib/src/tray_route.dart`
- Modify: `lib/src/tray_surface.dart`
- Modify: `lib/dynamic_tray.dart`
- Test: `test/tray_back_navigation_test.dart`

**Interfaces:**
- `TrayRoute` accepts an optional `restorationId` and passes it to
  `TraySurface`; the page restorer belongs to the controller because it is
  also needed by `push` validation and stack reconstruction.
- Existing route construction remains source-compatible through optional named
  parameters.

- [x] **Step 1: Add a route-level test that the restoration configuration reaches
  the surface without changing ordinary back behavior.**
- [x] **Step 2: Implement the optional route wiring and public export.**
- [x] **Step 3: Run route and restoration tests together.**

### Task 4: Document the supported restorable composition

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/plans/2026-09-18-dynamic-tray.md`

- [x] **Step 1: Add a concise static `Navigator.restorablePush` example showing
  serializable page IDs and arguments.**
- [x] **Step 2: Mark restoration as implemented while keeping scroll-position
  handoff as the remaining future slice.**
- [x] **Step 3: Run `rtk dart format lib test example/lib`, `rtk flutter analyze`,
  `rtk flutter analyze` from `example`, and the full `rtk flutter test`.**
