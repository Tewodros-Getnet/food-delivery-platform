import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/locale_provider.dart';

/// A settings tile that lets the user toggle between English and Amharic.
/// Drop this anywhere in a settings or profile screen.
class LanguageSwitcherTile extends ConsumerWidget {
  const LanguageSwitcherTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final isAmharic = locale.languageCode == 'am';

    return ListTile(
      leading: const Icon(Icons.language),
      title: const Text('Language / ቋንቋ'),
      subtitle: Text(isAmharic ? 'አማርኛ' : 'English'),
      trailing: Switch(
        value: isAmharic,
        onChanged: (val) {
          ref
              .read(localeProvider.notifier)
              .setLocale(Locale(val ? 'am' : 'en'));
        },
      ),
    );
  }
}
