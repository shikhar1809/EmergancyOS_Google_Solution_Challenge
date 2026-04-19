// ignore_for_file: avoid_print

import 'dart:io';

/// One-off helper: scans dashboard Dart files and prints suggested l10n keys.
/// Run: dart run scripts/extract_dashboard_strings.dart > /tmp/out.txt
void main() {
  final roots = [
    'lib/features/staff/presentation',
    'lib/features/hospital_bridge/presentation',
    'lib/features/operations/presentation',
  ];
  final seen = <String, String>{};
  final re = RegExp(
    r"(?:Text|SnackBar|label:|title:|tooltip:|hintText:|helperText:|semanticLabel:|child:\s*Text)\s*\(\s*'((?:\\'|[^'])*)'",
    multiLine: true,
  );
  final re2 = RegExp(
    r'(?:Text|SnackBar|label:|title:|tooltip:|hintText:|helperText:|semanticLabel:|child:\s*Text)\s*\(\s*"((?:\\"|[^"])*)"',
    multiLine: true,
  );

  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final m in re.allMatches(text)) {
        final s = m.group(1)!.replaceAll(r"\'", "'");
        if (s.length > 200 || s.contains(r'$')) continue;
        if (s.trim().isEmpty) continue;
        seen.putIfAbsent(s, () => f.path);
      }
      for (final m in re2.allMatches(text)) {
        final s = m.group(1)!;
        if (s.length > 200 || s.contains(r'$')) continue;
        if (s.trim().isEmpty) continue;
        seen.putIfAbsent(s, () => f.path);
      }
    }
  }

  var i = 0;
  for (final entry in seen.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
    final key = 'ops_auto_${i++}';
    final escaped = entry.key.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    print("  '$key': '$escaped', // ${entry.value}");
  }
}
