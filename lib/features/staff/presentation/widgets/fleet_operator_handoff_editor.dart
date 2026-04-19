import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../services/fleet_operator_handoff_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

const int _kMaxHandoffPhotos = 8;

/// Preview + "Edit handoff report" for the fleet operator Handoff tab.
class FleetOperatorHandoffSection extends StatelessWidget {
  const FleetOperatorHandoffSection({
    super.key,
    required this.incidentId,
    required this.operatorUid,
  });

  final String incidentId;
  final String operatorUid;

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
            (draft.notesText.isNotEmpty || draft.photoUrls.isNotEmpty);

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
              label: Text(context.opsTr('Edit handoff report'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
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

  Future<void> _openEditor(BuildContext context, FleetOperatorHandoffDraft? initial) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FleetOperatorHandoffEditorSheet(
        incidentId: incidentId,
        operatorUid: operatorUid,
        initial: initial,
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
  late final TextEditingController _notes = TextEditingController(text: widget.initial?.notesText ?? '');
  final List<String> _photoUrls = [];
  var _saving = false;
  var _uploading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _photoUrls.addAll(widget.initial!.photoUrls);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    if (_photoUrls.length >= _kMaxHandoffPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $_kMaxHandoffPhotos photos.')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1600,
      );
      if (picked == null) {
        if (mounted) setState(() => _uploading = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final name = picked.name;
      final url = await FleetOperatorHandoffService.uploadPhoto(
        widget.incidentId,
        widget.operatorUid,
        bytes,
        name.isNotEmpty ? name : 'photo.jpg',
      );
      if (mounted) {
        setState(() {
          if (_photoUrls.length < _kMaxHandoffPhotos) _photoUrls.add(url);
          _uploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo failed: $e'), backgroundColor: Colors.red.shade900),
        );
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await FleetOperatorHandoffService.saveDraft(
        widget.incidentId,
        widget.operatorUid,
        notesText: _notes.text.trim(),
        photoUrls: List<String>.from(_photoUrls),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.opsTr('Handoff report saved')),
            backgroundColor: Color(0xFF238636),
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(context.opsTr('Edit handoff report'), style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(context.opsTr('Notes for receiving physician / hospital. Photos are stored securely for this incident.'), style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notes,
              maxLines: 8,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              decoration: InputDecoration(
                hintText: context.opsTr('Situation, background, assessment, recommendation…'),
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photoUrls.length; i++)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _photoUrls[i],
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -4,
                        right: -4,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() => _photoUrls.removeAt(i)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_uploading ? 'Uploading…' : 'Attach photos'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF58A6FF)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF238636),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.opsTr('Save'), style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
