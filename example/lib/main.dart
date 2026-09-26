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
      builder: (_) => const TrayExampleContent(child: WalletDetailsView()),
      viewId: 'wallet-details',
      footer:
          (context) => SizedBox(
            height: 64,
            width: double.infinity,
            child: TrayExampleContent(
              child: FilledButton(
                onPressed:
                    () => context.tray.setView(
                      builder:
                          (_) => const TrayExampleContent(
                            child: ChooseCategoryView(),
                          ),
                      viewId: 'choose-category',
                    ),
                child: const Text('Change category'),
              ),
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

/// Styles the Material example's content locally without making the package
/// depend on Material widgets or a particular app theme.
class TrayExampleContent extends StatelessWidget {
  const TrayExampleContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final theme = parentTheme.copyWith(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ).copyWith(onSurface: Colors.white),
      textTheme: parentTheme.textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );

    return Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!,
          child: IconTheme(
            data: const IconThemeData(color: Colors.white),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ExampleTrayHeader extends StatelessWidget {
  const ExampleTrayHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onLeadingPressed,
    this.leadingTooltip = 'Back',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onLeadingPressed;
  final String leadingTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leading =
        onLeadingPressed == null
            ? Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                icon,
                size: 27,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            )
            : SizedBox(
              width: 48,
              height: 48,
              child: IconButton(
                onPressed: onLeadingPressed,
                tooltip: leadingTooltip,
                icon: Icon(icon, size: 26),
              ),
            );

    return TrayHeader(
      leading: leading,
      spacing: 14,
      title: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
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
        ExampleTrayHeader(
          icon: Icons.close_rounded,
          title: 'Wallet details',
          subtitle: 'One surface, adapting to each view.',
          onLeadingPressed: () => context.tray.close(),
          leadingTooltip: 'Close tray',
        ),
        const SizedBox(height: 16),
        const Text('The optional footer stays part of this tray session.'),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Keyboard check',
            hintText: 'Focus me to check the tray position',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed:
              () => context.tray.setView(
                builder:
                    (_) =>
                        const TrayExampleContent(child: ChooseCategoryView()),
                viewId: 'choose-category',
              ),
          child: const Text('Choose category'),
        ),
        OutlinedButton(
          onPressed:
              () => context.tray.setView(
                builder: (_) => const TrayExampleContent(child: LongListView()),
                viewId: 'long-list',
                layout: TrayPageLayout.bounded,
              ),
          child: const Text('Open long list'),
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
        ExampleTrayHeader(
          icon: Icons.arrow_back_rounded,
          title: 'Choose category',
          subtitle: 'Back returns to wallet details.',
          onLeadingPressed: context.tray.goBack,
        ),
        const SizedBox(height: 16),
        for (final category in const ['Food', 'Transport', 'Home'])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => context.tray.close(category),
              icon: const Icon(Icons.chevron_right),
              label: Text(category),
            ),
          ),
        TextButton(
          onPressed: context.tray.goBack,
          child: const Text('Back to details'),
        ),
      ],
    );
  }
}

class LongListView extends StatelessWidget {
  const LongListView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: 36,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ExampleTrayHeader(
              icon: Icons.list_alt_rounded,
              title: 'Long scrolling view',
              subtitle: 'Scroll the rows, then drag the handle to close.',
              onLeadingPressed: context.tray.goBack,
            ),
          );
        }
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text('$index')),
          title: Text('Scrollable row $index'),
          subtitle: const Text('Scroll this list, then pull the tray handle.'),
          onTap:
              () => context.tray.setView(
                builder:
                    (_) => const TrayExampleContent(child: WalletDetailsView()),
                viewId: 'wallet-details',
              ),
        );
      },
    );
  }
}
