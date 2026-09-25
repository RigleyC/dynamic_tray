import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scrolls content that is taller than the tray', (tester) async {
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
                      layout: TrayPageLayout.bounded,
                      builder: (_) => const _LongTrayPage(),
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

    final scrollable = find.byType(Scrollable);
    final scrollState = tester.state<ScrollableState>(scrollable);
    expect(scrollState.position.pixels, 0);

    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(scrollState.position.pixels, greaterThan(0));

    _scrollController!.dismiss('done');
    await tester.pumpAndSettle();
    expect(await openedTray, 'done');
  });
}

TrayController? _scrollController;

class _LongTrayPage extends StatelessWidget {
  const _LongTrayPage();

  @override
  Widget build(BuildContext context) {
    _scrollController = context.tray;
    return ListView.builder(
      itemCount: 40,
      itemBuilder: (context, index) {
        return Container(
          height: 48,
          color: index.isEven ? Colors.indigo : Colors.indigoAccent,
          alignment: Alignment.center,
          child: Text('$index'),
        );
      },
    );
  }
}
