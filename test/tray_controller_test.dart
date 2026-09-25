import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:dynamic_tray/dynamic_tray.dart';

void main() {
  TrayPage<T> page<T>(String label) {
    return TrayPage<T>(builder: (_) => Text(label));
  }

  test('push returns a future completed by pop', () async {
    final controller = TrayController(initialPage: page('root'));

    final resultFuture = controller.push<String>(page('child'));

    expect(controller.canPop, isTrue);

    controller.pop('selected');

    expect(await resultFuture, 'selected');
    expect(controller.canPop, isFalse);
  });

  test('pop on the root dismisses the tray without a navigator', () {
    final controller = TrayController(initialPage: page('root'));

    expect(controller.pop(), isTrue);
    expect(controller.canPop, isFalse);
  });

  test('presentation helpers update the current presentation', () {
    final controller = TrayController(initialPage: page('root'));

    controller.expand();
    expect(controller.presentation, TrayPresentation.expanded);

    controller.fullscreen();
    expect(controller.presentation, TrayPresentation.fullscreen);

    controller.collapse();
    expect(controller.presentation, TrayPresentation.content);
  });

  test('push and pop expose an outgoing/incoming page transition', () {
    final root = page<void>('root');
    final child = page<void>('child');
    final controller = TrayController(initialPage: root);

    controller.push<void>(child);

    final pushTransition = controller.transition;
    expect(pushTransition, isNotNull);
    expect(pushTransition!.outgoing, same(root));
    expect(pushTransition.incoming, same(child));
    expect(pushTransition.isPush, isTrue);

    controller.completePageTransition(pushTransition.id);
    expect(controller.transition, isNull);

    controller.pop<void>();

    final popTransition = controller.transition;
    expect(popTransition, isNotNull);
    expect(popTransition!.outgoing, same(child));
    expect(popTransition.incoming, same(root));
    expect(popTransition.isPush, isFalse);
  });

  test('serializes and restores a page stack through stable IDs', () {
    TrayPage<dynamic> restorePage(String id, Object? arguments) {
      return TrayPage<dynamic>(
        restorationId: id,
        restorationArguments: arguments,
        builder: (_) => Text('$id:$arguments'),
      );
    }

    final controller = TrayController(
      initialPage: restorePage('root', 1),
      pageRestorer: restorePage,
    );
    controller.push<void>(restorePage('child', <String, Object?>{'id': 2}));
    controller.fullscreen();

    expect(controller.restorationSnapshot, [
      {'id': 'root', 'arguments': 1, 'presentation': 'content'},
      {
        'id': 'child',
        'arguments': <String, Object?>{'id': 2},
        'presentation': 'fullscreen',
      },
    ]);

    controller.restoreFromSnapshot([
      {'id': 'root', 'arguments': 10, 'presentation': 'content'},
      {'id': 'details', 'arguments': 'wallet', 'presentation': 'fullscreen'},
    ]);

    expect(controller.pages, hasLength(2));
    expect(controller.currentPage.restorationId, 'details');
    expect(controller.currentPage.restorationArguments, 'wallet');
    expect(controller.presentation, TrayPresentation.fullscreen);
  });

  test('requires restoration IDs when a page restorer is configured', () {
    final root = TrayPage<void>(builder: (_) => const SizedBox.shrink());

    expect(
      () => TrayController(initialPage: root, pageRestorer: (_, _) => root),
      throwsArgumentError,
    );
  });
}
