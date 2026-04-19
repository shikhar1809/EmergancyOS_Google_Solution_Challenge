/// Demo credentials pre-filled on judge-facing login gates.
/// Override at build time with `--dart-define` flags:
///   --dart-define=DEMO_ADMIN_EMAIL=ops@emergencyos.app
///   --dart-define=DEMO_ADMIN_PASSWORD=8ACBSHSZPP
///   --dart-define=DEMO_HOSPITAL_ID=H-LKO-18
///   --dart-define=DEMO_FLEET_ID=EMS-H-LKO-18-A
///
/// IMPORTANT: Change these defaults before any production deployment.
abstract final class DemoCredentials {
  /// Master admin email for the Firebase Auth email/password account.
  static const adminEmail = String.fromEnvironment(
    'DEMO_ADMIN_EMAIL',
    defaultValue: '',
  );

  /// Master admin password (also used as hospital gate password hint).
  static const adminPassword = String.fromEnvironment(
    'DEMO_ADMIN_PASSWORD',
    defaultValue: '8ACBSHSZPP',
  );

  /// Hospital document ID pre-filled on the Hospital Dashboard gate.
  static const hospitalId = String.fromEnvironment(
    'DEMO_HOSPITAL_ID',
    defaultValue: 'H-LKO-18',
  );

  /// Fleet call sign pre-filled on the Fleet Operator gate.
  static const fleetId = String.fromEnvironment(
    'DEMO_FLEET_ID',
    defaultValue: '',
  );
}
