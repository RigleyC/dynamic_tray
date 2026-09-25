# Dynamic Tray restoration design

## Goal

Allow a restorable `TrayRoute` to recreate its internal page stack after the
Flutter restoration manager rebuilds the route.

## Contract

- `TrayPage` may declare a serializable `restorationId` and
  `restorationArguments`.
- A restorable tray receives a `TrayPageRestorer` that maps each saved page ID
  and argument object back to a new `TrayPage`.
- The route itself must be inserted with `Navigator.restorablePush` (or a
  named equivalent). A normal `Navigator.push` cannot restore an imperative
  route.
- The package stores only page descriptors, not widget builders or arbitrary
  Dart objects.
- A restorable tray rejects pages without a restoration ID when they are
  pushed or used as the initial page.
- Restoration is behavioral only; no golden or visual tests are added.

## State model

The tray surface owns a `RestorationMixin` with a single restorable list. Each
entry is encoded as a StandardMessageCodec-compatible map containing the page
ID, page arguments, and presentation. On restore, the list is passed to the
controller, which rebuilds the entries through the supplied page restorer.

The route's restoration scope is supplied by Flutter when the route is created
through `Navigator.restorablePush`; the surface uses a fixed child restoration
ID inside that route scope.

## Non-goals

- Making arbitrary `TrayPage.builder` closures serializable.
- Replacing `showTray` for existing non-restorable callers.
- Persisting transient animation progress or an in-flight shared-element flight.
