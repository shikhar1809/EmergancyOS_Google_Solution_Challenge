import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../../services/voice_comms_service.dart';

/// Compact globe icon that opens a menu of supported app languages.
class LanguageSwitcherButton extends ConsumerWidget {
  const LanguageSwitcherButton({super.key, this.tooltip});

  final String? tooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(localeProvider);
    return PopupMenuButton<Locale>(
      tooltip: tooltip ?? l10n.get('language_picker_title'),
      icon: const Icon(Icons.language_rounded),
      initialValue: current,
      onSelected: (loc) async {
        await ref.read(localeProvider.notifier).setLocale(loc);
        VoiceCommsService.clearSpeakQueue();
      },
      itemBuilder: (context) => [
        for (final loc in kSupportedLocales)
          PopupMenuItem<Locale>(
            value: loc,
            child: Text(kLocaleLabels[loc.languageCode] ?? loc.languageCode),
          ),
      ],
    );
  }
}
