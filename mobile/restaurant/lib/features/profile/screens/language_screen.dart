import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../language_provider.dart';

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocale = ref.watch(languageProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.language),
        elevation: 0,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.selectLanguage,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          RadioListTile<String>(
            title: const Text('English'),
            subtitle: const Text('English language'),
            value: 'en',
            groupValue: currentLocale.languageCode,
            onChanged: (value) {
              if (value != null && value != currentLocale.languageCode) {
                ref.read(languageProvider.notifier).setLanguage(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.success),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          RadioListTile<String>(
            title: const Text('አማርኛ'),
            subtitle: const Text('Amharic language / አማርኛ ቋንቋ'),
            value: 'am',
            groupValue: currentLocale.languageCode,
            onChanged: (value) {
              if (value != null && value != currentLocale.languageCode) {
                ref.read(languageProvider.notifier).setLanguage(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.success),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Language Information',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Language Code: ${currentLocale.languageCode}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Is Amharic: ${currentLocale.languageCode == 'am' ? 'Yes (አዎ)' : 'No'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}