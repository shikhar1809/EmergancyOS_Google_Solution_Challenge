import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

/// Browser global (`window` in the main thread) as a raw [JSObject].
///
/// Using [globalContext] is the canonical way to reach the JS global under
/// `dart:js_interop`. It avoids the Flutter web release build quirks we hit
/// with `extension type` + `@JS('window')` patterns (which could emit
/// `o.window.foo is not a function` even when `window.foo` was defined).
JSObject get _g => globalContext;

/// Attempt to call `window[name](args...)`, returning `true` on success.
///
/// Does **not** pre-check `typeof window[name] === 'function'` because
/// `getProperty` / `hasProperty` have proven flaky in release codegen; a
/// direct `callMethod` is both simpler and more reliable, and we catch the
/// native TypeError if the function really is missing.
bool _tryCall(String name, List<JSAny?> args) {
  try {
    switch (args.length) {
      case 0:
        _g.callMethod<JSAny?>(name.toJS);
        break;
      case 1:
        _g.callMethod<JSAny?>(name.toJS, args[0]);
        break;
      case 2:
        _g.callMethod<JSAny?>(name.toJS, args[0], args[1]);
        break;
      case 3:
        _g.callMethod<JSAny?>(name.toJS, args[0], args[1], args[2]);
        break;
      default:
        throw ArgumentError('too many args');
    }
    return true;
  } catch (e) {
    debugPrint('[speech_web] window.$name() failed: $e');
    return false;
  }
}

/// Whether the browser exposes a matching voice for [bcp47].
bool hasLocalVoiceFor(String bcp47) {
  try {
    final r = _g.callMethod<JSAny?>('eosHasVoiceFor'.toJS, bcp47.toJS);
    if (r == null) return false;
    return (r as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

Future<bool> nativeVoiceAvailable(String bcp47) async =>
    Future<bool>.value(hasLocalVoiceFor(bcp47));

void bankUserGestureForWeb() {
  _tryCall('bankUserGesture', const []);
}

bool speechSupported() => true;

void startListening(
  String languageCode,
  void Function(String) onResult,
  void Function() onEnd,
  void Function(String) onError,
  void Function() onSoundDetected,
) {
  unawaited(_startWebListeningAsync(
    languageCode,
    onResult,
    onEnd,
    onError,
    onSoundDetected,
  ));
}

Future<void> _startWebListeningAsync(
  String languageCode,
  void Function(String) onResult,
  void Function() onEnd,
  void Function(String) onError,
  void Function() onSoundDetected,
) async {
  cancelSpeechText();
  await Future<void>.delayed(const Duration(milliseconds: 140));
  try {
    _g['_speechOnResult'] = onResult.toJS;
    _g['_speechOnEnd'] = onEnd.toJS;
    _g['_speechOnError'] = onError.toJS;
    _g['_speechOnSound'] = onSoundDetected.toJS;
    final lang = (languageCode.isEmpty ? 'en-IN' : languageCode).toJS;

    if (_tryCall('eosInteropSttStart', [lang])) return;
    if (_tryCall('startSpeech', [lang])) return;

    onError('stt_js_missing');
    onEnd();
  } catch (e) {
    debugPrint('startListening FAILED: $e');
    onError(e.toString());
    onEnd();
  }
}

void stopListening() {
  if (_tryCall('eosInteropSttStop', const [])) return;
  _tryCall('stopSpeech', const []);
}

/// Core TTS: uses robust [eosSpeak] which handles AudioContext resume,
/// voice selection, and the self-healing watchdog timer internally.
void speakText(String text, {String lang = 'en-IN', void Function()? onDone}) {
  final args = onDone != null
      ? <JSAny?>[text.toJS, lang.toJS, onDone.toJS]
      : <JSAny?>[text.toJS, lang.toJS];

  if (_tryCall('eosSpeak', args)) return;

  try {
    _g.callMethod<JSAny?>(
      'resumeAudioForSpeech'.toJS,
      (() {
        if (!_tryCall('speakTextImpl', [text.toJS, lang.toJS])) {
          onDone?.call();
        }
      }).toJS,
    );
  } catch (_) {
    onDone?.call();
  }
}

void cancelSpeechText() {
  if (_tryCall('eosCancelSpeak', const [])) return;
  _tryCall('cancelSpeechText', const []);
}

/// Web autoplay policy: call from a user gesture before the first TTS.
void primeSpeechAudioContext() {
  if (_tryCall('eosPrimeAudio', const [])) return;
  _tryCall('resumeAudioForSpeech', [(() {}).toJS]);
  _tryCall('unlockWebSpeechSynthesis', const []);
}
