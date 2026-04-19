import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:emergency_os/core/l10n/dashboard_l10n.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/incident_service.dart';
import '../domain/admin_panel_access.dart';
import '../domain/command_center_accent.dart';

/// Master console: [Approvals] certification queue + [Lookup] search, ban, certs, incidents, submissions.
class AdminVolunteersScreen extends StatefulWidget {
  const AdminVolunteersScreen({
    super.key,
    required this.access,
    this.embeddedInManagement = false,
  });

  final AdminPanelAccess access;

  /// When true (e.g. Management map workspace), omits the large page title block.
  final bool embeddedInManagement;

  @override
  State<AdminVolunteersScreen> createState() => _AdminVolunteersScreenState();
}

class _AdminVolunteersScreenState extends State<AdminVolunteersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Color get _accent => CommandCenterAccent.forRole(widget.access.role).primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.slate900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embeddedInManagement) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                children: [
                  Icon(Icons.person_rounded, color: _accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.opsTr('Volunteer Management'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                context.opsTr(
                  'Approvals: review uploaded certificates. Lookup: find any volunteer by UID or email, moderate, and inspect incidents & submissions.',
                ),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.embeddedInManagement) const SizedBox(height: 8),
          Material(
            color: AppColors.slate800,
            child: TabBar(
              controller: _tabs,
              labelColor: _accent,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(
                  text: 'Approvals',
                  icon: Icon(Icons.fact_check_outlined, size: 20),
                ),
                Tab(text: 'Lookup', icon: Icon(Icons.person_search, size: 20)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _VolunteerApprovalsTab(accent: _accent),
                _VolunteerLookupTab(accent: _accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared moderation ─────────────────────────────────────────────────────

Future<void> adminSetVolunteerBanned(
  BuildContext context,
  String userId,
  bool banned, {
  String? reason,
}) async {
  final admin = FirebaseAuth.instance.currentUser;
  if (admin == null) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'volunteerBanned': banned,
      'volunteerBannedAt': banned
          ? FieldValue.serverTimestamp()
          : FieldValue.delete(),
      'volunteerBannedReason': banned && (reason != null && reason.isNotEmpty)
          ? reason.trim()
          : FieldValue.delete(),
      'volunteerBannedByUid': banned ? admin.uid : FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            banned ? 'Volunteer suspended.' : 'Suspension cleared.',
          ),
          backgroundColor: banned
              ? Colors.orange.shade900
              : const Color(0xFF1B5E20),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }
}

Future<void> adminConfirmBan(
  BuildContext context,
  String userId,
  String label,
) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.slate800,
      title: Text(
        'Suspend volunteer?',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: context.opsTr('Reason (optional)'),
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.accentBlue),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(context.opsTr('Cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(context.opsTr('Suspend')),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await adminSetVolunteerBanned(context, userId, true, reason: ctrl.text);
  }
  ctrl.dispose();
}

Future<void> _openUrl(String url) async {
  final u = Uri.tryParse(url);
  if (u == null) return;
  if (await canLaunchUrl(u)) {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }
}

Future<void> _syncCertToVolunteersDoc(
  String userId, {
  bool? cpr,
  bool? aed,
}) async {
  final patch = <String, Object?>{'updatedAt': FieldValue.serverTimestamp()};
  if (cpr != null) patch['cprCertified'] = cpr;
  if (aed != null) patch['aedCertified'] = aed;
  try {
    await FirebaseFirestore.instance
        .collection('volunteers')
        .doc(userId)
        .set(patch, SetOptions(merge: true));
  } catch (_) {}
}

Future<void> _setUserCertFlags(String userId, {bool? cpr, bool? aed}) async {
  final patch = <String, Object?>{'updatedAt': FieldValue.serverTimestamp()};
  if (cpr != null) patch['cprCertified'] = cpr;
  if (aed != null) patch['aedCertified'] = aed;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .set(patch, SetOptions(merge: true));
  await _syncCertToVolunteersDoc(userId, cpr: cpr, aed: aed);
}

Future<void> _markUploadReviewed(
  String uploadDocId, {
  required String status,
  String? note,
}) async {
  final admin = FirebaseAuth.instance.currentUser;
  if (admin == null) return;
  await FirebaseFirestore.instance
      .collection('volunteer_cert_uploads')
      .doc(uploadDocId)
      .update({
        'reviewStatus': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedByUid': admin.uid,
        'reviewNote': note == null || note.isEmpty
            ? FieldValue.delete()
            : note.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

bool _uploadPendingReview(Map<String, dynamic> m) {
  final s = (m['reviewStatus'] as String?)?.toLowerCase().trim() ?? '';
  return s != 'approved' && s != 'rejected';
}

// ── Approvals tab ─────────────────────────────────────────────────────────

class _VolunteerApprovalsTab extends StatelessWidget {
  const _VolunteerApprovalsTab({required this.accent});

  final Color accent;

  Future<void> _approve(
    BuildContext context,
    String uploadId,
    Map<String, dynamic> m,
  ) async {
    final userId = (m['userId'] as String?) ?? '';
    final certType = (m['certType'] as String?)?.toLowerCase() ?? '';
    if (userId.isEmpty) return;
    try {
      if (certType == 'cpr') {
        await _setUserCertFlags(userId, cpr: true);
      } else if (certType == 'aed') {
        await _setUserCertFlags(userId, aed: true);
      }
      await _markUploadReviewed(uploadId, status: 'approved');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.opsTr('Approved — profile flags updated.')),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
      }
    }
  }

  Future<void> _reject(BuildContext context, String uploadId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(context.opsTr('Reject upload?'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 2,
          decoration: InputDecoration(
            labelText: context.opsTr('Note to log (optional)'),
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.opsTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.opsTr('Reject')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      try {
        await _markUploadReviewed(
          uploadId,
          status: 'rejected',
          note: ctrl.text,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(context.opsTr('Marked rejected.'))));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('volunteer_cert_uploads')
          .orderBy('uploadedAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Could not load uploads: ${snap.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accentBlue),
          );
        }
        final pending = snap.data!.docs
            .where((d) => _uploadPendingReview(d.data()))
            .toList();
        if (pending.isEmpty) {
          return const Center(
            child: Text(
              'No uploads awaiting review.\nNew CPR/AED files from Profile appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          itemCount: pending.length,
          separatorBuilder: (context, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = pending[i];
            final m = d.data();
            final userId = (m['userId'] as String?) ?? '';
            final certType = (m['certType'] as String?) ?? '';
            final fileName = (m['fileName'] as String?) ?? '';
            final url = (m['downloadUrl'] as String?) ?? '';
            final email = (m['userEmail'] as String?) ?? '';
            final dn = (m['displayName'] as String?) ?? '';
            final uploadedAt = m['uploadedAt'];
            String when = '—';
            if (uploadedAt is Timestamp) {
              when = uploadedAt.toDate().toLocal().toString().split('.').first;
            }

            if (userId.isEmpty) {
              return Material(
                color: AppColors.slate800,
                borderRadius: BorderRadius.circular(12),
                child: const ListTile(
                  title: Text(
                    'Invalid upload (missing user id)',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .snapshots(),
              builder: (context, userSnap) {
                final banned =
                    userSnap.data?.data()?['volunteerBanned'] == true;
                final cpr = userSnap.data?.data()?['cprCertified'] == true;
                final aed = userSnap.data?.data()?['aedCertified'] == true;

                return Material(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(context.opsTr('NEEDS REVIEW'), style: TextStyle(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: certType == 'aed'
                                    ? Colors.teal.withValues(alpha: 0.2)
                                    : Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                certType.toUpperCase(),
                                style: TextStyle(
                                  color: certType == 'aed'
                                      ? Colors.tealAccent
                                      : Colors.redAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (banned) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(context.opsTr('SUSPENDED'), style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              when,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          dn.isNotEmpty
                              ? dn
                              : (email.isNotEmpty ? email : userId),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        if (email.isNotEmpty && dn.isNotEmpty)
                          Text(
                            email,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        Text(
                          'UID: $userId',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'Profile flags: CPR ${cpr ? "✓" : "—"} · AED ${aed ? "✓" : "—"}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 11,
                          ),
                        ),
                        if (fileName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              fileName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (url.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () => _openUrl(url),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accent,
                                ),
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: Text(context.opsTr('Open file')),
                              ),
                            FilledButton.icon(
                              onPressed: banned
                                  ? null
                                  : () => _approve(context, d.id, m),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                              ),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(context.opsTr('Approve')),
                            ),
                            FilledButton.icon(
                              onPressed: () => _reject(context, d.id),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade900,
                              ),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: Text(context.opsTr('Reject')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ── Lookup tab ────────────────────────────────────────────────────────────

class _VolunteerLookupTab extends StatefulWidget {
  const _VolunteerLookupTab({required this.accent});

  final Color accent;

  @override
  State<_VolunteerLookupTab> createState() => _VolunteerLookupTabState();
}

class _VolunteerLookupTabState extends State<_VolunteerLookupTab> {
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _resolvedUid;
  Map<String, dynamic>? _userData;
  List<SosIncident> _incidents = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _feedbackDocs = [];
  bool _loadedDetail = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static final _uidPattern = RegExp(r'^[a-zA-Z0-9]{20,}$');

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      setState(() => _error = 'Enter a Firebase UID or email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _resolvedUid = null;
      _userData = null;
      _incidents = [];
      _feedbackDocs = [];
      _loadedDetail = false;
    });

    try {
      String? uid;

      if (_uidPattern.hasMatch(q)) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(q)
            .get();
        if (doc.exists) uid = doc.id;
      }

      if (uid == null) {
        var qs = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: q)
            .limit(5)
            .get();
        if (qs.docs.isEmpty) {
          qs = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: q.toLowerCase())
              .limit(5)
              .get();
        }
        if (qs.docs.isNotEmpty) uid = qs.docs.first.id;
      }

      if (uid == null) {
        final up = await FirebaseFirestore.instance
            .collection('volunteer_cert_uploads')
            .where('userEmail', isEqualTo: q)
            .limit(1)
            .get();
        if (up.docs.isNotEmpty) {
          final id = up.docs.first.data()['userId'] as String?;
          if (id != null && id.isNotEmpty) uid = id;
        }
      }

      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'No user found for that UID or email.';
        });
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data();

      final incMap = <String, SosIncident>{};
      Future<void> mergeCol(String col) async {
        for (final field in ['acceptedVolunteerIds', 'onSceneVolunteerIds']) {
          final snap = await FirebaseFirestore.instance
              .collection(col)
              .where(field, arrayContains: uid)
              .limit(35)
              .get();
          for (final d in snap.docs) {
            try {
              incMap[d.id] = SosIncident.fromFirestore(d);
            } catch (_) {}
          }
        }
      }

      await mergeCol('sos_incidents');
      await mergeCol('sos_incidents_archive');
      final incidents = incMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final incIds = incidents.map((e) => e.id).toList();
      final feedbackChunks = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var i = 0; i < incIds.length && i < 90; i += 30) {
        final end = i + 30 > incIds.length ? incIds.length : i + 30;
        final chunk = incIds.sublist(i, end);
        if (chunk.isEmpty) continue;
        final fb = await FirebaseFirestore.instance
            .collection('incident_feedback')
            .where('incidentId', whereIn: chunk)
            .limit(60)
            .get();
        feedbackChunks.addAll(fb.docs);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _resolvedUid = uid;
        _userData = data;
        _incidents = incidents;
        _feedbackDocs = feedbackChunks;
        _loadedDetail = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _revokeCert({required bool cpr, required bool aed}) async {
    final uid = _resolvedUid;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(context.opsTr('Revoke certification?'), style: TextStyle(color: Colors.white),
        ),
        content: Text(
          cpr && aed
              ? 'Clear CPR and AED flags on this profile.'
              : cpr
              ? 'Clear CPR flag.'
              : 'Clear AED flag.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.opsTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.opsTr('Revoke')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _setUserCertFlags(
        uid,
        cpr: cpr ? false : null,
        aed: aed ? false : null,
      );
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (mounted) {
        setState(() => _userData = snap.data());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Certification flags updated.'))),
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.opsTr('UID or email'),
                  labelStyle: const TextStyle(color: Colors.white54),
                  hintText: context.opsTr('Paste Firebase Auth UID or exact account email'),
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                  filled: true,
                  fillColor: AppColors.slate800,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  suffixIcon: IconButton(
                    tooltip: context.opsTr('Search'),
                    icon: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentBlue,
                            ),
                          )
                        : Icon(Icons.search, color: widget.accent),
                    onPressed: _loading ? null : _runSearch,
                  ),
                ),
                onSubmitted: (_) => _runSearch(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _runSearch,
              style: FilledButton.styleFrom(
                backgroundColor: widget.accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
              ),
              icon: const Icon(Icons.search),
              label: Text(context.opsTr('Search')),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        ],
        if (_loadedDetail && _resolvedUid != null) ...[
          const SizedBox(height: 20),
          _LookupProfileCard(
            uid: _resolvedUid!,
            data: _userData,
            accent: widget.accent,
            onSuspend: () => adminConfirmBan(
              context,
              _resolvedUid!,
              _userData?['email']?.toString() ?? _resolvedUid!,
            ),
            onLiftBan: () =>
                adminSetVolunteerBanned(context, _resolvedUid!, false),
            onRevokeCpr: () => _revokeCert(cpr: true, aed: false),
            onRevokeAed: () => _revokeCert(cpr: false, aed: true),
            onRevokeAllCerts: () => _revokeCert(cpr: true, aed: true),
          ),
          const SizedBox(height: 16),
          Text(
            'Incidents & submissions',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          if (_incidents.isEmpty)
            Text(context.opsTr('No incidents in active or archive collections for this UID.'), style: TextStyle(color: Colors.white38),
            )
          else
            ..._incidents
                .take(25)
                .map(
                  (inc) =>
                      _IncidentVolunteerTile(inc: inc, accent: widget.accent),
                ),
          if (_incidents.length > 25)
            Text(
              '+ ${_incidents.length - 25} more (trim list in a future export)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'Post-incident feedback (linked incidents)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          if (_feedbackDocs.isEmpty)
            Text(context.opsTr('No incident_feedback rows for the incidents above (anonymous payloads may omit submitter).'), style: TextStyle(color: Colors.white38, fontSize: 12),
            )
          else
            ..._feedbackDocs.map((d) => _FeedbackTile(doc: d)),
          const SizedBox(height: 20),
          Text(
            'Certification upload history',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('volunteer_cert_uploads')
                .where('userId', isEqualTo: _resolvedUid)
                .limit(40)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  '${snap.error}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentBlue,
                    ),
                  ),
                );
              }
              final docs = snap.data!.docs.toList()
                ..sort((a, b) {
                  final ta = a.data()['uploadedAt'];
                  final tb = b.data()['uploadedAt'];
                  if (ta is! Timestamp) return 1;
                  if (tb is! Timestamp) return -1;
                  return tb.compareTo(ta);
                });
              if (docs.isEmpty) {
                return Text(context.opsTr('No uploads for this user.'), style: TextStyle(color: Colors.white38),
                );
              }
              return Column(
                children: docs
                    .map(
                      (d) => ListTile(
                        dense: true,
                        tileColor: AppColors.slate800,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(
                          '${d.data()['certType']} · ${d.data()['reviewStatus'] ?? 'pending'}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          d.data()['fileName']?.toString() ?? '',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _LookupProfileCard extends StatelessWidget {
  const _LookupProfileCard({
    required this.uid,
    required this.data,
    required this.accent,
    required this.onSuspend,
    required this.onLiftBan,
    required this.onRevokeCpr,
    required this.onRevokeAed,
    required this.onRevokeAllCerts,
  });

  final String uid;
  final Map<String, dynamic>? data;
  final Color accent;
  final VoidCallback onSuspend;
  final VoidCallback onLiftBan;
  final VoidCallback onRevokeCpr;
  final VoidCallback onRevokeAed;
  final VoidCallback onRevokeAllCerts;

  @override
  Widget build(BuildContext context) {
    final banned = data?['volunteerBanned'] == true;
    final reason = (data?['volunteerBannedReason'] as String?) ?? '';
    final email = (data?['email'] as String?) ?? '';
    final cpr = data?['cprCertified'] == true;
    final aed = data?['aedCertified'] == true;
    final onDuty = data?['volunteerOnDuty'] == true;
    final xp = data?['volunteerXp'];
    final lives = data?['volunteerLivesSaved'];

    return Material(
      color: AppColors.slate800,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, color: accent, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Volunteer record',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (banned)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(context.opsTr('SUSPENDED'), style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              'UID: $uid',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (email.isNotEmpty)
              SelectableText(
                'Email: $email',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Text(
              'Certifications (profile): CPR ${cpr ? "yes" : "no"} · AED ${aed ? "yes" : "no"}',
              style: const TextStyle(color: Colors.tealAccent, fontSize: 13),
            ),
            Text(
              'On duty flag: $onDuty',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            if (xp != null || lives != null)
              Text(
                'XP: ${xp ?? "—"} · Lives saved field: ${lives ?? "—"}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            if (banned && reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Ban reason: $reason',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!banned)
                  FilledButton.icon(
                    onPressed: onSuspend,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                    ),
                    icon: const Icon(Icons.block, size: 18),
                    label: Text(context.opsTr('Suspend')),
                  )
                else
                  FilledButton.icon(
                    onPressed: onLiftBan,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(context.opsTr('Lift suspension')),
                  ),
                OutlinedButton.icon(
                  onPressed: cpr ? onRevokeCpr : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(context.opsTr('Revoke CPR flag')),
                ),
                OutlinedButton.icon(
                  onPressed: aed ? onRevokeAed : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                  ),
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(context.opsTr('Revoke AED flag')),
                ),
                OutlinedButton.icon(
                  onPressed: (cpr || aed) ? onRevokeAllCerts : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(context.opsTr('Revoke both')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncidentVolunteerTile extends StatelessWidget {
  const _IncidentVolunteerTile({required this.inc, required this.accent});

  final SosIncident inc;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scene = inc.volunteerSceneReport;
    final hasScene = scene != null && scene.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${inc.type} · ${inc.lifecyclePhaseLabel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                inc.timestamp.toLocal().toString().split('.').first,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            'ID: ${inc.id}',
            style: TextStyle(
              color: accent.withValues(alpha: 0.95),
              fontSize: 11,
            ),
          ),
          Text(
            'Accepted ${inc.acceptedVolunteerIds.length} · On-scene ${inc.onSceneVolunteerIds.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (hasScene) ...[
            const SizedBox(height: 8),
            Text(context.opsTr('On-scene submission (volunteerSceneReport)'), style: TextStyle(color: Colors.cyanAccent, fontSize: 11),
            ),
            const SizedBox(height: 4),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(scene),
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'No structured scene report on doc.',
                style: TextStyle(color: Colors.white30, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final role = m['submitterRole'] ?? '—';
    final helpful = m['helpful'];
    final comment = m['comment']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Incident ${m['incidentId']} · role $role · helpful $helpful',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (comment.isNotEmpty)
            Text(
              comment,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
