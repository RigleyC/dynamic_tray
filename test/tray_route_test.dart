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

  testWidgets('pushes into the tray that is already open', (tester) async {
    late BuildContext homeContext;
    late Future<String?> rootTray;
    var rootCompleted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );

    rootTray = homeContext.openTray<String>(
      builder: (_) => const _ReopenRootPage(),
    );
    rootTray.then((_) => rootCompleted = true).ignore();
    await tester.pumpAndSettle();
    expect(find.text('Root'), findsOneWidget);

    // A context outside the tray asks for content. It joins the open tray
    // instead of being ignored, and the first future stays pending.
    final pushedPage = homeContext.openTray<String>(
      builder: (_) => const _PopChildPage(),
    );
    await tester.pumpAndSettle();

    // The page joined the tray that was already open: same session, the same
    // controller, and the first future still pending.
    expect(identical(_childPageController, _reopenController), isTrue);
    expect(find.text('Child'), findsOneWidget);
    expect(rootCompleted, isFalse);

    await tester.tap(find.text('Child'));
    await tester.pumpAndSettle();

    expect(await pushedPage, 'child');
    expect(find.text('Child'), findsNothing);
    expect(find.text('Root'), findsOneWidget);
    expect(rootCompleted, isFalse);
  });

  testWidgets('reuses the page bound to a repeated viewId', (tester) async {
    late BuildContext homeContext;
    var rootBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );

    homeContext
        .openTray<String>(
          viewId: 'root',
          builder: (_) {
            rootBuilds++;
            return const _PushChildPage();
          },
        )
        .ignore();
    await tester.pumpAndSettle();
    expect(rootBuilds, 1);

    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(find.text('Child'), findsOneWidget);

    // The same viewId from outside must reuse the visited page instead of
    // throwing and instead of stacking a second one.
    homeContext
        .openTray<String>(
          viewId: 'root',
          builder: (_) {
            rootBuilds++;
            return const _PushChildPage();
          },
        )
        .ignore();
    await tester.pumpAndSettle();

    expect(rootBuilds, 1);
    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Child'), findsNothing);
  });

  testWidgets('reports the tray through maybeTray only inside one', (
    tester,
  ) async {
    late BuildContext homeContext;
    _probeTray = null;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('Home'));
          },
        ),
      ),
    );

    expect(homeContext.maybeTray, isNull);

    homeContext.openTray<void>(builder: (_) => const _ScopeProbe()).ignore();
    await tester.pumpAndSettle();

    expect(_probeTray, isNotNull);
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
TrayController? _childPageController;
TrayController? _probeTray;

/// Reads the tray from a page's own build context, which sits under the scope.
class _ScopeProbe extends StatelessWidget {
  const _ScopeProbe();

  @override
  Widget build(BuildContext context) {
    _probeTray = context.maybeTray;
    return const Text('Probe');
  }
}

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

/// Root page that pushes another page inside the same tray.
class _PushChildPage extends StatelessWidget {
  const _PushChildPage();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('Root'),
      GestureDetector(
        onTap: () => context.tray.push<void>(
          TrayPage(builder: (_) => const _ReopenChildPage()),
        ),
        child: const Text('Push'),
      ),
    ],
  );
}

/// Page that returns a result when tapped.
class _PopChildPage extends StatelessWidget {
  const _PopChildPage();

  @override
  Widget build(BuildContext context) {
    _childPageController = context.tray;
    return GestureDetector(
      onTap: () => context.tray.pop<String>('child'),
      child: const Text('Child'),
    );
  }
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
  TrayGeometry resolve(TrayLayoutContext context, Size contentSize) {
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
