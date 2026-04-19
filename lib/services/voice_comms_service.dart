import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/app_localizations.dart';
import '../core/utils/speech_web.dart'
    if (dart.library.io) '../core/utils/speech_io.dart';
import 'cloud_tts_service.dart';

/// In-app **voice**: device TTS (Web Speech API on web, [FlutterTts] on mobile/desktop).
///
/// Active SOS also calls `dispatchLifelineComms` so the LiveKit Lifeline agent can speak
/// the same lines in the emergency bridge room; this service remains the reliable on-device path.
class VoiceCommsService {
  VoiceCommsService._();

  static String _cachedLocale = 'en';
  static bool _localeLoaded = false;

  /// Web: opening TTS was started during the SOS navigation gesture; skip duplicate on active screen.
  static bool _sosOpeningPrimedForNavigation = false;

  /// When true, all TTS is suppressed (user chose Silence Mode on the voice gate).
  static bool silenceMode = false;

  static final List<_VoiceQueueItem> _queue = [];
  static Timer? _stuckTimer;
  static bool _draining = false;
  static int _drainGeneration = 0;

  /// Shown on SOS / volunteer when local + cloud TTS both fail (e.g. offline).
  static final ValueNotifier<String?> ttsStatusNotifier =
      ValueNotifier<String?>(null);

  /// Localized string for the current cached app locale (no [BuildContext]).
  static String tr(String key) => AppLocalizations.lookup(_cachedLocale, key);

  /// Latin-style sentence boundaries; text without these stays one segment (e.g. Hindi).
  static final RegExp _sentenceBoundary = RegExp(r'(?<=[.!?])\s+');

  static List<String> _splitSpeakSegments(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    final parts = t
        .split(_sentenceBoundary)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? <String>[t] : parts;
  }

  static const Map<String, Map<String, String>> _translations = {
    'hi': {
      'Your SOS is active now. Help will be arriving soon.':
          'आपका SOS अभी सक्रिय है। मदद जल्द ही पहुंचेगी।',
      'Are you conscious? Please answer yes or no.':
          'क्या आप होश में हैं? कृपया हाँ या ना में जवाब दें।',
      'Confirmed. You are conscious. We will check again in 60 seconds.':
          'पुष्टि हो गई। आप होश में हैं। हम 60 सेकंड में फिर जांच करेंगे।',
      'No response detected. Marked as unconscious for responders.':
          'कोई जवाब नहीं मिला। बचावकर्ताओं के लिए बेहोश चिह्नित।',
      'Volunteer accepted. Help is on the way.':
          'स्वयंसेवक ने स्वीकार किया। मदद रास्ते में है।',
      'Ambulance dispatched. Estimated arrival:':
          'एम्बुलेंस रवाना। अनुमानित आगमन:',
      'Police dispatched. Estimated arrival:':
          'पुलिस रवाना। अनुमानित आगमन:',
      'Confirmed conscious. Starting vital questions for responders.':
          'होश में पुष्टि। बचावकर्ताओं के लिए महत्वपूर्ण सवाल शुरू।',
      'We marked you as unconscious for emergency responders. Stay calm. Help is coming.':
          'हमने आपको बेहोश चिह्नित किया है। शांत रहें। मदद आ रही है।',
      'All victim interview data has been saved. Responders now have detailed information. Consciousness checks will continue every 60 seconds.':
          'सभी जानकारी सहेज ली गई है। बचावकर्ताओं को विस्तृत जानकारी मिली। हर 60 सेकंड में होश की जांच जारी रहेगी।',
      'Victim is conscious but cannot speak. Monitoring continues.':
          'पीड़ित होश में है लेकिन बोल नहीं सकता। निगरानी जारी है।',
      'Can you speak and answer a few quick questions? This will help emergency responders.':
          'क्या आप बोल सकते हैं और कुछ सवालों का जवाब दे सकते हैं? इससे बचावकर्ताओं को मदद मिलेगी।',
      'What is the nature of your emergency? For example: accident, heart problem, breathing difficulty, injury, fire.':
          'आपकी आपातकालीन स्थिति क्या है? उदाहरण: दुर्घटना, हृदय समस्या, सांस की तकलीफ, चोट, आग।',
      'How many people are injured or need help?':
          'कितने लोग घायल हैं या मदद चाहिए?',
      'Are you in a safe location right now?':
          'क्या आप अभी सुरक्षित जगह पर हैं?',
      'Are you or anyone experiencing severe pain? If yes, where is the pain?':
          'क्या आपको या किसी को तेज़ दर्द है? अगर हाँ, तो दर्द कहाँ है?',
      'Are there any hazards nearby? For example: fire, gas leak, structural damage, traffic.':
          'क्या पास में कोई खतरा है? उदाहरण: आग, गैस रिसाव, ढांचागत क्षति, ट्रैफिक।',
      'Is anyone bleeding severely or having trouble breathing?':
          'क्या किसी को गंभीर खून बह रहा है या सांस लेने में तकलीफ है?',
      'To send a voice message to responders, hold the red Broadcast button at any time. Your voice will be sent to the incident channel and transcribed as text.':
          'बचावकर्ताओं को आवाज़ संदेश भेजने के लिए, लाल ब्रॉडकास्ट बटन को दबाकर रखें। आपकी आवाज़ चैनल पर भेजी जाएगी और टेक्स्ट में बदली जाएगी।',
      'No voice response. Consciousness check attempt one of three. We will ask again in one minute.':
          'कोई आवाज़ जवाब नहीं। होश की जांच: एक में से एक। हम एक मिनट में फिर पूछेंगे।',
      'No voice response. Consciousness check attempt two of three. We will ask again in one minute.':
          'कोई आवाज़ जवाब नहीं। होश की जांच: तीन में से दो। हम एक मिनट में फिर पूछेंगे।',
    },
    'es': {
      'Your SOS is active now. Help will be arriving soon.':
          'Tu SOS está activo ahora. La ayuda llegará pronto.',
      'Are you conscious? Please answer yes or no.':
          '¿Estás consciente? Por favor responde sí o no.',
      'Volunteer accepted. Help is on the way.':
          'Un voluntario ha aceptado. La ayuda está en camino.',
    },
    'fr': {
      'Your SOS is active now. Help will be arriving soon.':
          'Votre SOS est maintenant actif. L\'aide arrivera bientôt.',
      'Are you conscious? Please answer yes or no.':
          'Êtes-vous conscient? Veuillez répondre oui ou non.',
      'Volunteer accepted. Help is on the way.':
          'Un bénévole a accepté. L\'aide est en chemin.',
    },
  };

  /// BCP-47 for on-device TTS. Includes every [kSupportedLocales] language code.
  static String bcp47ForLocale(String locale) {
    switch (locale.toLowerCase()) {
      case 'en':
        return 'en-IN';
      case 'hi':
        return 'hi-IN';
      case 'ta':
        return 'ta-IN';
      case 'te':
        return 'te-IN';
      case 'kn':
        return 'kn-IN';
      case 'ml':
        return 'ml-IN';
      case 'bn':
        return 'bn-IN';
      case 'mr':
        return 'mr-IN';
      case 'gu':
        return 'gu-IN';
      case 'pa':
        return 'pa-IN';
      case 'or':
        return 'or-IN';
      case 'ur':
        return 'ur-IN';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'ar':
        return 'ar-SA';
      case 'zh':
        return 'zh-CN';
      case 'pt':
        return 'pt-BR';
      case 'de':
        return 'de-DE';
      case 'ja':
        return 'ja-JP';
      case 'ko':
        return 'ko-KR';
      case 'ru':
        return 'ru-RU';
      default:
        return 'en-IN';
    }
  }

  static bool _runeInArabicScript(int r) {
    return (r >= 0x0600 && r <= 0x06FF) ||
        (r >= 0x0750 && r <= 0x077F) ||
        (r >= 0x08A0 && r <= 0x08FF) ||
        (r >= 0xFB50 && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF);
  }

  /// Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam.
  static bool _runeInIndicBrahmic(int r) {
    return (r >= 0x0900 && r <= 0x0D7F);
  }

  /// True if [text] contains Arabic script (e.g. Urdu).
  static bool _hasArabicScript(String text) {
    for (final r in text.runes) {
      if (_runeInArabicScript(r)) return true;
    }
    return false;
  }

  /// True if [text] contains Brahmic script used by app locales.
  static bool _hasIndicScript(String text) {
    for (final r in text.runes) {
      if (_runeInIndicBrahmic(r)) return true;
    }
    return false;
  }

  /// TTS BCP-47 tag for this utterance (policy: **script-based**, not UI-only).
  ///
  /// - **Indic / Arabic script** in [spoken] → use [appLocale]’s engine ([bcp47ForLocale]) so
  ///   native-script strings get a matching voice when the OS/browser has that pack.
  /// - **Latin-only** and app locale is **English** → `en-IN` for clear English delivery.
  /// - **Latin-only** and app locale is **not** English (e.g. Spanish UI) → that locale’s voice.
  ///
  /// Tradeoff: mixed Latin + Indic in one string is tagged by the **dominant script** only;
  /// hospital dispatch lines are localized separately so Indic TTS applies to full sentences.
  /// Native [speech_io] falls back to `en-IN` if `isLanguageAvailable` fails; web [index.html]
  /// aligns `utter.lang` with the chosen `voice` to avoid silent synthesis.
  static String _bcp47ForSpokenText(String spoken, String appLocale) {
    final lc = appLocale.toLowerCase();
    if (_hasArabicScript(spoken)) return bcp47ForLocale('ur');
    if (_hasIndicScript(spoken)) return bcp47ForLocale(lc);
    if (lc != 'en') return bcp47ForLocale(lc);
    return 'en-IN';
  }

  /// Full string or longest-prefix (e.g. ETA suffix after a known prefix).
  static String _translate(String text, String locale) {
    final map = _translations[locale];
    if (map == null) return text;
    if (map[text] != null) return map[text]!;
    String? bestKey;
    for (final k in map.keys) {
      if (text.startsWith(k) && (bestKey == null || k.length > bestKey.length)) {
        bestKey = k;
      }
    }
    if (bestKey != null) return map[bestKey]! + text.substring(bestKey.length);
    return text;
  }

  static Future<String> getLocale() async {
    if (!_localeLoaded) {
      try {
        final prefs = await SharedPreferences.getInstance();
        _cachedLocale = prefs.getString('app_locale') ?? 'en';
      } catch (_) {}
      _localeLoaded = true;
    }
    return _cachedLocale;
  }

  /// Clears the "loaded" flag so the next [getLocale] re-reads [SharedPreferences].
  /// Does **not** clear [_cachedLocale] — that value remains the best hint for sync paths
  /// like [readAloudImmediate] (web user-gesture) until prefs are refreshed.
  static void invalidateLocaleCache() => _localeLoaded = false;

  /// Call when the user changes app language (or after loading prefs) so TTS sees the
  /// new code without waiting for an async [getLocale].
  static void syncLocaleFromPreference(String languageCode) {
    final c = languageCode.trim().toLowerCase();
    if (c.isEmpty) return;
    _cachedLocale = c;
    _localeLoaded = true;
  }

  /// Call synchronously from a tap / pointer-up **before** any `await` so web TTS is allowed.
  static void primeForVoiceGuidance() => primeSpeechAudioContext();

  /// Enqueue speech without awaiting [SharedPreferences] (same event turn as user gesture).
  static void readAloudImmediate(String text) {
    final t = text.trim();
    if (t.isEmpty || silenceMode) return;
    if (kIsWeb) bankUserGestureForWeb();
    // Never assume English when prefs have not been read yet — [_cachedLocale] may still
    // hold the last known code (e.g. hi). Forcing 'en' here broke Hindi/Indic TTS on web.
    final locale = _cachedLocale;
    final localized = _translate(t, locale);
    final bcp47 = _bcp47ForSpokenText(localized, locale);
    _enqueueSpeak(localized, bcp47, null);
  }

  static void markSosVoicePrimedForActiveScreen() {
    _sosOpeningPrimedForNavigation = true;
  }

  static bool get peekSosVoicePrimedForActiveScreen => _sosOpeningPrimedForNavigation;

  static bool takeSosOpeningPrimedForActiveScreen() {
    final v = _sosOpeningPrimedForNavigation;
    _sosOpeningPrimedForNavigation = false;
    return v;
  }

  /// If SOS navigation was aborted after [readAloudImmediate] (e.g. PIN not ready).
  static void discardSosVoicePriming() {
    _sosOpeningPrimedForNavigation = false;
    clearSpeakQueue();
  }

  static void clearSpeakQueue() {
    _drainGeneration++;
    for (final item in _queue) {
      if (item.completer != null && !item.completer!.isCompleted) {
        item.completer!.complete();
      }
    }
    _queue.clear();
    _stuckTimer?.cancel();
    _draining = false;
    cancelSpeechText();
  }

  // ── Public API: voice agent read-outs ───────────────────────────────────

  /// Speaks [text] on this device (queued). This is the **only** voice comms path.
  static Future<void> readAloud(String text) async {
    final t = text.trim();
    if (t.isEmpty || silenceMode) return;
    // Web: any await before speechSynthesis breaks user-activation — use sync enqueue.
    if (kIsWeb) {
      readAloudImmediate(t);
      return;
    }
    final locale = await getLocale();
    final localized = _translate(t, locale);
    final bcp47 = _bcp47ForSpokenText(localized, locale);
    _enqueueSpeak(localized, bcp47, null);
  }

  /// Same as [readAloud] but ignores empty [incidentId] for call-site clarity.
  static Future<void> readAloudForIncident({
    required String incidentId,
    required String text,
  }) async {
    if (incidentId.trim().isEmpty) return;
    await readAloud(text);
  }

  static Future<void> readAloudAndWait(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final completer = Completer<void>();
    if (kIsWeb) {
      final locale = _cachedLocale;
      final localized = _translate(t, locale);
      final bcp47 = _bcp47ForSpokenText(localized, locale);
      _enqueueSpeak(localized, bcp47, completer);
    } else {
      final locale = await getLocale();
      final localized = _translate(t, locale);
      final bcp47 = _bcp47ForSpokenText(localized, locale);
      _enqueueSpeak(localized, bcp47, completer);
    }
    await Future.any<void>([
      completer.future,
      Future<void>.delayed(const Duration(seconds: 45)),
    ]);
  }

  @Deprecated('Use readAloud')
  static Future<void> speakLocally(String text) => readAloud(text);

  @Deprecated('Use readAloudAndWait')
  static Future<void> speakLocallyAndWait(String text) => readAloudAndWait(text);

  @Deprecated('Use readAloudForIncident')
  static Future<void> announce({
    required String incidentId,
    required String text,
  }) =>
      readAloudForIncident(incidentId: incidentId, text: text);

  @Deprecated('Use readAloudForIncident')
  static Future<void> announceToLifeline({
    required String incidentId,
    required String text,
  }) =>
      readAloudForIncident(incidentId: incidentId, text: text);

  // ── Queue ──────────────────────────────────────────────────────────────

  static void _enqueueSpeak(String text, String lang, Completer<void>? completer) {
    final segments = _splitSpeakSegments(text);
    for (var i = 0; i < segments.length; i++) {
      final c = i == segments.length - 1 ? completer : null;
      _queue.add(_VoiceQueueItem(segments[i], lang, c));
    }
    _startDrainIfNeeded();
  }

  static void _startDrainIfNeeded() {
    if (_draining || _queue.isEmpty) return;
    unawaited(_drainQueue());
  }

  static void _emitTtsUnavailableBanner() {
    final msg = AppLocalizations.lookup(_cachedLocale, 'voice_tts_unavailable_banner');
    ttsStatusNotifier.value = msg;
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (ttsStatusNotifier.value == msg) {
        ttsStatusNotifier.value = null;
      }
    });
  }

  static Future<void> _drainQueue() async {
    if (_draining) return;
    _draining = true;
    final gen = _drainGeneration;
    try {
      while (_queue.isNotEmpty && gen == _drainGeneration) {
        final item = _queue.removeAt(0);
        if (silenceMode) {
          if (item.completer != null && !item.completer!.isCompleted) {
            item.completer!.complete();
          }
          continue;
        }

        final stuckMs = (item.text.length * 220 + 12000).clamp(20000, 180000);

        try {
          final localOk = await nativeVoiceAvailable(item.lang);
          if (!localOk) {
            final mp3 = await CloudTtsService.synthesize(item.text, item.lang);
            if (mp3 != null && mp3.isNotEmpty) {
              await CloudTtsService.playMp3(mp3);
            } else {
              _emitTtsUnavailableBanner();
            }
          } else {
            final utterDone = Completer<void>();
            _stuckTimer?.cancel();
            _stuckTimer = Timer(Duration(milliseconds: stuckMs), () {
              debugPrint('[VoiceComms] TTS stuck after ${stuckMs}ms — advancing queue');
              if (!utterDone.isCompleted) utterDone.complete();
            });
            speakText(
              item.text,
              lang: item.lang,
              onDone: () {
                if (!utterDone.isCompleted) utterDone.complete();
              },
            );
            await utterDone.future;
            _stuckTimer?.cancel();
          }
        } catch (e, st) {
          debugPrint('[VoiceComms] utterance error: $e\n$st');
          _emitTtsUnavailableBanner();
        } finally {
          _stuckTimer?.cancel();
          if (item.completer != null && !item.completer!.isCompleted) {
            item.completer!.complete();
          }
        }
      }
    } finally {
      _draining = false;
      _stuckTimer?.cancel();
      if (gen == _drainGeneration && _queue.isNotEmpty) {
        _startDrainIfNeeded();
      }
    }
  }
}

class _VoiceQueueItem {
  final String text;
  final String lang;
  final Completer<void>? completer;
  _VoiceQueueItem(this.text, this.lang, this.completer);
}
