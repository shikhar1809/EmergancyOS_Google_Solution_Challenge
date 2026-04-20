/// Demo fleet / hospital gate password (Firestore seeds and UI hints).
/// Override at build time: `--dart-define=DEMO_GATE_PASSWORD=your_value`.
/// Do not use the default in production — set gates in Firestore and dart-define.
abstract final class DemoGatePassword {
  static const value = String.fromEnvironment(
    'DEMO_GATE_PASSWORD',
    defaultValue: '8ACBSHSZPP',
  );
}