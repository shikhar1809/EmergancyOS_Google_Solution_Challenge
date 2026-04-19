// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

void downloadTextFile(String filename, String contents) {
  final safeName = filename.replaceAll(RegExp(r'[^\w.\-]'), '_');
  final bytes = utf8.encode(contents);
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', safeName.isEmpty ? 'report.txt' : safeName)
    ..click();
  html.Url.revokeObjectUrl(url);
}
