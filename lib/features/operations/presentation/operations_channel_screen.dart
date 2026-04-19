import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/utils/livekit_ui_sounds.dart';
import '../../../core/widgets/livekit_voice_party_strip.dart';
import '../../../services/livekit_operations_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Live voice between **hospital / command** and the **fleet unit assigned** to this incident.
class OperationsChannelScreen extends StatefulWidget {
  const OperationsChannelScreen({
    super.key,
    required this.incidentId,
    required this.side,
  });

  final String incidentId;
  final OperationsLiveKitSide side;

  @override
  State<OperationsChannelScreen> createState() => _OperationsChannelScreenState();
}

class _OperationsChannelScreenState extends State<OperationsChannelScreen> {
  Room? _room;
  bool _busy = false;
  bool _micOn = true;
  final Set<String> _speakingIdentities = {};
  EventsListener<RoomEvent>? _listener;

  String get _sideLabel => widget.side == OperationsLiveKitSide.hospital
      ? 'Hospital / command'
      : 'Fleet unit';

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

  String _remoteOpsLabel(RemoteParticipant p) {
    final id = p.identity;
    if (id.startsWith('hosp_ops_')) return 'Hospital / command';
    if (id.startsWith('fleet_ops_')) return 'Fleet';
    return id.isEmpty ? 'Participant' : id;
  }

  List<LivekitVoicePartyAvatar> _partyAvatars() {
    final r = _room;
    if (r == null) return [];
    final out = <LivekitVoicePartyAvatar>[];
    final lp = r.localParticipant;
    if (lp != null) {
      final id = lp.identity.trim();
      out.add(
        LivekitVoicePartyAvatar(
          label: _sideLabel,
          isLocal: true,
          isSpeaking: id.isNotEmpty && _speakingIdentities.contains(id),
        ),
      );
    }
    for (final p in r.remoteParticipants.values) {
      final id = p.identity.trim();
      out.add(
        LivekitVoicePartyAvatar(
          label: _remoteOpsLabel(p),
          isSpeaking: id.isNotEmpty && _speakingIdentities.contains(id),
        ),
      );
    }
    return out;
  }

  void _syncParticipants() {
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    setState(() => _busy = true);
    try {
      await _disconnect();
      final room = await LivekitOperationsService.connect(
        incidentId: id,
        side: widget.side,
        canPublishAudio: _micOn,
      );
      if (!mounted) {
        await room.disconnect();
        await room.dispose();
        return;
      }

      _listener = room.createListener()
        ..on<RoomConnectedEvent>((_) => _syncParticipants())
        ..on<ParticipantConnectedEvent>((e) {
          final lid = room.localParticipant?.identity ?? '';
          final pid = e.participant.identity;
          if (pid.isNotEmpty && pid != lid) {
            unawaited(LivekitUiSounds.playJoin());
          }
          _syncParticipants();
        })
        ..on<ParticipantDisconnectedEvent>((e) {
          final lid = room.localParticipant?.identity ?? '';
          final pid = e.participant.identity;
          if (pid.isNotEmpty && pid != lid) {
            unawaited(LivekitUiSounds.playLeave());
          }
          _syncParticipants();
        })
        ..on<TrackPublishedEvent>((_) => _syncParticipants())
        ..on<TrackSubscribedEvent>((_) => _syncParticipants())
        ..on<ActiveSpeakersChangedEvent>((e) {
          if (!mounted) return;
          setState(() {
            _speakingIdentities
              ..clear()
              ..addAll(
                e.speakers.map((s) => s.identity.trim()).where((id) => id.isNotEmpty),
              );
          });
        });

      setState(() => _room = room);
      if (kIsWeb) {
        unawaited(room.startAudio());
      }
      _syncParticipants();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not join channel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    _listener?.dispose();
    _listener = null;
    final r = _room;
    _room = null;
    _speakingIdentities.clear();
    if (r != null) {
      try {
        await r.localParticipant?.setMicrophoneEnabled(false);
      } catch (_) {}
      await r.disconnect();
      await r.dispose();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    final r = _room;
    if (r == null) return;
    final next = !_micOn;
    try {
      await r.localParticipant?.setMicrophoneEnabled(next);
      if (mounted) setState(() => _micOn = next);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Microphone: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _room != null;
    final party = _partyAvatars();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Text(context.opsTr('Operation channel')),
        actions: [
          if (connected)
            IconButton(
              icon: Icon(_micOn ? Icons.mic : Icons.mic_off),
              onPressed: _busy ? null : _toggleMic,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Incident ${widget.incidentId}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You are joining as: $_sideLabel',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'LiveKit voice between the accepting hospital and the assigned ambulance crew. '
                'Requires hospital acceptance and an assigned fleet call sign.',
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 24),
              if (connected) ...[
                LivekitVoicePartyStrip(avatars: party),
                const SizedBox(height: 12),
                Text(
                  party.length <= 1
                      ? 'Waiting for the other party…'
                      : 'Voice channel active — green ring = speaking',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(connected ? _disconnect() : _connect()),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      connected ? Colors.red.shade800 : const Color(0xFF238636),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: Icon(connected ? Icons.call_end : Icons.headset_mic),
                label: Text(connected ? 'Leave channel' : 'Join channel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
