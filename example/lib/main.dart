import 'dart:async';

import 'package:dynamic_tray/dynamic_tray.dart';
import 'package:flutter/material.dart';

void main() {
  // Resolves the device corner radii over a platform channel. Doing it before
  // the first frame keeps the tray's opening animation free of rebuilds.
  unawaited(warmUpTrayDeviceCorners());
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
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
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
      viewId: 'wallet-details',
      footer:
          (context) => SizedBox(
            height: 64,
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  () => context.tray.setView(
                    builder: (_) => const ChooseCategoryView(),
                    viewId: 'choose-category',
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

  Future<void> _openSharedTray(BuildContext context) {
    return context.openTray<String>(
      builder: (_) => const SharedElementRootView(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dynamic Tray')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => _openTray(context),
              child: const Text('Open details'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => _openSharedTray(context),
              child: const Text('Open shared element flow'),
            ),
          ],
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
                        const ChooseCategoryView(),
                viewId: 'choose-category',
              ),
          child: const Text('Choose category'),
        ),
        OutlinedButton(
          onPressed:
              () => context.tray.setView(
                builder: (_) => const LongListView(),
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

/// Root of the shared element flow. Its counter is the shared element: it keeps
/// running while it flies to the details page.
class SharedElementRootView extends StatelessWidget {
  const SharedElementRootView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleTrayHeader(
          icon: Icons.close_rounded,
          title: 'Shared element',
          subtitle: 'The counter keeps running while it moves.',
          onLeadingPressed: () => context.tray.close(),
          leadingTooltip: 'Close tray',
        ),
        const SizedBox(height: 16),
        const Center(
          child: TraySharedElement(tag: 'counter', child: LiveCounter()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.tray.setView(
            builder: (_) => const SharedElementDetailsView(),
            viewId: 'shared-details',
          ),
          child: const Text('Open details'),
        ),
      ],
    );
  }
}

/// Taller destination page with a text field. The counter lands in the
/// reserved target above the field.
class SharedElementDetailsView extends StatelessWidget {
  const SharedElementDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleTrayHeader(
          icon: Icons.arrow_back_rounded,
          title: 'Details',
          subtitle: 'The same counter, still counting.',
          onLeadingPressed: context.tray.goBack,
        ),
        const SizedBox(height: 16),
        const Center(
          child: TraySharedElement.target(tag: 'counter', width: 160, height: 56),
        ),
        const SizedBox(height: 16),
        const TextField(
          decoration: InputDecoration(
            labelText: 'Notes',
            hintText: 'Type while the counter runs',
          ),
        ),
        const SizedBox(height: 12),
        for (var line = 1; line <= 4; line++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Detail line $line'),
          ),
        TextButton(
          onPressed: () => context.tray.pop('saved'),
          child: const Text('Save and go back'),
        ),
      ],
    );
  }
}

/// A counter that ticks every quarter second. Its State is what the shared
/// element must keep across the transition.
class LiveCounter extends StatefulWidget {
  const LiveCounter({super.key});

  @override
  State<LiveCounter> createState() => _LiveCounterState();
}

class _LiveCounterState extends State<LiveCounter> {
  Timer? _timer;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      setState(() => _count++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 160,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        'Count $_count',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
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
                    (_) => const WalletDetailsView(),
                viewId: 'wallet-details',
              ),
        );
      },
    );
  }
}
