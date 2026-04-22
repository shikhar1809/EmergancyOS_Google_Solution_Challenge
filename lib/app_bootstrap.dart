import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/early_locale.dart';
import 'core/maps/maps_fallback_bootstrap.dart';
import 'core/providers/high_contrast_ops_provider.dart';
import 'core/providers/locale_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_variant.dart';
import 'core/utils/router.dart';
import 'firebase_options.dart';
import 'core/l10n/app_localizations.dart';
import 'services/demo_data_service.dart';
import 'services/drill_entry_service.dart';
import 'services/fcm_service.dart';
import 'services/incident_seed_service.dart';
import 'services/leaderboard_service.dart';
import 'services/offline_cache_service.dart';
import 'services/ops_hospital_service.dart';
import 'services/voice_comms_service.dart';
import 'services/volunteer_presence_service.dart';

Future<void> bootstrapEmergencyOS(AppVariant variant) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (kIsWeb) {
      usePathUrlStrategy();
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.forVariant(variant),
    );

    if (kIsWeb) {
      try {
        await FirebaseAuth.instance.initializeRecaptchaConfig();
      } catch (e, st) {
        debugPrint('[FirebaseAuth] initializeRecaptchaConfig failed: $e');
        assert(() {
          debugPrint('$st');
          return true;
        }());
      }
    }

    FlutterError.onError = (errorDetails) {
      FirebaseCrashlytics.instance.recordFlutterFatalError(errorDetails);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // Web uses the Firestore JS SDK. IndexedDB persistence + rapid auth changes
    // (hospital gate: signOut → signInAnonymously) has triggered INTERNAL ASSERTION
    // failures in WatchChangeAggregator (e.g. FIRESTORE 12.9.x). Memory cache on web
    // avoids that class of bugs; mobile/desktop keep disk persistence.
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: !kIsWeb,
      cacheSizeBytes: 50 * 1024 * 1024,
    );

    await OfflineCacheService.init();

    // FIX 6: Register lifecycle observer to immediately clear volunteer availability
    // when the app backgrounds, ensuring no ghost-volunteer dispatches occur.
    VolunteerPresenceService.initLifecycleObserver();

    // Sync locale before prefs async completes (web: localStorage hint).
    final earlyLocale = readEarlyAppLocaleHint();
    if (earlyLocale != null && earlyLocale.isNotEmpty) {
      VoiceCommsService.syncLocaleFromPreference(earlyLocale);
    }
    // So first web TTS (readAloudImmediate) uses app language, not default en.
    await VoiceCommsService.getLocale();

    try {
      const recaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: '');
      if (kIsWeb) {
        if (recaptchaSiteKey.isNotEmpty) {
          await FirebaseAppCheck.instance.activate(
            webProvider: ReCaptchaV3Provider(recaptchaSiteKey),
          );
        }
      } else {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.deviceCheck,
        );
      }
    } catch (_) {}

    // Seed/purge data only for the main app (avoid side-effects on admin/fleet hostings).
    if (variant == AppVariant.main) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('demo_incidents_purged_v1') != true) {
        await IncidentSeedService.clearDemoIncidents();
        await prefs.setBool('demo_incidents_purged_v1', true);
      }
      if (prefs.getBool('demo_platform_docs_purged_v2') != true) {
        await DemoDataService.purgeAll();
        await prefs.setBool('demo_platform_docs_purged_v2', true);
      }
      await DrillEntryService.clearLegacyDashboardDemoPreference();

      if (prefs.getBool('legacy_bundled_ops_hospitals_purged_v1') != true) {
        final purged =
            await OpsHospitalService.purgeLegacyBundledHospitalDocumentsFromFirestore();
        if (purged) await prefs.setBool('legacy_bundled_ops_hospitals_purged_v1', true);
      }
    }

    FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid != null && uid.isNotEmpty) {
        FcmService.init(uid);
        if (variant == AppVariant.main) {
          unawaited(LeaderboardService.syncVolunteerPublicProfile(user!));
        }
      }
    });

    runApp(ProviderScope(child: EmergencyOSApp(variant: variant)));
  } catch (e, stack) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            'FATAL STARTUP ERROR:\n\n$e\n\n$stack',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ),
    ));
  }
}

class EmergencyOSApp extends ConsumerWidget {
  const EmergencyOSApp({super.key, required this.variant});

  final AppVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final highContrastOps = ref.watch(highContrastOpsProvider);

    final title = switch (variant) {
      AppVariant.main => 'EmergencyOS',
      AppVariant.admin => 'EmergencyOS · Admin',
      AppVariant.fleet => 'EmergencyOS · Fleet',
      AppVariant.hospital => 'EmergencyOS · Hospital',
    };

    return MaterialApp.router(
      title: title,
      theme: highContrastOps ? AppTheme.highContrastOpsTheme : AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      locale: locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      routerConfig: buildRouter(variant),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final minScale = highContrastOps ? 1.0 : 0.88;
        final maxScale = highContrastOps ? 1.5 : 1.34;
        return MapsFallbackBootstrap(
          child: MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: minScale,
                maxScaleFactor: maxScale,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

