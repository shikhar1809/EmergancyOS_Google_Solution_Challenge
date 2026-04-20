import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shared_situation_brief_card.dart';

/// Shown after an incident is marked resolved.
/// Captures structured post-incident data that feeds the real leaderboard.
class PostIncidentReportScreen extends StatefulWidget {
  final String incidentId;
  const PostIncidentReportScreen({super.key, required this.incidentId});

  @override
  State<PostIncidentReportScreen> createState() => _PostIncidentReportScreenState();
}

class _PostIncidentReportScreenState extends State<PostIncidentReportScreen> {
  final _formKey = GlobalKey<FormState>();
  String _firstAidGiven = '';
  String _victimCondition = 'Stable';
  String _emsArrivalTime = '';
  String _additionalNotes = '';
  bool _saving = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() => _saving = true);

    try {
      await FirebaseFirestore.instance
          .collection('incidents')
          .doc(widget.incidentId)
          .update({
        'hasReport': true,
        'resolvedAt': Timestamp.now(),
        'report': {
          'firstAidGiven': _firstAidGiven,
          'victimCondition': _victimCondition,
          'emsArrivalTime': _emsArrivalTime,
          'additionalNotes': _additionalNotes,
          'submittedAt': Timestamp.now(),
        },
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Report submitted. Your save has been recorded!'),
            backgroundColor: AppColors.primarySafe,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  InputDecoration _inputDecor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white60),
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('POST-INCIDENT REPORT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // AI Situation Brief — shown read-only so the responding volunteer
              // can see the Gemini-generated debrief as part of their closing report.
              SharedSituationBriefCard(
                incidentId: widget.incidentId,
                accentColor: AppColors.primarySafe,
                compact: false,
                showRefreshButton: false,
              ),
              const SizedBox(height: 4),

              // Header Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 28),
                decoration: BoxDecoration(
                  color: AppColors.primarySafe.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primarySafe.withValues(alpha: 0.4)),
                ),
                child: const Column(children: [
                  Icon(Icons.assignment_turned_in_rounded, color: AppColors.primarySafe, size: 36),
                  SizedBox(height: 10),
                  Text('Incident Resolved', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('Complete this report to log your save and help improve emergency response data.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
                ]),
              ),

              const Text('First Aid Given', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _inputDecor('e.g. CPR, bleeding controlled, immobilised spine...'),
                onSaved: (v) => _firstAidGiven = v ?? '',
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              const Text('Victim Condition on Handover', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _victimCondition,
                dropdownColor: AppColors.surfaceHighlight,
                decoration: _inputDecor(''),
                style: const TextStyle(color: Colors.white),
                items: ['Stable', 'Critical — Alive', 'Deceased', 'Unknown / Transported']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setState(() => _victimCondition = v!),
              ),
              const SizedBox(height: 20),

              const Text('EMS Arrival Time (approx.)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecor('e.g. 8 mins, still awaiting...'),
                onSaved: (v) => _emsArrivalTime = v ?? 'N/A',
              ),
              const SizedBox(height: 20),

              const Text('Additional Notes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: _inputDecor('Hazards, complications, other responders...'),
                onSaved: (v) => _additionalNotes = v ?? '',
              ),
              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded, color: Colors.white),
                  label: Text(_saving ? 'Submitting...' : 'SUBMIT REPORT',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primarySafe,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
