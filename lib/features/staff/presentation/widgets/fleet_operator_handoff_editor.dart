import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/fleet_operator_handoff_service.dart';
import '../../../../services/situation_brief_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

const int _kMaxHandoffPhotos = 8;

class FleetOperatorHandoffSection extends StatelessWidget {
  const FleetOperatorHandoffSection({
    super.key,
    required this.incidentId,
    required this.operatorUid,
    this.viewOnly = false,
  });

  final String incidentId;
  final String operatorUid;
  final bool viewOnly;

  @override
  Widget build(BuildContext context) {
    final uid = operatorUid.trim();
    final iid = incidentId.trim();
    if (uid.isEmpty || iid.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<FleetOperatorHandoffDraft?>(
      stream: FleetOperatorHandoffService.watchDraft(iid, uid),
      builder: (context, snap) {
        final draft = snap.data;
        final hasContent = draft != null &&
            (draft.notesText.isNotEmpty || draft.photoUrls.isNotEmpty || draft.v2Data.isNotEmpty);

        if (viewOnly) {
          if (!hasContent) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.slate800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'No handoff report submitted yet.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            );
          }
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.slate800,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_hospital_rounded, color: Color(0xFF7EE787), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'EMS Physician Handoff',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (draft?.notesText.isNotEmpty == true) ...[
                  Text(draft!.notesText, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                ],
                if (draft?.v2Data.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _buildV2DataView(draft!.v2Data),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () => _openEditor(context, draft),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.edit_note_rounded, size: 22),
              label: Text(context.opsTr('Edit handoff report'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            if (hasContent) ...[
              const SizedBox(height: 12),
              _HandoffDraftPreview(draft: draft),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildV2DataView(Map<String, dynamic> v2Data) {
    final List<Widget> items = [];
    v2Data.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        items.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$key: ', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
              Expanded(child: Text(value.toString(), style: const TextStyle(color: Colors.white70, fontSize: 11))),
            ],
          ),
        ));
      }
    });
    return Column(children: items);
  }

  Future<void> _openEditor(BuildContext context, FleetOperatorHandoffDraft? initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent,
        body: _FleetOperatorHandoffEditorSheet(
          incidentId: incidentId,
          operatorUid: operatorUid,
          initial: initial,
        ),
      ),
    );
  }
}

class _HandoffDraftPreview extends StatelessWidget {
  const _HandoffDraftPreview({required this.draft});

  final FleetOperatorHandoffDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.opsTr('Your handoff notes'), style: TextStyle(
              color: Color(0xFF79C0FF),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (draft.updatedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Updated: ${draft.updatedAt!.toLocal()}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
          if (draft.notesText.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              draft.notesText,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ],
          if (draft.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in draft.photoUrls)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      u,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: Colors.white12,
                        child: const Icon(Icons.broken_image, color: Colors.white38),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (draft.v2Data.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('STRUCTURED HANDOFF', style: TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (draft.v2Data['incidentType'] != null && draft.v2Data['incidentType'].toString().isNotEmpty)
                    Text('Type: ${draft.v2Data['incidentType']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  if (draft.v2Data['complaintText'] != null && draft.v2Data['complaintText'].toString().isNotEmpty)
                    Text('Complaint: ${draft.v2Data['complaintText']} (${draft.v2Data['onset']} onset)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 8),
                  const Text('Vitals:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    'BP ${draft.v2Data['bp']} | SpO2 ${draft.v2Data['spo2']} | HR ${draft.v2Data['pulse']} | RR ${draft.v2Data['rr']} | GCS ${draft.v2Data['gcs']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text('Consciousness:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    'AVPU: ${draft.v2Data['avpu']} | Pupils: ${draft.v2Data['pupils']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text('Interventions:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    [
                      if (draft.v2Data['o2Given'] == true) 'O2',
                      if (draft.v2Data['ivAccess'] == true) 'IV',
                      if (draft.v2Data['medsGiven'] == true) 'Meds',
                      if (draft.v2Data['cprGiven'] == true) 'CPR',
                      if (draft.v2Data['immobilisation'] == true) 'Immobilisation',
                      if (draft.v2Data['noInterventions'] == true) 'None',
                    ].join(', '),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text('Destination & Trend:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    'Trend: ${draft.v2Data['trend']} | Alert: ${draft.v2Data['alertHosp']}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FleetOperatorHandoffEditorSheet extends StatefulWidget {
  const _FleetOperatorHandoffEditorSheet({
    required this.incidentId,
    required this.operatorUid,
    this.initial,
  });

  final String incidentId;
  final String operatorUid;
  final FleetOperatorHandoffDraft? initial;

  @override
  State<_FleetOperatorHandoffEditorSheet> createState() => _FleetOperatorHandoffEditorSheetState();
}

class _FleetOperatorHandoffEditorSheetState extends State<_FleetOperatorHandoffEditorSheet> {
  // Step 1: Scene & call
  String _incidentType = '';
  bool _pickupNoted = false;
  bool _sceneSafe = false;

  // Step 2: Vitals
  final _bpCtrl = TextEditingController();
  final _spo2Ctrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _rrCtrl = TextEditingController();
  final _gcsCtrl = TextEditingController();
  final _painCtrl = TextEditingController();

  // Step 3: Consciousness
  String _avpu = '';
  String _pupils = '';

  // Step 4: Chief Complaint
  bool _complaintSpoken = false;
  final _complaintCtrl = TextEditingController();
  String _onset = '';

  // Step 5: Interventions
  bool _o2Given = false;
  bool _ivAccess = false;
  bool _medsGiven = false;
  bool _cprGiven = false;
  bool _immobilisation = false;
  bool _noInterventions = false;

  // Step 6: Trend & handoff flag
  String _trend = '';
  String _alertHosp = '';

  int _expandedIndex = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromDraft();
  }

  void _loadFromDraft() {
    final cur = widget.initial;
    if (cur == null || cur.v2Data.isEmpty) return;
    final d = cur.v2Data;
    _incidentType = d['incidentType'] ?? '';
    _pickupNoted = d['pickupNoted'] ?? false;
    _sceneSafe = d['sceneSafe'] ?? false;
    _bpCtrl.text = d['bp'] ?? '';
    _spo2Ctrl.text = d['spo2'] ?? '';
    _pulseCtrl.text = d['pulse'] ?? '';
    _rrCtrl.text = d['rr'] ?? '';
    _gcsCtrl.text = d['gcs'] ?? '';
    _painCtrl.text = d['pain'] ?? '';
    _avpu = d['avpu'] ?? '';
    _pupils = d['pupils'] ?? '';
    _complaintSpoken = d['complaintSpoken'] ?? false;
    _complaintCtrl.text = d['complaintText'] ?? '';
    _onset = d['onset'] ?? '';
    _o2Given = d['o2Given'] ?? false;
    _ivAccess = d['ivAccess'] ?? false;
    _medsGiven = d['medsGiven'] ?? false;
    _cprGiven = d['cprGiven'] ?? false;
    _immobilisation = d['immobilisation'] ?? false;
    _noInterventions = d['noInterventions'] ?? false;
    _trend = d['trend'] ?? '';
    _alertHosp = d['alertHosp'] ?? '';
  }

  int get _sectionsDone {
    int count = 0;
    if (_incidentType.isNotEmpty) count++;
    int vitalsCount = 0;
    if (_bpCtrl.text.isNotEmpty) vitalsCount++;
    if (_spo2Ctrl.text.isNotEmpty) vitalsCount++;
    if (_pulseCtrl.text.isNotEmpty) vitalsCount++;
    if (_rrCtrl.text.isNotEmpty) vitalsCount++;
    if (_gcsCtrl.text.isNotEmpty) vitalsCount++;
    if (_painCtrl.text.isNotEmpty) vitalsCount++;
    if (vitalsCount >= 3) count++;
    if (_avpu.isNotEmpty && _pupils.isNotEmpty) count++;
    if (_complaintCtrl.text.isNotEmpty && _onset.isNotEmpty) count++;
    if (_o2Given || _ivAccess || _medsGiven || _cprGiven || _immobilisation || _noInterventions) count++;
    if (_trend.isNotEmpty && _alertHosp.isNotEmpty) count++;
    return count;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final v2Data = <String, dynamic>{
        'incidentType': _incidentType,
        'pickupNoted': _pickupNoted,
        'sceneSafe': _sceneSafe,
        'bp': _bpCtrl.text.trim(),
        'spo2': _spo2Ctrl.text.trim(),
        'pulse': _pulseCtrl.text.trim(),
        'rr': _rrCtrl.text.trim(),
        'gcs': _gcsCtrl.text.trim(),
        'pain': _painCtrl.text.trim(),
        'avpu': _avpu,
        'pupils': _pupils,
        'complaintSpoken': _complaintSpoken,
        'complaintText': _complaintCtrl.text.trim(),
        'onset': _onset,
        'o2Given': _o2Given,
        'ivAccess': _ivAccess,
        'medsGiven': _medsGiven,
        'cprGiven': _cprGiven,
        'immobilisation': _immobilisation,
        'noInterventions': _noInterventions,
        'trend': _trend,
        'alertHosp': _alertHosp,
      };

      await FleetOperatorHandoffService.saveDraft(
        widget.incidentId,
        widget.operatorUid,
        notesText: '',
        photoUrls: widget.initial?.photoUrls ?? [],
        v2Data: v2Data,
      );

      final summary = '$_incidentType incident. ${_complaintCtrl.text.trim().isNotEmpty ? _complaintCtrl.text.trim() : "Complaint not listed"} ($_onset onset). Vitals: BP ${_bpCtrl.text}, SpO2 ${_spo2Ctrl.text}. Trend: $_trend. Alerting $_alertHosp.';

      if (mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF161B22),
            title: const Text('Verbal Handoff Summary', style: TextStyle(color: Colors.white)),
            content: Text(summary, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildProgressBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 80, top: 8),
            child: Column(
              children: [
                _buildSection(0, '1', 'Scene & call', _buildScene()),
                _buildSection(1, '2', 'Vitals on contact', _buildVitals()),
                _buildSection(2, '3', 'Consciousness & response', _buildConsciousness()),
                _buildSection(3, '4', 'Chief complaint', _buildComplaint()),
                _buildSection(4, '5', 'Interventions done', _buildInterventions()),
                _buildSection(5, '6', 'Trend & handoff flag', _buildTrend()),
              ],
            ),
          ),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildProgressBar() {
    final progress = _sectionsDone / 6.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_sectionsDone of 6 sections done', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white12,
            color: Colors.blueAccent,
            minHeight: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildSection(int index, String numBadge, String title, Widget content) {
    final isExpanded = _expandedIndex == index;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('section_$index'),
        initiallyExpanded: isExpanded,
        onExpansionChanged: (b) {
          if (b) setState(() => _expandedIndex = index);
        },
        leading: CircleAvatar(
          radius: 12,
          backgroundColor: Colors.white24,
          child: Text(numBadge, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildScene() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Incident type', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Trauma', 'Cardiac', 'Neuro', 'Respiratory', 'OB', 'Other'].map((t) {
            return ChoiceChip(
              label: Text(t, style: const TextStyle(color: Colors.white)),
              selectedColor: Colors.blue.withValues(alpha: 0.3),
              selected: _incidentType == t,
              onSelected: (val) => setState(() => _incidentType = val ? t : ''),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pickup location noted', style: TextStyle(color: Colors.white70)),
          value: _pickupNoted,
          onChanged: (v) => setState(() => _pickupNoted = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Scene safe / hazards noted', style: TextStyle(color: Colors.white70)),
          value: _sceneSafe,
          onChanged: (v) => setState(() => _sceneSafe = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _buildVitals() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.5,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _vitalField('BP (mmHg)', _bpCtrl),
        _vitalField('SpO2 (%)', _spo2Ctrl),
        _vitalField('Pulse (bpm)', _pulseCtrl),
        _vitalField('RR (breaths/min)', _rrCtrl),
        _vitalField('GCS (3-15)', _gcsCtrl),
        _vitalField('Pain (0-10)', _painCtrl),
      ],
    );
  }

  Widget _vitalField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: Colors.white12,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildConsciousness() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('AVPU', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Alert', 'Voice', 'Pain', 'Unresponsive'].map((t) {
            return ChoiceChip(
              label: Text(t, style: const TextStyle(color: Colors.white)),
              selectedColor: Colors.blue.withValues(alpha: 0.3),
              selected: _avpu == t,
              onSelected: (val) => setState(() => _avpu = val ? t : ''),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('Pupils', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['PEARL', 'Unequal', 'Fixed & dilated', 'Pinpoint'].map((t) {
            return ChoiceChip(
              label: Text(t, style: const TextStyle(color: Colors.white)),
              selectedColor: Colors.blue.withValues(alpha: 0.3),
              selected: _pupils == t,
              onSelected: (val) => setState(() => _pupils = val ? t : ''),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildComplaint() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Patient / bystander spoken to', style: TextStyle(color: Colors.white70)),
          value: _complaintSpoken,
          onChanged: (v) => setState(() => _complaintSpoken = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _complaintCtrl,
          maxLines: 2,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'e.g. chest pain since 20 mins, radiating to left arm',
            hintStyle: const TextStyle(color: Colors.white38),
            labelText: 'Complaint in brief',
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: Colors.white12,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Onset', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Sudden', 'Gradual', 'Unknown'].map((t) {
            return ChoiceChip(
              label: Text(t, style: const TextStyle(color: Colors.white)),
              selectedColor: Colors.blue.withValues(alpha: 0.3),
              selected: _onset == t,
              onSelected: (val) => setState(() => _onset = val ? t : ''),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInterventions() {
    return Column(
      children: [
        _interventionCheck('O2 given', _o2Given, (v) => setState(() => _o2Given = v)),
        _interventionCheck('IV access secured', _ivAccess, (v) => setState(() => _ivAccess = v)),
        _interventionCheck('Medication administered', _medsGiven, (v) => setState(() => _medsGiven = v)),
        _interventionCheck('CPR / defib performed', _cprGiven, (v) => setState(() => _cprGiven = v)),
        _interventionCheck('Immobilisation / splinting', _immobilisation, (v) => setState(() => _immobilisation = v)),
        _interventionCheck('No interventions needed', _noInterventions, (v) => setState(() => _noInterventions = v)),
      ],
    );
  }

  Widget _interventionCheck(String title, bool val, Function(bool) onChanged) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      value: val,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildTrend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Patient trend en route', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Improving', 'Stable', 'Deteriorating'].map((t) {
            return ChoiceChip(
              label: Text(t, style: const TextStyle(color: Colors.white)),
              selectedColor: Colors.blue.withValues(alpha: 0.3),
              selected: _trend == t,
              onSelected: (val) => setState(() => _trend = val ? t : ''),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text('Alert receiving hospital', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ['Cath lab', 'Trauma bay', 'ICU', 'General ER'].map((t) {
            return ChoiceChip(
              label: Text(t, style: const TextStyle(color: Colors.white)),
              selectedColor: Colors.blue.withValues(alpha: 0.3),
              selected: _alertHosp == t,
              onSelected: (val) => setState(() => _alertHosp = val ? t : ''),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final isComplete = _sectionsDone >= 4;
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF0D1117),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isComplete)
              Text(
                'Complete at least 4 sections. Partial handoffs are valid.',
                style: TextStyle(color: Colors.orange.shade300, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: isComplete ? const Color(0xFF238636) : Colors.blue.shade700,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          isComplete ? 'Submit Handoff Report' : 'Submit Partial Handoff',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sections completed: $_sectionsDone / 6',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
