import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('restores the internal page stack after a restart', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        restorationScopeId: 'app',
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).restorablePush<void>(_buildRestorableTray);
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    _restorableController!.push<void>(_restorablePage('details', 'wallet'));
    await tester.pumpAndSettle();
    expect(find.text('details:wallet'), findsOneWidget);

    await tester.restartAndRestore();
    await tester.pumpAndSettle();

    expect(_restorableController!.currentPage.restorationId, 'details');
    expect(_restorableController!.currentPage.restorationArguments, 'wallet');
    expect(find.text('details:wallet'), findsOneWidget);
  });
}

TrayController? _restorableController;

@pragma('vm:entry-point')
Route<void> _buildRestorableTray(BuildContext context, Object? arguments) {
  final controller = TrayController(
    initialPage: _restorablePage('root', null),
    pageRestorer: _restorablePage,
  );
  return TrayRoute<void>(
    trayController: controller,
    geometryResolver: const DefaultTrayGeometryResolver(),
    motionTheme: TrayMotionTheme.family(),
    barrierColor: Colors.black54,
    barrierDismissible: true,
    restorationId: 'stack',
  );
}

TrayPage<dynamic> _restorablePage(String id, Object? arguments) {
  switch (id) {
    case 'root':
      return TrayPage<void>(
        restorationId: id,
        restorationArguments: arguments,
        builder:
            (_) => Builder(
              builder: (context) {
                _restorableController = context.tray;
                return const Text('root');
              },
            ),
      );
    case 'details':
      return TrayPage<void>(
        restorationId: id,
        restorationArguments: arguments,
        builder: (_) => Text('details:$arguments'),
      );
    default:
      throw ArgumentError.value(id, 'id', 'Unknown test tray page.');
  }
}
