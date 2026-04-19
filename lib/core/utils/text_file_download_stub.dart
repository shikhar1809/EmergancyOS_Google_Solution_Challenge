import 'package:flutter/foundation.dart';

/// Non-web: copy is handled by caller; stub avoids importing dart:io here.
void downloadTextFile(String filename, String contents) {
  if (kDebugMode) {
    debugPrint('[downloadTextFile] stub: $filename (${contents.length} chars)');
  }
}
