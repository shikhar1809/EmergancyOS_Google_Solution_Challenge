import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/leaderboard_service.dart';

class VolunteerDetailsScreen extends ConsumerStatefulWidget {
  const VolunteerDetailsScreen({super.key});

  @override
  ConsumerState<VolunteerDetailsScreen> createState() =>
      _VolunteerDetailsScreenState();
}

class _VolunteerDetailsScreenState
    extends ConsumerState<VolunteerDetailsScreen> {
  bool _cprCertified = false;
  bool _aedCertified = false;
  bool _uploadingCprCert = false;
  bool _uploadingAedCert = false;
  final bool _emergencyBridgeDesk = false;
  bool _isSaving = false;

  String _contentTypeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _pickAndUploadCert(String certType) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final l = AppLocalizations.of(context);
    if (certType == 'cpr' ? _uploadingCprCert : _uploadingAedCert) return;

    setState(() {
      if (certType == 'cpr')
        _uploadingCprCert = true;
      else
        _uploadingAedCert = true;
    });

    try {
      final picker = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      if (!mounted) return;
      if (picker == null || picker.files.isEmpty) {
        setState(() {
          if (certType == 'cpr')
            _uploadingCprCert = false;
          else
            _uploadingAedCert = false;
        });
        return;
      }
      final f = picker.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.profileCertUploadNoBytes),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final rawName = f.name.trim().isEmpty ? 'certificate' : f.name.trim();
      final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final dot = safeName.lastIndexOf('.');
      final ext = dot >= 0 ? safeName.substring(dot + 1) : 'jpg';
      final contentType = _contentTypeForExtension(ext);
      if (contentType == 'application/octet-stream') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.profileCertUploadNoBytes),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final path =
          'volunteer_certifications/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('volunteer_cert_uploads')
          .add({
            'userId': user.uid,
            'userEmail': user.email ?? '',
            'displayName': user.displayName ?? '',
            'certType': certType,
            'storagePath': path,
            'downloadUrl': url,
            'fileName': rawName,
            'contentType': contentType,
            'uploadedAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.profileCertUploaded),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Cert upload error: $e');
      if (mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.profileCertUploadFailed('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (certType == 'cpr')
            _uploadingCprCert = false;
          else
            _uploadingAedCert = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final l = AppLocalizations.of(context);
    final responseAsync = ref.watch(myResponseCountProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l.profileTabVolunteerHub),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(
                Icons.check_rounded,
                color: AppColors.primaryDanger,
              ),
              onPressed: () async {
                setState(() => _isSaving = true);
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .set({
                        'cprCertified': _cprCertified,
                        'aedCertified': _aedCertified,
                        'emergencyBridgeDesk': _emergencyBridgeDesk,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                  await FirebaseFirestore.instance
                      .collection('volunteers')
                      .doc(user?.uid)
                      .set({
                        'cprCertified': _cprCertified,
                        'aedCertified': _aedCertified,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.profileSavedMsg),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.profileSaveError('$e')),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isSaving = false);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (user != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snap) {
                return _buildVolunteerStatsCard(
                  l,
                  snap.data?.data(),
                  responseAsync,
                );
              },
            )
          else
            _buildVolunteerStatsCard(l, null, responseAsync),
          const SizedBox(height: 12),
          _buildCard(
            icon: Icons.verified_rounded,
            title: l.profileVolunteerCertificationsTitle,
            children: [
              Text(
                l.profileVolunteerCertificationsSubtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l.profileCprCertifiedTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  l.profileCprCertifiedSubtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _cprCertified,
                activeColor: AppColors.primaryDanger,
                onChanged: (v) => setState(() => _cprCertified = v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _uploadingCprCert
                      ? null
                      : () => _pickAndUploadCert('cpr'),
                  icon: _uploadingCprCert
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(
                          Icons.upload_file_rounded,
                          color: AppColors.primaryInfo,
                        ),
                  label: Text(
                    _uploadingCprCert
                        ? l.profileCertUploading
                        : l.profileUploadCprCert,
                    style: const TextStyle(
                      color: AppColors.primaryInfo,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Divider(height: 24, color: Colors.white12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  l.profileAedCertifiedTitle,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: Text(
                  l.profileAedCertifiedSubtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _aedCertified,
                activeColor: AppColors.primaryDanger,
                onChanged: (v) => setState(() => _aedCertified = v),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _uploadingAedCert
                      ? null
                      : () => _pickAndUploadCert('aed'),
                  icon: _uploadingAedCert
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white70,
                          ),
                        )
                      : const Icon(
                          Icons.upload_file_rounded,
                          color: AppColors.primaryInfo,
                        ),
                  label: Text(
                    _uploadingAedCert
                        ? l.profileCertUploading
                        : l.profileUploadAedCert,
                    style: const TextStyle(
                      color: AppColors.primaryInfo,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildVolunteerStatsCard(
    AppLocalizations l,
    Map<String, dynamic>? d,
    AsyncValue<int> responseAsync,
  ) {
    final lives = (d?['volunteerLivesSaved'] as num?)?.toInt() ?? 0;
    final xp = (d?['volunteerXp'] as num?)?.toInt() ?? 0;
    final lastTs = d?['lastVolunteerResponseAt'];
    final lastId = (d?['lastVolunteerIncidentId'] as String?)?.trim() ?? '';
    final lastTimeStr = lastTs != null
        ? _formatLastVolunteerResponse(l, lastTs)
        : l.profileStatNever;
    final incidentsStr = responseAsync.when(
      data: (n) => '$n',
      loading: () => l.profileLoading,
      error: (_, __) => l.profileError,
    );
    final xpFmt = NumberFormat.decimalPattern(l.locale.toString());

    String lastLine() {
      if (lastTimeStr == l.profileStatNever) return lastTimeStr;
      if (lastId.isEmpty) return lastTimeStr;
      final short = lastId.length > 10 ? '${lastId.substring(0, 8)}…' : lastId;
      return '$lastTimeStr · $short';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: Colors.amberAccent.shade200,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                l.profileVolunteerStatsTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.hail_rounded,
                  label: l.profileStatIncidentsResponded,
                  value: incidentsStr,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.favorite_rounded,
                  label: l.profileStatTotalLivesSaved,
                  value: '$lives',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.history_rounded,
                  label: l.profileStatLastIncident,
                  value: lastLine(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.auto_awesome_rounded,
                  label: l.profileStatValueCreated,
                  value: xpFmt.format(xp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.profileStatValueCreatedHint,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastVolunteerResponse(AppLocalizations l, dynamic ts) {
    if (ts == null) return l.profileStatNever;
    try {
      if (ts is Timestamp) {
        return DateFormat.yMMMd().add_jm().format(ts.toDate());
      }
      return l.profileStatNever;
    } catch (_) {
      return l.profileStatNever;
    }
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryDanger, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.tealAccent.shade100, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              height: 1.1,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
