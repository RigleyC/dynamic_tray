import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motor/motor.dart';

void main() {
  testWidgets('shared element renders its child without a tray scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TraySharedElement(tag: 'wallet-avatar', child: Text('Wallet')),
        ),
      ),
    );

    expect(find.text('Wallet'), findsOneWidget);
  });

  testWidgets('matches tagged elements during an internal push', (
    tester,
  ) async {
    late Future<String?> openedTray;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  openedTray = showTray<String>(
                    context: context,
                    page: TrayPage(builder: (_) => const _SharedRootPage()),
                    motionTheme: TrayMotionTheme(
                      geometry: Motion.none(),
                      effects: Motion.linear(const Duration(seconds: 1)),
                      interactive: Motion.none(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byKey(const ValueKey<String>('avatar-flight')), findsOneWidget);

    _sharedController!.pop<void>();
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });

  testWidgets('falls back to the page transition for unmatched tags', (
    tester,
  ) async {
    late Future<String?> openedTray;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  openedTray = showTray<String>(
                    context: context,
                    page: TrayPage(
                      builder: (_) => const _SharedRootPage(matching: false),
                    ),
                    motionTheme: TrayMotionTheme(
                      geometry: Motion.none(),
                      effects: Motion.linear(const Duration(seconds: 1)),
                      interactive: Motion.none(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.byKey(const ValueKey<String>('avatar-flight')), findsNothing);

    _sharedController!.pop<void>();
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });

  testWidgets('matches tagged elements during an internal pop', (tester) async {
    late Future<String?> openedTray;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  openedTray = showTray<String>(
                    context: context,
                    page: TrayPage(
                      builder:
                          (_) => const _SharedRootPage(dismissAfterPop: false),
                    ),
                    motionTheme: TrayMotionTheme(
                      geometry: Motion.none(),
                      effects: Motion.linear(const Duration(seconds: 1)),
                      interactive: Motion.none(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byKey(const ValueKey<String>('avatar-flight')), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    _sharedController!.pop<void>();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      find.byKey(const ValueKey<String>('avatar-pop-flight')),
      findsOneWidget,
    );

    _sharedController!.dismiss('done');
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });
}

TrayController? _sharedController;

class _SharedRootPage extends StatefulWidget {
  const _SharedRootPage({this.matching = true, this.dismissAfterPop = true});

  final bool matching;
  final bool dismissAfterPop;

  @override
  State<_SharedRootPage> createState() => _SharedRootPageState();
}

class _SharedRootPageState extends State<_SharedRootPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _sharedController = context.tray;
      context.tray
          .push<void>(
            TrayPage(
              builder: (_) => _SharedChildPage(matching: widget.matching),
            ),
          )
          .then((_) {
            if (mounted && widget.dismissAfterPop) {
              context.tray.dismiss('done');
            }
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    return TraySharedElement(
      tag: widget.matching ? 'avatar' : 'root',
      flightBuilder: _buildRootAvatarFlight,
      child: const SizedBox(key: ValueKey<String>('avatar-root'), height: 24),
    );
  }
}

class _SharedChildPage extends StatelessWidget {
  const _SharedChildPage({required this.matching});

  final bool matching;

  @override
  Widget build(BuildContext context) {
    return TraySharedElement(
      tag: matching ? 'avatar' : 'child',
      flightBuilder: _buildAvatarFlight,
      child: const SizedBox(key: ValueKey<String>('avatar-child'), height: 72),
    );
  }
}

Widget _buildAvatarFlight(BuildContext context, Widget child) {
  return SizedBox(key: const ValueKey<String>('avatar-flight'), child: child);
}

Widget _buildRootAvatarFlight(BuildContext context, Widget child) {
  return SizedBox(
    key: const ValueKey<String>('avatar-pop-flight'),
    child: child,
  );
}
