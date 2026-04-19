import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:livekit_client/livekit_client.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/livekit_ui_sounds.dart';
import '../../../core/widgets/livekit_voice_party_strip.dart';
import '../../../services/incident_service.dart';
import '../../../services/livekit_comms_bridge_service.dart';
import '../../../services/ops_hospital_service.dart';
import '../domain/admin_panel_access.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Deep-link: Comms tab opens and joins this incident channel (`operation` | `emergency`).
class CommsPendingJoin {
  const CommsPendingJoin({required this.incidentId, required this.channel});

  final String incidentId;
  final String channel;
}

/// Discord-style comms: hospital “servers”, incident categories, Operation + Emergency voice per incident.
class CommsBridgeScreen extends StatefulWidget {
  const CommsBridgeScreen({
    super.key,
    required this.access,
    this.pendingJoin,
    this.onPendingJoinConsumed,
  });

  final AdminPanelAccess access;
  final CommsPendingJoin? pendingJoin;
  final VoidCallback? onPendingJoinConsumed;

  @override
  State<CommsBridgeScreen> createState() => _CommsBridgeScreenState();
}

class _CommsBridgeScreenState extends State<CommsBridgeScreen> {
  static const Object _commandServer = Object();

  Object? _selectedServerKey;
  String? _activeIncidentId;
  String _activeChannel = '';
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _busy = false;
  bool _micOn = true;
  final Set<String> _ensuredIncidents = {};
  final Set<String> _speakingIdentities = {};
  String? _processedLaunchSig;

  bool get _isMaster => widget.access.role == AdminConsoleRole.master;

  String? get _boundHospitalId {
    final b = widget.access.boundHospitalDocId?.trim();
    if (b == null || b.isEmpty) return null;
    return b;
  }

  bool _medicalRailSelectionFixScheduled = false;

  void _pickMedicalServerIfNeeded(List<OpsHospitalRow> hospitals) {
    if (_isMaster) return;
    if (_boundHospitalId != null) return;
    if (hospitals.isEmpty) return;
    if (_selectedServerKey == _commandServer) return;
    final sel = _selectedServerKey;
    final valid = sel is String && hospitals.any((h) => h.id == sel);
    if (valid) {
      _medicalRailSelectionFixScheduled = false;
      return;
    }
    if (_medicalRailSelectionFixScheduled) return;
    _medicalRailSelectionFixScheduled = true;
    final pick = hospitals.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _medicalRailSelectionFixScheduled = false;
      if (!mounted) return;
      if (_isMaster || _boundHospitalId != null) return;
      setState(() => _selectedServerKey = pick);
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedServerKey = _isMaster ? _commandServer : _boundHospitalId;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_tryConsumePendingJoin()));
  }

  @override
  void didUpdateWidget(covariant CommsBridgeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingJoin != null && widget.pendingJoin == null) {
      _processedLaunchSig = null;
    }
    final pj = widget.pendingJoin;
    final opj = oldWidget.pendingJoin;
    if (pj != null &&
        (opj?.incidentId != pj.incidentId || opj?.channel != pj.channel)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_tryConsumePendingJoin()));
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    final r = _room;
    _room = null;
    if (r != null) {
      unawaited(r.disconnect());
      unawaited(r.dispose());
    }
    super.dispose();
  }

  Future<void> _disconnectRoom() async {
    _listener?.dispose();
    _listener = null;
    final r = _room;
    _room = null;
    if (r != null) {
      await r.disconnect();
      await r.dispose();
    }
    if (mounted) {
      setState(() {
        _activeChannel = '';
        _activeIncidentId = null;
        _speakingIdentities.clear();
      });
    }
  }

  void _attachListener(Room room) {
    _listener?.dispose();
    _listener = room.createListener()
      ..on<RoomConnectedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<RoomReconnectedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<RoomReconnectingEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<ParticipantConnectedEvent>((e) {
        final lid = room.localParticipant?.identity ?? '';
        final pid = e.participant.identity;
        if (pid.isNotEmpty && pid != lid) {
          unawaited(LivekitUiSounds.playJoin());
        }
        if (mounted) setState(() {});
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        final lid = room.localParticipant?.identity ?? '';
        final pid = e.participant.identity;
        if (pid.isNotEmpty && pid != lid) {
          unawaited(LivekitUiSounds.playLeave());
        }
        if (mounted) setState(() {});
      })
      ..on<TrackMutedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<TrackUnmutedEvent>((_) {
        if (mounted) setState(() {});
      })
      ..on<ActiveSpeakersChangedEvent>((e) {
        if (!mounted) return;
        setState(() {
          _speakingIdentities
            ..clear()
            ..addAll(
              e.speakers
                  .map((s) => s.identity.trim())
                  .where((id) => id.isNotEmpty),
            );
        });
      })
      ..on<RoomDisconnectedEvent>((_) {
        if (!mounted) return;
        setState(() => _room = null);
      });
  }

  List<LivekitVoicePartyAvatar> _partyAvatars(Room room) {
    final out = <LivekitVoicePartyAvatar>[];
    for (final p in _participantsOrdered(room)) {
      final id = p.identity.trim();
      final isLocal = p is LocalParticipant;
      out.add(
        LivekitVoicePartyAvatar(
          label: isLocal ? _localDisplayLabel() : _participantTitle(p),
          isLocal: isLocal,
          isSpeaking: id.isNotEmpty && _speakingIdentities.contains(id),
        ),
      );
    }
    return out;
  }

  String get _selfLabel {
    final u = FirebaseAuth.instance.currentUser;
    if (_isMaster) return u?.email ?? 'Master';
    final hid = widget.access.boundHospitalDocId ?? '';
    return hid.isEmpty ? 'Hospital console' : 'Hospital ($hid)';
  }

  String _localDisplayLabel() {
    final u = FirebaseAuth.instance.currentUser;
    final dn = u?.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final em = u?.email?.trim();
    if (em != null && em.isNotEmpty) return em;
    return _selfLabel;
  }

  String _formatVoiceError(Object e) {
    if (e is FirebaseException) {
      final m = e.message;
      if (m != null && m.isNotEmpty) return '${e.code}: $m';
      return e.code;
    }
    return e.toString();
  }

  String _connectionStatusLine(Room? room) {
    if (room == null) return 'Not connected';
    return switch (room.connectionState) {
      ConnectionState.connected => 'Connected · LiveKit',
      ConnectionState.connecting => 'Connecting…',
      ConnectionState.reconnecting => 'Reconnecting…',
      ConnectionState.disconnected => 'Disconnected',
    };
  }

  (Color, String) _connectionStatusStyle(Room? room) {
    if (room == null) {
      return (Colors.white38, 'Idle');
    }
    return switch (room.connectionState) {
      ConnectionState.connected => (Colors.greenAccent, 'Live'),
      ConnectionState.connecting => (Colors.lightBlueAccent, 'Connecting'),
      ConnectionState.reconnecting => (Colors.orangeAccent, 'Reconnecting'),
      ConnectionState.disconnected => (Colors.redAccent, 'Offline'),
    };
  }

  String _participantTitle(Participant p) {
    final n = p.name.trim();
    if (n.isNotEmpty) return n;
    final id = p.identity.trim();
    return id.isEmpty ? 'Participant' : id;
  }

  int _compareParticipants(Participant a, Participant b) {
    final ta = _participantTitle(a).toLowerCase();
    final tb = _participantTitle(b).toLowerCase();
    final c = ta.compareTo(tb);
    if (c != 0) return c;
    return a.identity.compareTo(b.identity);
  }

  List<Participant> _participantsOrdered(Room room) {
    final lp = room.localParticipant;
    final rem = room.remoteParticipants.values.toList()..sort(_compareParticipants);
    return [?lp, ...rem];
  }

  Future<void> _tryConsumePendingJoin() async {
    final pj = widget.pendingJoin;
    if (pj == null) return;
    final ch = pj.channel.trim().toLowerCase();
    if (ch != 'operation' && ch != 'emergency') return;
    final incId = pj.incidentId.trim();
    if (incId.isEmpty) return;
    final sig = '$incId|$ch';
    if (_processedLaunchSig == sig) return;
    _processedLaunchSig = sig;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .doc(incId)
          .get();
      var hid = (doc.data()?['primaryHospitalId'] as String?)?.trim();
      if (hid != null && hid.isEmpty) hid = null;

      if (!mounted) return;
      setState(() {
        _selectedServerKey = hid ?? _boundHospitalId;
      });

      await _ensureIncident(incId);
      if (!mounted) return;
      final ui = ch == 'operation'
          ? 'Operation · $incId'
          : 'Emergency · $incId';
      await _join(channel: ch, incidentId: incId, uiLabel: ui);
    } catch (e, st) {
      debugPrint('[CommsBridge] pending join failed: $e\n$st');
      _processedLaunchSig = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice link: ${_formatVoiceError(e)}')),
        );
      }
    } finally {
      widget.onPendingJoinConsumed?.call();
    }
  }

  Future<void> _ensureIncident(String incidentId) async {
    if (_ensuredIncidents.contains(incidentId)) return;
    try {
      await LivekitCommsBridgeService.ensureIncidentRooms(
        incidentId: incidentId,
        boundHospitalDocId: widget.access.boundHospitalDocId,
      );
      _ensuredIncidents.add(incidentId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open comms rooms: $e')),
        );
      }
    }
  }

  Future<void> _join({
    required String channel,
    String? incidentId,
    required String uiLabel,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _disconnectRoom();
      final room = await LivekitCommsBridgeService.connect(
        access: widget.access,
        channel: channel,
        incidentId: incidentId,
        canPublishAudio: _micOn,
      );
      if (!mounted) {
        await room.disconnect();
        await room.dispose();
        return;
      }
      if (kIsWeb) {
        unawaited(room.startAudio());
      }
      _attachListener(room);
      setState(() {
        _room = room;
        _activeChannel = uiLabel;
        _activeIncidentId = incidentId;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice channel: ${_formatVoiceError(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleMic() async {
    final room = _room;
    if (room == null) return;
    final next = !_micOn;
    try {
      await room.localParticipant?.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micOn = next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Mic: $e')));
      }
    }
  }

  Widget _serverRail(List<OpsHospitalRow> hospitals) {
    _pickMedicalServerIfNeeded(hospitals);
    final visible = _isMaster
        ? hospitals
        : (_boundHospitalId != null
              ? hospitals.where((h) => h.id == _boundHospitalId).toList()
              : hospitals);

    return Container(
      width: 76,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF13161C), Color(0xFF0E1015)],
        ),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'SERVERS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (_isMaster) ...[
            _serverOrb(
              selected: _selectedServerKey == _commandServer,
              tooltip: context.opsTr('Inter-hospital command'),
              icon: Icons.hub_rounded,
              accent: const Color(0xFFB388FF),
              onTap: () => setState(() => _selectedServerKey = _commandServer),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ],
          if (visible.isEmpty && !_isMaster && _boundHospitalId != null)
            _serverOrb(
              selected: _selectedServerKey == _boundHospitalId,
              tooltip: _boundHospitalId!,
              icon: Icons.local_hospital_rounded,
              accent: AppColors.accentBlue,
              onTap: () =>
                  setState(() => _selectedServerKey = _boundHospitalId),
            ),
          for (final h in visible)
            _serverOrb(
              selected: _selectedServerKey == h.id,
              tooltip: h.name,
              icon: Icons.local_hospital_rounded,
              accent: AppColors.accentBlue,
              onTap: () => setState(() => _selectedServerKey = h.id),
            ),
        ],
      ),
    );
  }

  Widget _serverOrb({
    required bool selected,
    required String tooltip,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.06),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: selected
                ? accent.withValues(alpha: 0.22)
                : const Color(0xFF1E232C),
            borderRadius: BorderRadius.circular(13),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              splashColor: accent.withValues(alpha: 0.2),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Icon(
                  icon,
                  color: selected ? Colors.white : Colors.white54,
                  size: 26,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _channelSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.14),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelColumn({
    required Map<String, String> assignmentPrimaryByIncident,
    required List<SosIncident> incidents,
  }) {
    if (_selectedServerKey == _commandServer) {
      return Container(
        width: 300,
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
          children: [
            _channelSectionHeader(
              icon: Icons.shield_moon_rounded,
              title: 'Command net',
              subtitle: 'Cross-hospital coordination',
              accent: const Color(0xFFB388FF),
            ),
            const SizedBox(height: 14),
            _voiceChannelTile(
              icon: Icons.graphic_eq_rounded,
              label: 'Operations voice',
              subtitle: 'All facilities · master console',
              channelAccent: const Color(0xFFB388FF),
              selected: _room != null && _activeChannel == 'Command net',
              onTap: () => _join(channel: 'command', uiLabel: 'Command net'),
            ),
          ],
        ),
      );
    }

    if (_selectedServerKey == null) {
      return Container(
        width: 300,
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(20),
        child: Text(
          'Select a facility from the rail.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      );
    }

    final hid = _selectedServerKey as String;
    final forHospital = incidents.where((e) {
      if (e.status == IncidentStatus.resolved) return false;
      final p = assignmentPrimaryByIncident[e.id]?.trim();
      if (p == null || p.isEmpty) return false;
      return p == hid;
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          _channelSectionHeader(
            icon: Icons.local_hospital_rounded,
            title: hid,
            subtitle: 'Incident voice rooms (auto-created)',
            accent: AppColors.accentBlue,
          ),
          const SizedBox(height: 6),
          Text(
            'Each open incident gets Operation + Emergency channels.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 11,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          if (forHospital.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No active incidents for this hospital.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ),
          for (final inc in forHospital)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashColor: AppColors.accentBlue.withValues(alpha: 0.08),
                ),
                child: Material(
                  color: const Color(0xFF1E232C),
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    collapsedIconColor: Colors.white38,
                    iconColor: AppColors.accentBlue,
                    title: Text(
                      inc.type,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${inc.id.length > 14 ? '${inc.id.substring(0, 14)}…' : inc.id} · ${inc.lifecyclePhaseLabel}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
                    onExpansionChanged: (open) {
                      if (open) unawaited(_ensureIncident(inc.id));
                    },
                    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                    children: [
                      _voiceChannelTile(
                        icon: Icons.settings_input_antenna,
                        label: 'Operation',
                        subtitle: 'Dispatch & coordination',
                        channelAccent: AppColors.accentBlue,
                        selected:
                            _room != null &&
                            _activeIncidentId == inc.id &&
                            _activeChannel.contains('Operation'),
                        onTap: () => _join(
                          channel: 'operation',
                          incidentId: inc.id,
                          uiLabel: 'Operation · ${inc.id}',
                        ),
                      ),
                      _voiceChannelTile(
                        icon: Icons.emergency_rounded,
                        label: 'Emergency',
                        subtitle: 'Clinical / scene bridge',
                        channelAccent: Colors.deepOrangeAccent,
                        selected:
                            _room != null &&
                            _activeIncidentId == inc.id &&
                            _activeChannel.contains('Emergency'),
                        onTap: () => _join(
                          channel: 'emergency',
                          incidentId: inc.id,
                          uiLabel: 'Emergency · ${inc.id}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _voiceChannelTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
    Color channelAccent = AppColors.accentBlue,
  }) {
    final ac = channelAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? ac.withValues(alpha: 0.12) : const Color(0xFF252B36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected
                ? ac.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: ac.withValues(alpha: 0.15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: ac.withValues(alpha: selected ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? Colors.white : ac.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.38),
                          fontSize: 10,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.headset_mic_rounded,
                  size: 18,
                  color: selected ? ac : Colors.white24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _membersSidebar(Room room) {
    final people = _participantsOrdered(room);
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E12),
        border: Border(
          left: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice channel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Online — ${people.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hospital & command staff in this room',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 11,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
              itemCount: people.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Colors.white.withValues(alpha: 0.06),
              ),
              itemBuilder: (context, i) {
                final p = people[i];
                final isLocal = p is LocalParticipant;
                final id = p.identity.trim();
                final title = isLocal ? _localDisplayLabel() : _participantTitle(p);
                final speaking =
                    id.isNotEmpty && _speakingIdentities.contains(id);
                final micOn = p.isMicrophoneEnabled();
                final av = LivekitVoicePartyAvatar(
                  label: title,
                  isLocal: isLocal,
                  isSpeaking: speaking,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: speaking
                              ? Colors.greenAccent.withValues(alpha: 0.2)
                              : const Color(0xFF1E232C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: speaking
                                ? Colors.greenAccent.withValues(alpha: 0.45)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          av.initials,
                          style: TextStyle(
                            color: speaking
                                ? Colors.greenAccent.shade100
                                : Colors.white70,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isLocal
                                  ? 'You · ${_micOn ? 'mic on' : 'muted'}'
                                  : (micOn ? 'Speaking ready' : 'Muted'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.38),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                        size: 18,
                        color: micOn
                            ? Colors.white54
                            : Colors.redAccent.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _voicePanel() {
    final room = _room;
    return ColoredBox(
      color: const Color(0xFF0D1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF1C2128),
                  const Color(0xFF0D1117).withValues(alpha: 0.95),
                ],
              ),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.headset_mic_rounded,
                    color: AppColors.accentBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room == null ? 'Voice lounge' : _activeChannel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        room == null
                            ? 'Pick a server, then join Operation or Emergency'
                            : '${_connectionStatusLine(room)} · ${_micOn ? 'Your mic on' : 'Your mic muted'}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (room != null) ...[
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                    ),
                    onPressed: _busy ? null : _toggleMic,
                    child: Icon(
                      _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orangeAccent,
                      side: BorderSide(
                        color: Colors.orangeAccent.withValues(alpha: 0.5),
                      ),
                    ),
                    onPressed: _busy ? null : _disconnectRoom,
                    child: Text(context.opsTr('Leave')),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: room == null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.accentBlue.withValues(
                                  alpha: 0.08,
                                ),
                                border: Border.all(
                                  color: AppColors.accentBlue.withValues(
                                    alpha: 0.22,
                                  ),
                                ),
                              ),
                              child: Icon(
                                Icons.graphic_eq_rounded,
                                size: 48,
                                color: AppColors.accentBlue.withValues(
                                  alpha: 0.75,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Hospital voice bridge',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Servers on the left mirror facilities. Under each incident you\'ll find two channels — coordination and emergency — created automatically when rooms are prepared.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.42),
                                height: 1.55,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: AppColors.accentBlue,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Who\'s here',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              LivekitVoicePartyStrip(
                                avatars: _partyAvatars(room),
                                backgroundColor: const Color(0xFF161B22),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _membersSidebar(room),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _screenTopChrome() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.forum_rounded,
            color: AppColors.accentBlue.withValues(alpha: 0.95),
            size: 22,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comms bridge',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
                Text(
                  'Secure voice · hospitals & incidents',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final (dot, label) = _connectionStatusStyle(_room);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.accentBlue.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: dot),
                    const SizedBox(width: 6),
                    Text(
                      'LiveKit · $label',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _screenTopChrome(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('ops_hospitals')
                      .limit(64)
                      .snapshots(),
                  builder: (context, hSnap) {
                    final hospitals =
                        hSnap.data?.docs
                            .map(OpsHospitalRow.fromFirestore)
                            .toList() ??
                        [];
                    return _serverRail(hospitals);
                  },
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('ops_incident_hospital_assignments')
                      .limit(400)
                      .snapshots(),
                  builder: (context, aSnap) {
                    final primaries = <String, String>{};
                    for (final d in aSnap.data?.docs ?? const []) {
                      final pid = (d.data()['primaryHospitalId'] as String?)
                          ?.trim();
                      if (pid != null && pid.isNotEmpty) primaries[d.id] = pid;
                    }
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('sos_incidents')
                          .limit(400)
                          .snapshots(),
                      builder: (context, iSnap) {
                        final incidents =
                            iSnap.data?.docs
                                .map(SosIncident.fromFirestore)
                                .where((e) {
                                  final id = e.id;
                                  return !id.startsWith('demo_') &&
                                      !id.startsWith('demo_ops_');
                                })
                                .toList() ??
                            [];
                        return _channelColumn(
                          assignmentPrimaryByIncident: primaries,
                          incidents: incidents,
                        );
                      },
                    );
                  },
                ),
                Expanded(child: _voicePanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
