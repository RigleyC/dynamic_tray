import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const DynamicTrayExampleApp());
}

class DynamicTrayExampleApp extends StatelessWidget {
  const DynamicTrayExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  Future<void> _openTray(BuildContext context) async {
    final result = await showTray<String>(
      context: context,
      page: TrayPage(builder: (_) => const TrayActionsPage()),
      footer: const ExampleTrayFooter(),
    );
    if (!context.mounted || result == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Tray result: $result')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Tray example')),
      body: Center(
        child: FilledButton(
          onPressed: () => _openTray(context),
          child: const Text('Open tray'),
        ),
      ),
    );
  }
}

class TrayActionsPage extends StatelessWidget {
  const TrayActionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tray = context.tray;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrayHeader(
            leading: TraySharedElement(
              tag: 'wallet-avatar',
              flightBuilder: _walletAvatarFlight,
              child: const CircleAvatar(
                radius: 28,
                child: Icon(Icons.account_balance_wallet),
              ),
            ),
            title: Text(
              'Surface navigation',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: const Text('A neutral header built from caller widgets.'),
          ),
          const Text('Try changing the presentation or opening another page.'),
          FilledButton(onPressed: tray.expand, child: const Text('Expand')),
          FilledButton(
            onPressed: tray.fullscreen,
            child: const Text('Fullscreen'),
          ),
          OutlinedButton(
            onPressed:
                () => tray.push<String>(
                  TrayPage(builder: (_) => const ConfirmationPage()),
                ),
            child: const Text('Push page'),
          ),
          TextButton(
            onPressed: () => tray.dismiss('dismissed'),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }
}

class ExampleTrayFooter extends StatelessWidget {
  const ExampleTrayFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: FilledButton(
          onPressed:
              () => context.tray.push<String>(
                TrayPage(builder: (_) => const ConfirmationPage()),
              ),
          child: const Text('Continue from persistent footer'),
        ),
      ),
    );
  }
}

class ConfirmationPage extends StatelessWidget {
  const ConfirmationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TraySharedElement(
            tag: 'wallet-avatar',
            flightBuilder: _walletAvatarFlight,
            child: const CircleAvatar(
              radius: 52,
              child: Icon(Icons.account_balance_wallet, size: 36),
            ),
          ),
          Text('Confirmation', style: Theme.of(context).textTheme.titleLarge),
          const Text('Back pops this page before closing the tray.'),
          FilledButton(
            onPressed: () => context.tray.pop('confirmed'),
            child: const Text('Return result'),
          ),
        ],
      ),
    );
  }
}

Widget _walletAvatarFlight(BuildContext context, Widget child) {
  return Material(type: MaterialType.transparency, child: child);
}
