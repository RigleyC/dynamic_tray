import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens a tray and returns a result through its scope', (
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
                    page: TrayPage(builder: (_) => const _AutoPopPage()),
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
    await tester.pumpAndSettle();

    expect(await openedTray, 'done');
  });

  testWidgets('keeps a page state mounted across an internal push and pop', (
    tester,
  ) async {
    _statefulRootInstances = 0;
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
                    page: TrayPage(builder: (_) => const _StatefulRootPage()),
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
    await tester.pumpAndSettle();

    expect(await openedTray, 'done');
    expect(_statefulRootInstances, 1);
  });

  testWidgets('refreshes geometry measurement when the current page changes', (
    tester,
  ) async {
    final resolver = _RecordingGeometryResolver();
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
                    geometryResolver: resolver,
                    page: TrayPage(
                      builder: (_) => const _MeasurementRootPage(),
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
    await tester.pumpAndSettle();

    expect(resolver.heights, contains(40));
    expect(resolver.heights, contains(120));

    _measurementController!.pop<void>();
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });

  testWidgets('can push a page again after popping it', (tester) async {
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
                    page: TrayPage(builder: (_) => const _ReopenRootPage()),
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
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);

    _reopenController!.push<void>(
      TrayPage(builder: (_) => const _ReopenChildPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsOneWidget);

    _reopenController!.pop<void>();
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);

    _reopenController!.push<void>(
      TrayPage(builder: (_) => const _ReopenChildPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsOneWidget);

    _reopenController!.dismiss('done');
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });

  testWidgets('dragging a child page pops it', (tester) async {
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
                    page: TrayPage(builder: (_) => const _ReopenRootPage()),
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
    await tester.pumpAndSettle();
    _reopenController!.push<void>(
      TrayPage(builder: (_) => const _ReopenChildPage()),
    );
    await tester.pumpAndSettle();

    final surface = tester.getRect(find.byType(Material).last);
    await tester.dragFrom(
      surface.topCenter + const Offset(0, 8),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();

    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Child'), findsNothing);

    _reopenController!.dismiss('done');
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });

  testWidgets('keeps the route mounted while dismissing', (tester) async {
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
                    page: TrayPage(builder: (_) => const _ReopenRootPage()),
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
    await tester.pumpAndSettle();

    _reopenController!.dismiss('done');
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('Root'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Root'), findsNothing);
    expect(await openedTray, 'done');
  });
}

var _statefulRootInstances = 0;

class _AutoPopPage extends StatefulWidget {
  const _AutoPopPage();

  @override
  State<_AutoPopPage> createState() => _AutoPopPageState();
}

class _AutoPopPageState extends State<_AutoPopPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.tray.pop('done');
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _MeasurementRootPage extends StatefulWidget {
  const _MeasurementRootPage();

  @override
  State<_MeasurementRootPage> createState() => _MeasurementRootPageState();
}

class _MeasurementRootPageState extends State<_MeasurementRootPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.tray
          .push<void>(TrayPage(builder: (_) => const _MeasurementChildPage()))
          .then((_) {
            if (mounted) {
              context.tray.dismiss('done');
            }
          });
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 40);
}

TrayController? _measurementController;
TrayController? _reopenController;

class _ReopenRootPage extends StatelessWidget {
  const _ReopenRootPage();

  @override
  Widget build(BuildContext context) {
    _reopenController = context.tray;
    return const Text('Root');
  }
}

class _ReopenChildPage extends StatelessWidget {
  const _ReopenChildPage();

  @override
  Widget build(BuildContext context) => const Text('Child');
}

class _MeasurementChildPage extends StatelessWidget {
  const _MeasurementChildPage();

  @override
  Widget build(BuildContext context) {
    _measurementController = context.tray;
    return const SizedBox(height: 120);
  }
}

class _RecordingGeometryResolver implements TrayGeometryResolver {
  final List<double> heights = [];

  @override
  TrayGeometry resolve(
    TrayLayoutContext context,
    TrayPresentation presentation,
    Size contentSize,
  ) {
    heights.add(contentSize.height);
    return const TrayGeometry(
      rect: Rect.fromLTWH(0, 0, 320, 240),
      borderRadius: BorderRadius.zero,
    );
  }
}

class _StatefulRootPage extends StatefulWidget {
  const _StatefulRootPage();

  @override
  State<_StatefulRootPage> createState() => _StatefulRootPageState();
}

class _StatefulRootPageState extends State<_StatefulRootPage> {
  @override
  void initState() {
    super.initState();
    _statefulRootInstances++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.tray
          .push<void>(TrayPage(builder: (_) => const _AutoPopPage()))
          .then((_) {
            if (mounted) {
              context.tray.dismiss('done');
            }
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
