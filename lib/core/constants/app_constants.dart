/// App-wide constants for EmergencyOS.
/// API keys are injected at compile time via --dart-define (never stored in assets).
///
/// Usage: flutter run --dart-define=GEMINI_API_KEY=xxx --dart-define=GOOGLE_MAPS_API_KEY=yyy
class AppConstants {
  static const String appName = 'EmergencyOS';

  /// Demo mode flag - when true, allows volunteer/officer drill login without real authentication.
  /// Set via: --dart-define=DEMO_MODE=true
  /// In production, this should NOT be set, forcing proper Google/Phone sign-in.
  static const bool demoModeEnabled = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  /// Stable id for practice / drill flows (no real Firestore document required).
  static const String drillIncidentId = 'emergencyos_drill_session';

  /// PIN for UNLOCK on the practice SOS screen only (drill mode). Not used for live SOS.
  static const String drillSosPracticePin = '1234';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String incidentsCollection = 'incidents';
  static const String volunteersCollection = 'volunteers';

  // Gemini — injected at compile time, never shipped in a readable asset
  static const String geminiModel = 'gemini-2.5-flash';
  static const String geminiApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // Google Maps / Places — injected at compile time
  static const String googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

  /// Google Maps Cloud Map ID (optional; style is edited in Google Cloud Map Styles / Maps SDK).
  /// When non-empty, embedded dark ops JSON in `google_maps_illustrative_light_style.dart` is not
  /// applied: the Cloud-published style is used instead. Align that Cloud style with the
  /// emergency-response palette, or omit this define to rely on embedded JSON only.
  static const String googleMapsDarkMapId =
      String.fromEnvironment('GOOGLE_MAPS_DARK_MAP_ID', defaultValue: '');

  // Asset Paths (splash + login use the same brand mark)
  static const String logoPath = 'assets/images/logo.png';
  static const String splashLogoPath = 'assets/images/logo.png';
  static const String animSOSPath = 'assets/animations/sos_pulse.json';

  // Volunteer alert radius (meters)
  static const double volunteerAlertRadiusMeters = 10000.0; // 10 km

  // ── SMS Gateway Configuration ───────────────────────────────────────────
  /// Primary gateway number that receives and parses inbound GeoSMS alerts.
  /// Replace with your production SIM/Twilio number before deployment.
  static const String smsGatewayNumber = '+15674051628';

  /// Radius used by the Cloud Function geo-query for volunteer dispatch.
  static const int smsRadiusKm = 10;

  /// Base URL embedded in outgoing GeoSMS messages (Open GeoSMS spec).
  static const String geoSmsBaseUrl = 'https://emergencyos.app/sos';
}
