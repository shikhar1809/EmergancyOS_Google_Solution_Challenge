// Runs Python Google Cloud Translate fill for [kDashboardL10nByLang].
//
// Prerequisites:
// - Python 3 on PATH
// - GOOGLE_TRANSLATE_API_KEY environment variable (Cloud Translation API)
//
// Usage (from project root):
//   dart run scripts/generate_translations.dart
//
// See also: scripts/generate_dashboard_translations.py

import 'dart:io';

void main() {
  final root = Directory.current.path;
  final script = '$root${Platform.pathSeparator}scripts${Platform.pathSeparator}generate_dashboard_translations.py';
  if (!File(script).existsSync()) {
    stderr.writeln('Missing $script');
    exit(1);
  }
  final r = Process.runSync(
    'python',
    [script],
    workingDirectory: root,
    environment: Platform.environment,
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  exit(r.exitCode);
}
