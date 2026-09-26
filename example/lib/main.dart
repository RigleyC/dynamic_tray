import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DynamicTrayExampleApp());

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
    final result = await context.openTray<String>(
      builder: (_) => const WalletDetailsView(),
      footer:
          (context) => SizedBox(
            height: 65,
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  () => context.tray.setView(
                    builder: (_) => const ChooseCategoryView(),
                  ),
              child: const Text('Change category'),
            ),
          ),
    );

    if (!context.mounted || result == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Tray result: $result')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Tray')),
      body: Center(
        child: FilledButton(
          onPressed: () => _openTray(context),
          child: const Text('Open details'),
        ),
      ),
    );
  }
}

class WalletDetailsView extends StatelessWidget {
  const WalletDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TrayHeader(
          leading: CircleAvatar(
            child: Icon(Icons.account_balance_wallet_outlined),
          ),
          title: Text('Wallet details'),
          subtitle: Text('One modal session, adapting to its content.'),
        ),
        const SizedBox(height: 16),
        const Text('The optional footer stays part of this tray session.'),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed:
              () => context.tray.setView(
                builder: (_) => const ChooseCategoryView(),
              ),
          child: const Text('Choose category'),
        ),
        TextButton(
          onPressed: () => context.tray.close('cancelled'),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class ChooseCategoryView extends StatelessWidget {
  const ChooseCategoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TrayHeader(
          title: Text('Choose category'),
          subtitle: Text(
            'This replaces the view without opening another modal.',
          ),
        ),
        const SizedBox(height: 16),
        for (final category in const ['Food', 'Transport', 'Home'])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(category),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.tray.close(category),
          ),
        TextButton(
          onPressed: context.tray.goBack,
          child: const Text('Back to details'),
        ),
      ],
    );
  }
}
