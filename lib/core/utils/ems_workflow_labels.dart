/// Fleet operator strip + hospital dashboards + volunteer/SOS: one label for [emsWorkflowPhase].
String emsWorkflowPhaseShortLabel(String? raw) {
  final p = (raw ?? '').trim();
  if (p.isEmpty) return 'Not started';
  return switch (p) {
    'inbound' => 'En route',
    'on_scene' => 'On scene',
    'returning' => 'Returning',
    'complete' => 'Response complete',
    _ => p.replaceAll('_', ' '),
  };
}
