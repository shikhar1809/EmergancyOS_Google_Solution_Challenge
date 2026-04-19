// iOS / Android / desktop (IO) — speech recognition + TTS for SOS voice QA and comms.
// Web uses speech_web.dart via conditional import.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

final SpeechToText _stt = SpeechToText();
final FlutterTts _tts = FlutterTts();

bool _sttInited = false;
bool _ttsInited = false;
bool _listenSession = false;
VoidCallback? _pendingListenEnd;

/// Invalidates in-flight TTS completion when [cancelSpeechText] or a new utterance starts.
Object? _ttsSpeakToken;

bool speechSupported() => true;

Future<bool> _ensureStt() async {
  if (_sttInited) return _stt.isAvailable;
  _sttInited = true;
  final ok = await _stt.initialize(
    onError: (e) => debugPrint('[speech_io] stt ${e.errorMsg}'),
    onStatus: (status) {
      if (!_listenSession || _pendingListenEnd == null) return;
      if (status == SpeechToText.doneStatus ||
          status == SpeechToText.notListeningStatus) {
        final done = _pendingListenEnd!;
        _pendingListenEnd = null;
        _listenSession = false;
        done();
      }
    },
  );
  return ok;
}

Future<void> _ensureTts() async {
  if (_ttsInited) return;
  _ttsInited = true;
  try {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSharedInstance(true);
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playAndRecord,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        IosTextToSpeechAudioCategoryOptions.duckOthers,
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
      ],
      IosTextToSpeechAudioMode.voicePrompt,
    );
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.45);
  } catch (e) {
    debugPrint('[speech_io] tts init: $e');
  }
}

/// speech_to_text expects e.g. en_IN; we get BCP-47 from the app (en-IN).
String? _localeIdForListen(String bcp47) {
  final t = bcp47.trim();
  if (t.isEmpty) return null;
  final parts = t.replaceAll('_', '-').split('-');
  if (parts.length >= 2) {
    return '${parts[0]}_${parts[1].toUpperCase()}';
  }
  return '${parts[0]}_${parts[0].toUpperCase()}';
}

/// Prefer a locale the engine actually has (en_IN missing on many devices → fall back to en_US).
Future<String?> _pickLocaleId(String languageCode) async {
  final ok = await _ensureStt();
  if (!ok || !_stt.isAvailable) return null;
  try {
    final available = await _stt.locales();
    if (available.isEmpty) return null;

    final preferred = _localeIdForListen(
      languageCode.trim().isEmpty ? 'en-IN' : languageCode,
    );
    if (preferred != null &&
        available.any((l) => l.localeId.toLowerCase() == preferred.toLowerCase())) {
      return preferred;
    }
    final lang = (languageCode.trim().isEmpty ? 'en' : languageCode)
        .replaceAll('_', '-')
        .split('-')
        .first
        .toLowerCase();
    for (final l in available) {
      if (l.localeId.toLowerCase().startsWith(lang)) return l.localeId;
    }
  } catch (e) {
    debugPrint('[speech_io] locale pick: $e');
  }
  return null;
}

void startListening(
  String languageCode,
  void Function(String) onResult,
  void Function() onEnd,
  void Function(String) onError,
  void Function() onSoundDetected,
) {
  unawaited(_startListeningAsync(
    languageCode,
    onResult,
    onEnd,
    onError,
    onSoundDetected,
  ));
}

Future<void> _startListeningAsync(
  String languageCode,
  void Function(String) onResult,
  void Function() onEnd,
  void Function(String) onError,
  void Function() onSoundDetected,
) async {
  final ok = await _ensureStt();
  if (!ok || !_stt.isAvailable) {
    onError('not_available');
    onEnd();
    return;
  }

  try {
    if (_stt.isListening) {
      await _stt.stop();
    }
  } catch (e) {
    debugPrint('[speech_io] pre-listen stop: $e');
  }
  await Future<void>.delayed(const Duration(milliseconds: 120));

  _listenSession = true;
  _pendingListenEnd = onEnd;

  try {
    final localeId = await _pickLocaleId(languageCode);
    debugPrint('[speech_io] listen localeId=$localeId');
    await _stt.listen(
      onResult: (res) {
        if (res.recognizedWords.isNotEmpty) {
          onResult(res.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 8),
      localeId: localeId,
      onSoundLevelChange: (level) {
        if (level > 0.03) onSoundDetected();
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        // Short yes/no matches confirmation tuning better than dictation on Android.
        listenMode: ListenMode.confirmation,
      ),
    );
  } catch (e) {
    _listenSession = false;
    _pendingListenEnd = null;
    onError('$e');
    onEnd();
  }
}

void stopListening() {
  if (!_sttInited) return;
  unawaited(() async {
    try {
      await _stt.stop();
    } catch (e) {
      debugPrint('[speech_io] stop: $e');
    }
    _listenSession = false;
    final cb = _pendingListenEnd;
    _pendingListenEnd = null;
    cb?.call();
  }());
}

void speakText(String text, {String lang = 'en-IN', void Function()? onDone}) {
  unawaited(_speakAsync(text, lang, onDone));
}

bool _truthyLangAvailable(dynamic v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Prefer [preferredBcp47]; if the engine reports it unavailable, fall back to English so TTS is not silent.
Future<String> _effectiveTtsLanguage(String preferredBcp47) async {
  final primary = preferredBcp47.trim().replaceAll('_', '-');
  if (primary.isEmpty) return 'en-IN';
  try {
    final a = await _tts.isLanguageAvailable(primary);
    if (_truthyLangAvailable(a)) return primary;
  } catch (e) {
    debugPrint('[speech_io] isLanguageAvailable("$primary"): $e');
  }
  final legacy = primary.contains('-')
      ? '${primary.split('-').first}_${primary.split('-')[1].toUpperCase()}'
      : primary;
  if (legacy != primary) {
    try {
      final a = await _tts.isLanguageAvailable(legacy);
      if (_truthyLangAvailable(a)) return legacy;
    } catch (_) {}
  }
  for (final fb in <String>['en-IN', 'en_US', 'en-US']) {
    try {
      final a = await _tts.isLanguageAvailable(fb);
      if (_truthyLangAvailable(a)) return fb.replaceAll('_', '-');
    } catch (_) {}
  }
  return 'en-IN';
}

Future<void> _speakAsync(String text, String lang, void Function()? onDone) async {
  final cleaned = text.trim();
  if (cleaned.isEmpty) {
    onDone?.call();
    return;
  }
  await _ensureTts();
  final token = Object();
  _ttsSpeakToken = token;
  var completed = false;
  void tryDone() {
    if (completed || _ttsSpeakToken != token) return;
    completed = true;
    _ttsSpeakToken = null;
    onDone?.call();
  }

  try {
    _tts.setCompletionHandler(() => tryDone());
    await _tts.stop();
    final langTag = await _effectiveTtsLanguage(lang.replaceAll('_', '-'));
    if (langTag.replaceAll('_', '-') != lang.replaceAll('_', '-')) {
      debugPrint('[speech_io] TTS language fallback: $lang -> $langTag');
    }
    await _tts.setLanguage(langTag);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.45);
    await _tts.speak(cleaned);
    // Completion handler is authoritative; fallback if platform returns early.
    tryDone();
  } catch (e) {
    debugPrint('[speech_io] speak: $e');
    tryDone();
  }
}

void cancelSpeechText() {
  _ttsSpeakToken = Object();
  unawaited(() async {
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _stt.stop();
    } catch (_) {}
    _listenSession = false;
    _pendingListenEnd = null;
  }());
}

void primeSpeechAudioContext() {}

/// True when [FlutterTts] reports the BCP-47 language as available (no English fallback).
Future<bool> nativeVoiceAvailable(String bcp47) async {
  await _ensureTts();
  final primary = bcp47.trim().replaceAll('_', '-');
  if (primary.isEmpty) return true;
  try {
    final a = await _tts.isLanguageAvailable(primary);
    if (_truthyLangAvailable(a)) return true;
  } catch (e) {
    debugPrint('[speech_io] isLanguageAvailable("$primary"): $e');
  }
  if (primary.contains('-')) {
    final legacy =
        '${primary.split('-').first}_${primary.split('-')[1].toUpperCase()}';
    if (legacy != primary) {
      try {
        final a = await _tts.isLanguageAvailable(legacy);
        if (_truthyLangAvailable(a)) return true;
      } catch (_) {}
    }
  }
  return false;
}

void bankUserGestureForWeb() {}
