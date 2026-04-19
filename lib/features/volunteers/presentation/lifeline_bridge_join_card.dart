import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/ops_integration_routing_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/livekit_emergency_bridge_service.dart';

class LifelineBridgeJoinCard extends ConsumerStatefulWidget {
  const LifelineBridgeJoinCard({
    super.key,
    this.initialIncidentId,
    this.lockIncidentId = false,
    this.showJoinCalmDisclaimer = true,
  });

  final String? initialIncidentId;
  final bool lockIncidentId;
  /// When true, shows a calm-speech disclaimer before connecting.
  final bool showJoinCalmDisclaimer;

  @override
  ConsumerState<LifelineBridgeJoinCard> createState() => _LifelineBridgeJoinCardState();
}

String? _normalizeE164(String? phone) {
  if (phone == null) return null;
  final raw = phone.trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('+')) return raw;
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length < 8) return null;
  return '+$digits';
}

class _LifelineBridgeJoinCardState extends ConsumerState<LifelineBridgeJoinCard>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _incidentIdController;
  Room? _room;
  bool _busy = false;
  bool? _isEmergencyServicesDesk;
  bool? _eliteVolunteerBridge;
  bool _pttHeld = false;

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  final List<String> _participants = [];
  EventsListener<RoomEvent>? _roomListener;

  @override
  void initState() {
    super.initState();
    _incidentIdController =
        TextEditingController(text: widget.initialIncidentId?.trim() ?? '');
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _loadDeskFlag();
  }

  Future<void> _loadDeskFlag() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
      final data = doc.data() ?? {};
      final desk = data['emergencyBridgeDesk'] == true;
      final cleared = (data['lifelineLevelsCleared'] is num)
          ? (data['lifelineLevelsCleared'] as num).toInt()
          : 0;
      final xp = (data['volunteerXp'] is num)
          ? (data['volunteerXp'] as num).toInt()
          : 0;
      final lives = (data['volunteerLivesSaved'] is num)
          ? (data['volunteerLivesSaved'] as num).toInt()
          : 0;
      final elite = cleared >= 10 || (lives >= 5 && xp >= 1000);
      if (!context.mounted) return;
      setState(() {
        _isEmergencyServicesDesk = desk;
        _eliteVolunteerBridge = elite;
      });
    } catch (_) {
      if (context.mounted) {
        setState(() {
          _isEmergencyServicesDesk = false;
          _eliteVolunteerBridge = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _incidentIdController.dispose();
    _pulseCtrl.dispose();
    _roomListener?.dispose();
    if (_room != null) {
      unawaited(_room!.disconnect());
      unawaited(_room!.dispose());
    }
    super.dispose();
  }

  void _syncParticipants() {
    if (_room == null) return;
    final names = <String>[];
    for (final p in _room!.remoteParticipants.values) {
      final id = p.identity;
      final label = id.startsWith('vol_elite_')
          ? 'Volunteer'
          : id.startsWith('ems_')
              ? 'Dispatch'
              : id.startsWith('contact_')
                  ? 'Contact'
                  : id.startsWith('victim_')
                      ? 'Victim'
                      : id.startsWith('volunteer_')
                          ? 'Volunteer'
                          : id.contains('lifeline')
                          ? 'Assist'
                          : id;
      names.add(label);
    }
    if (context.mounted) {
      setState(() {
        _participants
          ..clear()
          ..addAll(names);
      });
    }
  }

  Future<void> _leave() async {
    if (_room == null) return;
    try {
      await _room!.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    if (context.mounted) setState(() => _pttHeld = false);
    _roomListener?.dispose();
    _roomListener = null;
    final r = _room!;
    _room = null;
    _participants.clear();
    await r.disconnect();
    await r.dispose();
    if (context.mounted) setState(() {});
  }

  Future<void> _join() async {
    final incidentId = _incidentIdController.text.trim();
    if (incidentId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).get('bridge_card_incident_id_missing'))),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _busy = true);
    try {
      final pttOnly =
          ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;
      if (pttOnly) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).get('bridge_card_ptt_only_snackbar'),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final effectiveRole = await _resolveJoinRoleForIncident();
      await _leave();
      final room = await LivekitEmergencyBridgeService.connectToEmergencyBridge(
        incidentId: incidentId,
        uid: uid,
        variant: 'dash',
        canPublishAudio: true,
        role: effectiveRole,
      );
      if (!context.mounted) {
        await room.disconnect();
        await room.dispose();
        return;
      }

      _roomListener = room.createListener();
      _roomListener!
        ..on<RoomConnectedEvent>((_) => _syncParticipants())
        ..on<ParticipantConnectedEvent>((_) => _syncParticipants())
        ..on<ParticipantDisconnectedEvent>((_) => _syncParticipants())
        ..on<TrackPublishedEvent>((_) => _syncParticipants())
        ..on<TrackSubscribedEvent>((_) => _syncParticipants());

      setState(() => _room = room);
      try {
        await room.localParticipant?.setMicrophoneEnabled(false);
      } catch (_) {}
      if (kIsWeb) {
        unawaited(room.startAudio());
      }
      _syncParticipants();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context).get('bridge_card_connected_snackbar')),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                AppLocalizations.of(context)
                    .get('bridge_card_could_not_join')
                    .replaceAll('{err}', '$e'),
              ),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (context.mounted) setState(() => _busy = false);
    }
  }

  /// Role is derived from profile flags and this incident (desk → dispatch; matching contact → contact; else volunteer tier).
  Future<LiveKitBridgeRole> _resolveJoinRoleForIncident() async {
    if (_isEmergencyServicesDesk == true) {
      return LiveKitBridgeRole.emergencyDesk;
    }
    final incidentId = _incidentIdController.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (incidentId.isNotEmpty && uid.isNotEmpty) {
      try {
        final incSnap = await FirebaseFirestore.instance
            .collection('sos_incidents')
            .doc(incidentId)
            .get();
        final inc = incSnap.data();
        if (inc != null) {
          final contactUid = (inc['emergencyContactUid'] ?? '').toString().trim();
          if (contactUid.isNotEmpty && contactUid == uid) {
            return LiveKitBridgeRole.emergencyContact;
          }
          final incPhone = _normalizeE164(inc['emergencyContactPhone'] as String?);
          final userSnap =
              await FirebaseFirestore.instance.collection('users').doc(uid).get();
          final u = userSnap.data() ?? {};
          final userPhone =
              _normalizeE164((u['contactPhone'] ?? u['phone']) as String?);
          if (incPhone != null &&
              userPhone != null &&
              incPhone == userPhone) {
            return LiveKitBridgeRole.emergencyContact;
          }
          final incEmail =
              (inc['emergencyContactEmail'] as String?)?.trim().toLowerCase();
          final authEmail =
              FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
          if (incEmail != null &&
              incEmail.isNotEmpty &&
              authEmail != null &&
              authEmail.isNotEmpty &&
              incEmail == authEmail) {
            return LiveKitBridgeRole.emergencyContact;
          }
        }
      } catch (_) {}
    }
    if (_eliteVolunteerBridge == true) {
      return LiveKitBridgeRole.volunteerElite;
    }
    return LiveKitBridgeRole.acceptedVolunteer;
  }

  Future<void> _pttDown() async {
    if (_room == null || _busy) return;
    setState(() => _pttHeld = true);
    try {
      await _room!.localParticipant?.setMicrophoneEnabled(true);
    } catch (_) {}
  }

  Future<void> _pttUp() async {
    if (_room == null) return;
    try {
      await _room!.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    if (context.mounted) setState(() => _pttHeld = false);
  }

  Future<void> _onJoinPressed() async {
    if (widget.showJoinCalmDisclaimer) {
      final l10n = AppLocalizations.of(context);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1D2E),
          title: Text(
            l10n.get('bridge_card_voice_channel_title'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            l10n.get('bridge_card_calm_disclaimer'),
            style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.get('bridge_card_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.get('bridge_card_join_voice')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _join();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final connected = _room != null;
    final desk = _isEmergencyServicesDesk;
    final elite = _eliteVolunteerBridge;
    final loading = desk == null || elite == null;
    final hasIncidentId =
        widget.lockIncidentId && (widget.initialIncidentId ?? '').trim().isNotEmpty;
    final pttOnly =
        ref.watch(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;

    if (connected) {
      return _buildConnectedState();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A3356)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pttOnly) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
              ),
              child: Text(
                l10n.get('bridge_card_ptt_only_banner'),
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryInfo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.wifi_tethering_rounded,
                    color: AppColors.primaryInfo, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.get('volunteer_bridge_voice_channel_title'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                    Text(
                      desk == true
                          ? l10n.get('volunteer_bridge_join_hint_desk')
                          : elite == true
                              ? l10n.get('volunteer_bridge_join_hint_elite')
                              : l10n.get('volunteer_bridge_join_hint_incident'),
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!hasIncidentId) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: TextField(
                controller: _incidentIdController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: l10n.get('volunteer_bridge_incident_id_hint'),
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: Colors.black26,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              onPressed: (loading || _busy || pttOnly) ? null : _onJoinPressed,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.call_rounded, size: 18),
              label: Text(
                _busy
                    ? l10n.get('volunteer_bridge_connecting_btn')
                    : l10n.get('volunteer_bridge_join_voice_btn'),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3BA55D),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedState() {
    final l10n = AppLocalizations.of(context);
    final pCount = _participants.length + 1; // +1 for self

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2D1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF3BA55D).withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Channel header
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, child) => Opacity(
                    opacity: _pulseAnim.value, child: child),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3BA55D),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.get('bridge_card_voice_connected'),
                  style: const TextStyle(
                    color: Color(0xFF3BA55D),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                l10n
                    .get('bridge_card_in_channel')
                    .replaceAll('{n}', '$pCount'),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Participant avatars row
          if (_participants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _participants.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 6),
                  itemBuilder: (context, i) => _ParticipantChip(
                      label: _participants[i]),
                ),
              ),
            ),
          // Push-to-talk + disconnect
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => unawaited(_pttDown()),
            onPointerUp: (_) => unawaited(_pttUp()),
            onPointerCancel: (_) => unawaited(_pttUp()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _pttHeld
                    ? const Color(0xFF3BA55D).withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _pttHeld
                      ? const Color(0xFF3BA55D)
                      : Colors.white24,
                  width: _pttHeld ? 2 : 1,
                ),
              ),
              child: Text(
                _pttHeld
                    ? l10n.get('bridge_card_transmitting')
                    : l10n.get('bridge_card_hold_to_talk'),
                style: TextStyle(
                  color: _pttHeld ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => unawaited(_leave()),
              icon: const Icon(Icons.call_end_rounded, size: 16),
              label: Text(l10n.get('bridge_card_disconnect'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  final String label;
  const _ParticipantChip({required this.label});

  IconData get _icon {
    final l = label.toLowerCase();
    if (l.contains('dispatch')) return Icons.support_agent_rounded;
    if (l.contains('victim')) return Icons.person_rounded;
    if (l.contains('contact')) return Icons.contact_phone_rounded;
    if (l.contains('lifeline') || l.contains('ai')) return Icons.smart_toy_rounded;
    if (l.contains('volunteer')) return Icons.volunteer_activism_rounded;
    return Icons.headset_mic_rounded;
  }

  Color get _color {
    final l = label.toLowerCase();
    if (l.contains('dispatch')) return AppColors.primaryInfo;
    if (l.contains('victim')) return AppColors.primaryDanger;
    if (l.contains('lifeline') || l.contains('ai')) return Colors.purpleAccent;
    if (l.contains('volunteer')) return Colors.green;
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: _color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                color: _color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
