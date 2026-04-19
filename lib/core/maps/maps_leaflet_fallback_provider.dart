import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Legacy key could stay `true` across sessions (timeouts, old defaults). We
/// no longer read it so installs get a fresh Google-first attempt.
const _kPrefKeyLegacy = 'eos_maps_leaflet_fallback';
const _kPrefKey = 'eos_maps_leaflet_fallback_v2';

Future<void> _clearLegacyLeafletPrefs(SharedPreferences prefs) async {
  await prefs.remove(_kPrefKeyLegacy);
}

/// When true, [EosHybridMap] uses OpenStreetMap via flutter_map after a Google
/// failure (quota, auth, load timeout) or explicit toggle. Default is Google Maps.
class MapsLeafletFallbackNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  var _hydrated = false;

  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    final prefs = await SharedPreferences.getInstance();
    await _clearLegacyLeafletPrefs(prefs);
    if (prefs.containsKey(_kPrefKey)) {
      final v = prefs.getBool(_kPrefKey) ?? false;
      if (v) state = true;
      return;
    }
    // First launch after key bump: do not resurrect stale OSM lock from v1.
    await prefs.setBool(_kPrefKey, false);
  }

  void activateLeaflet(String reason) {
    if (state) return;
    state = true;
    SharedPreferences.getInstance().then((prefs) async {
      await _clearLegacyLeafletPrefs(prefs);
      await prefs.setBool(_kPrefKey, true);
    });
    debugPrint('[MapsFallback] Switching to OSM/Leaflet tiles: $reason');
  }

  /// Explicit preference (e.g. master clears auto-fallback when console maps = Google).
  void setLeafletExplicit(bool useLeaflet, {required String reason}) {
    state = useLeaflet;
    SharedPreferences.getInstance().then((prefs) async {
      await _clearLegacyLeafletPrefs(prefs);
      if (useLeaflet) {
        await prefs.setBool(_kPrefKey, true);
      } else {
        await prefs.remove(_kPrefKey);
      }
    });
    debugPrint(
      useLeaflet
          ? '[MapsFallback] Explicit OSM/Leaflet: $reason'
          : '[MapsFallback] Cleared OSM preference: $reason',
    );
  }

  /// Force Google Maps mode for the admin console - clears any stored Leaflet preference.
  void forceGoogleMaps({required String reason}) {
    state = false;
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.remove(_kPrefKey);
      await _clearLegacyLeafletPrefs(prefs);
    });
    debugPrint('[MapsFallback] Force Google Maps for admin: $reason');
  }
}

final mapsLeafletFallbackProvider =
    NotifierProvider<MapsLeafletFallbackNotifier, bool>(MapsLeafletFallbackNotifier.new);
