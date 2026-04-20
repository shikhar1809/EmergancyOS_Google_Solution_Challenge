/// Demo credentials pre-filled on judge-facing login gates.
/// Override at build time with `--dart-define` flags:
///   --dart-define=DEMO_ADMIN_EMAIL=you@example.com
///   --dart-define=DEMO_ADMIN_PASSWORD=your_master_or_medical_gate_password
///   --dart-define=DEMO_HOSPITAL_ID=H-LKO-18
///   --dart-define=DEMO_FLEET_ID=EMS-LKO-18
///   --dart-define=DEMO_FLEET_GATE_PASSWORD=your_fleet_gate_password
///
/// IMPORTANT: Change these defaults before any production deployment.
abstract final class DemoCredentials {
  /// Master admin email for the Firebase Auth email/password account.
  static const adminEmail = String.fromEnvironment(
    'DEMO_ADMIN_EMAIL',
    defaultValue: 'admin@emergencyos.com',
  );

  /// Master admin + medical gate password pre-fill (hospital gate uses the same field in admin UI).
  static const adminPassword = String.fromEnvironment(
    'DEMO_ADMIN_PASSWORD',
    defaultValue: 'admin123',
  );

  /// Hospital document ID pre-filled on the Hospital Dashboard gate.
  static const hospitalId = String.fromEnvironment(
    'DEMO_HOSPITAL_ID',
    defaultValue: 'H-LKO-18',
  );

  /// Fleet call sign pre-filled on the Fleet Operator gate.
  static const fleetId = String.fromEnvironment(
    'DEMO_FLEET_ID',
    defaultValue: 'EMS-LKO-18',
  );

  /// `ops_fleet_accounts` gate password pre-filled on the Fleet Operator screen only.
  static const fleetGatePassword = String.fromEnvironment(
    'DEMO_FLEET_GATE_PASSWORD',
    defaultValue: 'ZBYF2MTL',
  );
}
