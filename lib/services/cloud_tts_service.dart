import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Server-side Google Cloud TTS (Firebase callable) for when the device/browser
/// has no matching local voice pack.
class CloudTtsService {
  CloudTtsService._();

  static final Map<String, Uint8List> _memoryCache = {};
  static const int _maxCacheEntries = 48;

  static final AudioPlayer _player = AudioPlayer();

  static String _cacheKey(String text, String bcp47) {
    final b = utf8.encode('$bcp47|$text');
    return sha256.convert(b).toString();
  }

  static Future<Uint8List?> synthesize(String text, String bcp47) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final lang = bcp47.trim().replaceAll('_', '-');
    if (lang.isEmpty) return null;

    final key = _cacheKey(t, lang);
    final hit = _memoryCache[key];
    if (hit != null) return hit;

    if (FirebaseAuth.instance.currentUser == null) {
      debugPrint('[CloudTts] skip — not signed in');
      return null;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('synthesizeSpeech');
      final res = await callable.call<Map<String, dynamic>>({
        'text': t,
        'bcp47': lang,
      });
      final data = res.data;
      final b64 = data['audioBase64'] as String?;
      if (b64 == null || b64.isEmpty) return null;
      final bytes = base64Decode(b64);
      if (bytes.isEmpty) return null;
      _memoryCache[key] = bytes;
      while (_memoryCache.length > _maxCacheEntries) {
        _memoryCache.remove(_memoryCache.keys.first);
      }
      return bytes;
    } catch (e, st) {
      debugPrint('[CloudTts] synthesize failed: $e\n$st');
      return null;
    }
  }

  /// Plays MP3 [bytes]; completes when playback ends or on error.
  static Future<void> playMp3(Uint8List bytes) async {
    if (bytes.isEmpty) return;
    final done = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _player.stop();
      await _player.play(BytesSource(bytes));
      await done.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {},
      );
    } catch (e) {
      debugPrint('[CloudTts] play failed: $e');
    } finally {
      await sub.cancel();
    }
  }
}
