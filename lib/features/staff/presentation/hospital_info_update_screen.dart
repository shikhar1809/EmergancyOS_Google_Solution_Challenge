import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/admin_panel_access.dart';
import '../../../services/ops_hospital_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Hospital capacity editor — Medical sees only the hospital bound by their code; Master sees all.
class HospitalInfoUpdateScreen extends StatefulWidget {
  const HospitalInfoUpdateScreen({super.key, required this.access});

  final AdminPanelAccess access;

  @override
  State<HospitalInfoUpdateScreen> createState() => _HospitalInfoUpdateScreenState();
}

class _HospitalInfoUpdateScreenState extends State<HospitalInfoUpdateScreen> {
  @override
  Widget build(BuildContext context) {
    final bound = (widget.access.boundHospitalDocId ?? '').trim();
    final scopeNote = widget.access.role == AdminConsoleRole.medical
        ? (bound.isEmpty ? 'Medical console: no hospital ID bound to this session.' : 'Updating: $bound')
        : 'All hospitals (master)';

    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(
              'Hospital information',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              scopeNote,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder(
              stream: OpsHospitalService.watchHospitals(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('${snap.error}', style: const TextStyle(color: Colors.white54)),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
                }
                var rows = snap.data!;
                if (widget.access.role == AdminConsoleRole.medical) {
                  final id = bound;
                  if (id.isEmpty) {
                    rows = [];
                  } else {
                    rows = rows.where((r) => r.id == id).toList();
                  }
                }
                if (rows.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hospital rows for your scope.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _HospitalEditorCard(row: rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HospitalEditorCard extends StatefulWidget {
  const _HospitalEditorCard({required this.row});

  final OpsHospitalRow row;

  @override
  State<_HospitalEditorCard> createState() => _HospitalEditorCardState();
}

const _kCommonServices = <String>[
  'trauma',
  'cardiology',
  'icu',
  'surgery',
  'orthopedics',
  'burns',
  'ent',
  'pediatrics',
  'blood_bank',
  'neurology',
];

String _serviceChipLabel(String id) {
  switch (id) {
    case 'icu':
      return 'ICU';
    case 'ent':
      return 'ENT';
    case 'blood_bank':
      return 'Blood bank';
    default:
      if (id.isEmpty) return id;
      return id[0].toUpperCase() + id.substring(1);
  }
}

class _HospitalEditorCardState extends State<_HospitalEditorCard> {
  late final TextEditingController _avail;
  late final TextEditingController _total;
  late final TextEditingController _note;
  late Set<String> _selectedServices;
  late bool _hasBloodBank;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _avail = TextEditingController(text: '${r.bedsAvailable}');
    _total = TextEditingController(text: '${r.bedsTotal}');
    _note = TextEditingController(text: r.traumaBedsNote ?? '');
    _selectedServices = Set<String>.from(r.offeredServices);
    _hasBloodBank = r.hasBloodBank;
  }

  @override
  void dispose() {
    _avail.dispose();
    _total.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = int.tryParse(_avail.text.trim()) ?? 0;
    final t = int.tryParse(_total.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      await OpsHospitalService.updateBedsAndServices(
        id: widget.row.id,
        bedsAvailable: a,
        bedsTotal: t,
        traumaBedsNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
        offeredServices: _selectedServices.toList(),
        hasBloodBank: _hasBloodBank,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.opsTr('Hospital row updated'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final df = DateFormat('MMM d, yyyy HH:mm');
    return Card(
      color: AppColors.slate800,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            Text(
              '${r.region} · last update ${df.format(r.updatedAt.toLocal())}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _avail,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _deco('Beds available'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _total,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _deco('Beds total'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              decoration: _deco('Trauma / notes (optional)'),
            ),
            const SizedBox(height: 16),
            Text(context.opsTr('Offered services'), style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kCommonServices.map((id) {
                final selected = _selectedServices.contains(id);
                return FilterChip(
                  label: Text(_serviceChipLabel(id)),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedServices.add(id);
                      } else {
                        _selectedServices.remove(id);
                      }
                    });
                  },
                  selectedColor: AppColors.accentBlue.withValues(alpha: 0.35),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12,
                  ),
                  side: BorderSide(color: selected ? AppColors.accentBlue : Colors.white24),
                  backgroundColor: AppColors.slate900,
                );
              }).toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.opsTr('Has blood bank on-site'), style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              value: _hasBloodBank,
              onChanged: (v) => setState(() => _hasBloodBank = v),
              activeThumbColor: AppColors.accentBlue,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentBlue),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(context.opsTr('Save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: AppColors.slate900,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );
}
