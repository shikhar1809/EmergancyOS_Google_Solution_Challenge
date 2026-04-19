import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/locale_provider.dart';
import '../../../../services/voice_comms_service.dart';

/// Windows-style tray strip: language, connectivity, mic, volume, uptime, clock.
///
/// When [dockTray] is true, renders only the compact tray row (no full-width bar
/// chrome) for placement on the right inside the ops taskbar dock.
class OpsDashboardStatusBar extends ConsumerStatefulWidget {
  const OpsDashboardStatusBar({
    super.key,
    required this.sessionStartedAt,
    this.dockTray = false,
  });

  final DateTime sessionStartedAt;
  final bool dockTray;

  @override
  ConsumerState<OpsDashboardStatusBar> createState() => _OpsDashboardStatusBarState();
}

class _OpsDashboardStatusBarState extends ConsumerState<OpsDashboardStatusBar> {
  Timer? _ticker;
  DateTime _now = DateTime.now();
  List<ConnectivityResult> _connectivity = const [ConnectivityResult.none];
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshConnectivity());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      if (mounted) {
        setState(() => _now = DateTime.now());
        if (_tick % 5 == 0) unawaited(_refreshConnectivity());
      }
    });
  }

  Future<void> _refreshConnectivity() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _connectivity = r);
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  IconData _networkIcon() {
    if (_connectivity.contains(ConnectivityResult.none)) {
      return Icons.wifi_off_rounded;
    }
    if (_connectivity.contains(ConnectivityResult.wifi)) {
      return Icons.wifi_rounded;
    }
    if (_connectivity.contains(ConnectivityResult.ethernet)) {
      return Icons.lan_rounded;
    }
    if (_connectivity.contains(ConnectivityResult.mobile)) {
      return Icons.signal_cellular_alt_rounded;
    }
    return Icons.wifi_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appLocale = ref.watch(localeProvider);
    final localeTag = appLocale.countryCode != null && appLocale.countryCode!.isNotEmpty
        ? '${appLocale.languageCode}_${appLocale.countryCode}'
        : appLocale.languageCode;
    final timeFmt = DateFormat.Hm(localeTag);
    final dateFmt = DateFormat.yMd(localeTag);
    final uptime = _now.difference(widget.sessionStartedAt);
    final uptimeLabel =
        l10n.get('ops_tray_uptime').replaceAll('{time}', _formatUptime(uptime));

    final tray = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<Locale>(
          tooltip: l10n.get('language_picker_title'),
          padding: EdgeInsets.zero,
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                appLocale.languageCode.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 56),
                child: Text(
                  kLocaleLabels[appLocale.languageCode] ?? appLocale.languageCode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 7,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Icon(_networkIcon(), color: Colors.white70, size: 18),
        const SizedBox(width: 12),
        const Icon(Icons.mic_rounded, color: Colors.white70, size: 18),
        const SizedBox(width: 12),
        const Icon(Icons.volume_up_rounded, color: Colors.white70, size: 18),
        const SizedBox(width: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              timeFmt.format(_now),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              dateFmt.format(_now),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Text(
          uptimeLabel,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );

    if (widget.dockTray) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: tray,
      );
    }

    return Material(
      color: const Color(0xFF1A1A1A),
      child: Container(
        height: 36,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [tray],
        ),
      ),
    );
  }
}
