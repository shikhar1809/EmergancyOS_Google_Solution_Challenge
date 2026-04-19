// ignore_for_file: avoid_web_libraries_in_flutter
// Web-only implementation; routed via conditional import from the main maps
// bridge. The lint flags direct dart:html use, but this file is only compiled
// for the web target.
import 'dart:html' as html;

void registerGoogleMapsWebFailureBridgeImpl(void Function(String reason) onFailure) {
  html.window.addEventListener('eos-google-maps-unavailable', (event) {
    var reason = 'web_event';
    if (event is html.CustomEvent) {
      final d = event.detail;
      if (d != null) reason = d.toString();
    }
    onFailure(reason);
  });
}
