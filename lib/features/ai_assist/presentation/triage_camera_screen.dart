import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ai_advisory_banner.dart';
// ---------------------------------------------------------------------------
// Triage Camera Screen — Gemini Vision Wound Analysis
// ---------------------------------------------------------------------------

enum TriageSeverity { green, yellow, red, black }

extension TriageSeverityExt on TriageSeverity {
  Color get color => const {
    TriageSeverity.green:  Colors.green,
    TriageSeverity.yellow: Colors.yellow,
    TriageSeverity.red:    Colors.red,
    TriageSeverity.black:  Colors.black,
  }[this]!;
  String get label => const {
    TriageSeverity.green:  'MINOR — Delayed',
    TriageSeverity.yellow: 'DELAYED — Monitor',
    TriageSeverity.red:    'IMMEDIATE — Treat Now',
    TriageSeverity.black:  'EXPECTANT — Critical',
  }[this]!;
}

class TriageResult {
  final TriageSeverity severity;
  final String category;
  final String? aiRecommendedSpecialty;
  final String confidence;
  final String analysis;
  final List<String> immediateSteps;
  final String rawResponse;

  const TriageResult({
    required this.severity,
    required this.category,
    required this.aiRecommendedSpecialty,
    required this.confidence,
    required this.analysis,
    required this.immediateSteps,
    required this.rawResponse,
  });
}

class TriageCameraScreen extends ConsumerStatefulWidget {
  const TriageCameraScreen({super.key, this.incidentId});

  /// Optional: the incident to attach AI triage onto. When provided, the
  /// screen offers a one-tap button that writes the structured Gemini triage
  /// vision onto `sos_incidents/{id}.triage.aiVision` and re-runs hospital
  /// dispatch so the updated specialty recommendation reshuffles the chain.
  final String? incidentId;

  @override
  ConsumerState<TriageCameraScreen> createState() => _TriageCameraScreenState();
}

class _TriageCameraScreenState extends ConsumerState<TriageCameraScreen> {
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  TriageResult? _result;
  bool _loading = false;
  String? _error;
  bool _attaching = false;
  String? _attachSuccessMsg;

  // Safety preamble is also enforced server-side in `analyzeTriageImage`.
  // We keep a compact client-side task block so the model sees clear output rules.
  static const _systemPrompt = '''
TRIAGE TASK
Analyze the image and respond ONLY in this JSON format (no markdown fences):
{
  "severity": "green|yellow|red|black",
  "category": "cardiac|trauma|burn|bleed|fall|drowning|fire|rta|medical|other",
  "aiRecommendedSpecialty": "cardiac|trauma|burn|pediatric|stroke|general",
  "confidence": "low|medium|high",
  "analysis": "Brief clinical description of what you observe (no diagnosis)",
  "steps": ["Step 1", "Step 2", "Step 3"]
}

Triage levels:
- green: Minor, non-life-threatening
- yellow: Delayed, serious but stable
- red: Immediate, life-threatening, treat NOW
- black: Expectant, unsurvivable or requires resources beyond available

Rules:
- Be clinical, specific, and actionable. Steps must be numbered first-aid actions.
- If the image is NOT a medical/injury image, respond with severity "green", category "other", and say so in analysis.
- Never invent injuries that are not visible. Never guess identity or diagnosis.
- If severity is red or black, make sure "Call 112 now" is step 1.
''';

  Future<void> _pickAndAnalyze({bool fromCamera = true}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final picked = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) { setState(() => _loading = false); return; }

      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);

      final base64Img = base64Encode(bytes);
      
      final promptStr = '$_systemPrompt\n\nAnalyze this injury/medical image for triage.';

      final callable = FirebaseFunctions.instance.httpsCallable('analyzeTriageImage');
      final response = await callable.call({
        'base64str': base64Img,
        'mimeType': 'image/jpeg',
        'prompt': promptStr,
      }).timeout(const Duration(seconds: 30));

      final raw = response.data['result'] as String? ?? '';
      final result = _parseTriageResponse(raw);
      setState(() { _result = result; _loading = false; _attachSuccessMsg = null; });
    } catch (e) {
      setState(() { _error = 'Analysis failed: $e'; _loading = false; });
    }
  }

  /// Writes the parsed AI triage result onto the linked incident document so
  /// hospital dispatch can reshuffle against the recommended specialty.
  Future<void> _attachTriageToIncident() async {
    final incidentId = widget.incidentId;
    final result = _result;
    if (incidentId == null || result == null || _attaching) return;
    setState(() { _attaching = true; _attachSuccessMsg = null; _error = null; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('applyAiTriageToIncident');
      await callable.call({
        'incidentId': incidentId,
        'triage': {
          'severity': result.severity.name,
          'category': result.category,
          'aiRecommendedSpecialty': result.aiRecommendedSpecialty,
          'confidence': result.confidence,
          'analysis': result.analysis,
          'steps': result.immediateSteps,
        },
      }).timeout(const Duration(seconds: 15));
      setState(() {
        _attaching = false;
        _attachSuccessMsg = 'AI triage attached to incident. Hospital dispatch will re-rank for '
            '${result.aiRecommendedSpecialty ?? "general"} specialty.';
      });
    } catch (e) {
      setState(() {
        _attaching = false;
        _error = 'Failed to attach AI triage: $e';
      });
    }
  }

  TriageResult _parseTriageResponse(String raw) {
    // Server enforces responseMimeType=application/json + responseSchema, so
    // `raw` should be a clean JSON object. The guarded decode below tolerates
    // stray markdown fences if they ever slip through.
    try {
      var text = raw.trim();
      if (text.startsWith('```json')) {
        text = text.substring(7);
      } else if (text.startsWith('```')) {
        text = text.substring(3);
      }
      if (text.endsWith('```')) {
        text = text.substring(0, text.length - 3);
      }
      text = text.trim();
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        text = text.substring(start, end + 1);
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) throw Exception('Not an object');

      final severityStr = (decoded['severity'] as String?)?.trim().toLowerCase() ?? 'yellow';
      final category = (decoded['category'] as String?)?.trim().toLowerCase() ?? 'other';
      final specialty = (decoded['aiRecommendedSpecialty'] as String?)?.trim().toLowerCase();
      final confidence = (decoded['confidence'] as String?)?.trim().toLowerCase() ?? 'medium';
      final analysis = (decoded['analysis'] as String?)?.trim() ?? 'See full response below.';

      final stepsRaw = decoded['steps'];
      final steps = <String>[];
      if (stepsRaw is List) {
        for (final s in stepsRaw) {
          final str = s?.toString().trim();
          if (str != null && str.isNotEmpty) steps.add(str);
        }
      }

      final severity = TriageSeverity.values.firstWhere(
        (s) => s.name == severityStr,
        orElse: () => TriageSeverity.yellow,
      );

      return TriageResult(
        severity: severity,
        category: category,
        aiRecommendedSpecialty: (specialty != null && specialty.isNotEmpty) ? specialty : null,
        confidence: confidence,
        analysis: analysis,
        immediateSteps: steps,
        rawResponse: raw,
      );
    } catch (_) {
      return TriageResult(
        severity: TriageSeverity.yellow,
        category: 'other',
        aiRecommendedSpecialty: null,
        confidence: 'low',
        analysis: 'Analysis complete — see details below.',
        immediateSteps: [raw],
        rawResponse: raw,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.camera_alt_rounded, color: Colors.redAccent),
          SizedBox(width: 8),
          Text('TRIAGE SCAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        ]),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Instructions
            if (_imageBytes == null && !_loading)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.document_scanner_rounded, color: Colors.redAccent, size: 56),
                    SizedBox(height: 12),
                    Text('AI Wound Triage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    SizedBox(height: 8),
                    Text('Point camera at wound or injury. Gemini Vision will classify severity (Green/Yellow/Red/Black) and give immediate field actions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),

            if (_imageBytes == null && !_loading) const SizedBox(height: 24),

            // Action Buttons
            if (!_loading && _result == null) ...[
              ElevatedButton.icon(
                onPressed: () => _pickAndAnalyze(fromCamera: true),
                icon: const Icon(Icons.camera_alt_rounded),
                label: const Text('CAPTURE WOUND PHOTO', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, color: Colors.amber, size: 14),
                    SizedBox(width: 4),
                    Text('Tip: Use flash or bright light for better AI accuracy', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _pickAndAnalyze(fromCamera: false),
                icon: const Icon(Icons.photo_library_rounded, color: Colors.white70),
                label: const Text('UPLOAD FROM GALLERY', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],

            // Loading
            if (_loading) ...[
              const SizedBox(height: 40),
              const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
              const SizedBox(height: 16),
              const Text('Analyzing image with Gemini Vision...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14)),
            ],

            // Image Preview
            if (_imageBytes != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(_imageBytes!, height: 200, fit: BoxFit.cover),
              ),
            ],

            // Error
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ),
            ],

            // Result
            if (_result != null) ...[
              const SizedBox(height: 20),
              // Severity Badge
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _result!.severity.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _result!.severity.color, width: 2),
                ),
                child: Column(
                  children: [
                    Text('TRIAGE LEVEL', style: TextStyle(color: _result!.severity.color, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(_result!.severity.label,
                      style: TextStyle(color: _result!.severity.color, fontSize: 22, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Analysis
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CLINICAL ASSESSMENT', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_result!.analysis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Steps
              if (_result!.immediateSteps.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('IMMEDIATE ACTIONS', style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ..._result!.immediateSteps.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: _result!.severity.color.withValues(alpha: 0.2)),
                              child: Center(child: Text('${e.key + 1}', style: TextStyle(color: _result!.severity.color, fontWeight: FontWeight.bold, fontSize: 11))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(e.value, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
                // AI specialty routing chip
                if (_result!.aiRecommendedSpecialty != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_hospital_rounded, color: Colors.cyanAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI-recommended hospital specialty: '
                            '${_result!.aiRecommendedSpecialty!.toUpperCase()}  '
                            '· confidence ${_result!.confidence}',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_result!.aiRecommendedSpecialty != null) const SizedBox(height: 12),

                // Attach-to-incident action (only shown when called from an
                // active incident context). This is the demo moment where AI
                // triage visibly drives hospital chain reshuffling.
                if (widget.incidentId != null) ...[
                  ElevatedButton.icon(
                    onPressed: _attaching ? null : _attachTriageToIncident,
                    icon: _attaching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(_attaching ? 'Attaching…' : 'ATTACH AI TRIAGE TO INCIDENT',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.shade700,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  if (_attachSuccessMsg != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_attachSuccessMsg!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],

                AiAdvisoryBanner.triage(),
                const SizedBox(height: 16),
                // Scan Again
                OutlinedButton.icon(
                  onPressed: () => setState(() { _imageBytes = null; _result = null; }),
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                  label: const Text('SCAN ANOTHER', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ],
          ),
        ),
    );
  }
}
