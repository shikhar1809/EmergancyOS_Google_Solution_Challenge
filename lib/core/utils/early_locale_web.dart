import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Reads [SharedPreferences] string for `app_locale` from web localStorage
/// before async [SharedPreferences.getInstance] completes (same key as
/// `shared_preferences_web`: `flutter.app_locale`, JSON-encoded value).
String? readEarlyAppLocaleHint() {
  if (!kIsWeb) return null;
  try {
    final raw = web.window.localStorage.getItem('flutter.app_locale');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is String && decoded.isNotEmpty) return decoded;
  } catch (_) {}
  return null;
}
