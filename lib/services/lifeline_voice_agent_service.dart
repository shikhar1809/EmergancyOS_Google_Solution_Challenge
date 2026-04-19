import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:emergency_os/features/ai_assist/data/lifeline_curriculum_digest.dart';
import 'package:emergency_os/core/utils/speech_web.dart'
    if (dart.library.io) 'package:emergency_os/core/utils/speech_io.dart';

/// Push-to-talk lifecycle for the Lifeline voice assistant.
///
/// UX contract:
/// - Long-press the mic: STT starts (listening).
/// - Release the press: STT stops, transcript is sent to Gemini, reply is
///   spoken back (thinking -> speaking).
/// - Short tap while speaking: cancels the TTS reply.
/// - Short tap while listening: drops the capture without sending.
/// - Screen dispose (`detachOverlay`): cancels STT and TTS.
enum LifelineVoiceState { idle, listening, thinking, speaking }

typedef LifelineVoiceCallback = void Function(LifelineVoiceState state);
/// Fired once per reply, right before TTS: [spoken] is what will be read aloud;
/// [openLibraryLevelId] is a curriculum id when the model links a library topic (may be null).
typedef LifelineVoiceReplyCallback = void Function(
  String spoken,
  int? openLibraryLevelId,
);
typedef LifelineMicErrorCallback = void Function(String code);

class LifelineVoiceAgentService {
  LifelineVoiceAgentService._();
  static final LifelineVoiceAgentService instance =
      LifelineVoiceAgentService._();

  /// STT always listens with Indian English — Chrome's `en-IN` recognizer
  /// reliably handles Hinglish mixing and an Indian accent. Gemini then
  /// replies in whichever language the user actually spoke.
  static const String _sttLocale = 'en-IN';

  /// Matches any Devanagari codepoint. Used to switch TTS to `hi-IN` when
  /// Gemini replies in Hindi.
  static final RegExp _devanagari = RegExp(r'[\u0900-\u097F]');

  LifelineVoiceState _state = LifelineVoiceState.idle;
  LifelineVoiceCallback? _onStateChanged;
  LifelineVoiceReplyCallback? _onVoiceReply;
  LifelineMicErrorCallback? _onMicError;

  final List<Map<String, String>> _history = [];

  bool _isListening = false;
  bool _aborted = false;
  String _lastRecognizedText = '';

  LifelineVoiceState get state => _state;

  void setOnStateChanged(LifelineVoiceCallback? cb) {
    _onStateChanged = cb;
  }

  void setOnVoiceReply(LifelineVoiceReplyCallback? cb) {
    _onVoiceReply = cb;
  }

  void setOnMicError(LifelineMicErrorCallback? cb) {
    _onMicError = cb;
  }

  void _setState(LifelineVoiceState next) {
    if (_state == next) return;
    _state = next;
    _onStateChanged?.call(next);
  }

  /// Long-press started on the mic bubble.
  void beginHold() {
    if (_isListening) return;
    // Any prior TTS must be silenced so the user can start talking immediately.
    cancelSpeechText();
    _aborted = false;
    _lastRecognizedText = '';
    _isListening = true;
    _setState(LifelineVoiceState.listening);

    startListening(
      _sttLocale,
      (text) {
        _lastRecognizedText = text;
      },
      _handleListenEnd,
      (error) {
        debugPrint('[LifelineVoice] STT error: $error');
        _isListening = false;
        _aborted = true;
        _onMicError?.call(error);
        _setState(LifelineVoiceState.idle);
      },
      () {/* sound detected — no UI change needed */},
    );
  }

  /// Long-press released on the mic bubble.
  void endHold() {
    if (!_isListening) return;
    stopListening();
    // The STT engine will invoke [_handleListenEnd] shortly; that's where
    // the transcript is actually dispatched to Gemini.
  }

  /// Short tap while the agent is listening — discard the capture.
  void abortListening() {
    if (!_isListening && _state != LifelineVoiceState.listening) return;
    _aborted = true;
    _isListening = false;
    stopListening();
    _setState(LifelineVoiceState.idle);
  }

  /// Short tap while the agent is speaking — stop the reply.
  void cancelSpeaking() {
    if (_state != LifelineVoiceState.speaking) return;
    cancelSpeechText();
    _setState(LifelineVoiceState.idle);
  }

  void _handleListenEnd() {
    _isListening = false;
    if (_aborted) {
      _aborted = false;
      return;
    }
    final text = _lastRecognizedText.trim();
    if (text.isEmpty) {
      _setState(LifelineVoiceState.idle);
      return;
    }
    unawaited(_processTranscript(text));
  }

  Future<void> _processTranscript(String text) async {
    _setState(LifelineVoiceState.thinking);
    try {
      final (spoken, levelId) = await _askGemini(text);
      if (spoken == null || spoken.isEmpty) {
        _setState(LifelineVoiceState.idle);
        return;
      }
      _onVoiceReply?.call(spoken, levelId);
      _setState(LifelineVoiceState.speaking);
      speakText(
        spoken,
        lang: _ttsLocaleFor(spoken),
        onDone: () {
          if (_state == LifelineVoiceState.speaking) {
            _setState(LifelineVoiceState.idle);
          }
        },
      );
    } catch (e) {
      debugPrint('[LifelineVoice] Gemini error: $e');
      _setState(LifelineVoiceState.idle);
    }
  }

  Future<(String?, int?)> _askGemini(String text) async {
    final callable = FirebaseFunctions.instance.httpsCallable('lifelineChat');
    final result = await callable.call(<String, dynamic>{
      'message': text,
      'history': _history,
      'scenario': 'Lifeline voice assistant',
      'trainingMode': true,
      'voiceAssistantMode': true,
      // Intentionally empty: server prompt then falls back to
      // "match the language of the user's message" (see functions/index.js).
      'replyLocale': '',
      'contextDigest': LifelineCurriculumDigest.build(),
      'analyticsMode': false,
    });

    final raw = result.data;
    final Map<String, dynamic> data =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    var reply = (data['text'] as String?)?.trim() ?? '';
    int? openId;
    final oid = data['openLibraryLevelId'];
    if (oid is int) {
      openId = oid;
    } else if (oid is num) {
      openId = oid.round();
    }

    // Older deployments may return the raw JSON string in `text`.
    if (reply.startsWith('{') && reply.contains('"spoken"')) {
      try {
        final m = jsonDecode(reply) as Map<String, dynamic>?;
        if (m != null && m['spoken'] is String) {
          reply = (m['spoken'] as String).trim();
          final o = m['openLibraryLevelId'];
          if (o is int) {
            openId = o;
          } else if (o is num) {
            openId = o.round();
          }
        }
      } catch (_) {}
    }

    if (reply.isEmpty) return (null, null);

    _history.add({'role': 'user', 'text': text});
    _history.add({'role': 'model', 'text': reply});
    while (_history.length > 12) {
      _history.removeAt(0);
    }

    return (reply, openId);
  }

  String _ttsLocaleFor(String text) =>
      _devanagari.hasMatch(text) ? 'hi-IN' : 'en-IN';

  /// Called when the Lifeline screen is disposed. Cancels everything and
  /// drops the callback set.
  void detachOverlay() {
    _aborted = true;
    _isListening = false;
    stopListening();
    cancelSpeechText();
    _history.clear();
    _state = LifelineVoiceState.idle;
    _onStateChanged = null;
    _onVoiceReply = null;
    _onMicError = null;
  }
}
