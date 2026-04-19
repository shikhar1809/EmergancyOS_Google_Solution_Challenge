import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/widgets/language_switcher_button.dart';
import '../../../core/widgets/livekit_voice_party_strip.dart';
import '../../../services/livekit_comms_bridge_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// LiveKit **operation** comms room (`commsop_*`) — hospital / command coordination (not Firebase PTT).
class FleetCommsOperationScreen extends StatefulWidget {
  const FleetCommsOperationScreen({
    super.key,
    required this.incidentId,
    this.boundHospitalDocId,
  });

  final String incidentId;
  final String? boundHospitalDocId;

  @override
  State<FleetCommsOperationScreen> createState() => _FleetCommsOperationScreenState();
}

class _FleetCommsOperationScreenState extends State<FleetCommsOperationScreen> {
  Room? _room;
  bool _busy = false;
  bool _micOn = true;
  final Set<String> _speakingIdentities = {};
  EventsListener<RoomEvent>? _listener;

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

  String _remoteLabel(RemoteParticipant p) {
    final id = p.identity;
    if (id.startsWith('comms_')) return 'Ops / staff';
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
          label: 'You (fleet)',
          isLocal: true,
          isSpeaking: id.isNotEmpty && _speakingIdentities.contains(id),
        ),
      );
    }
    for (final p in r.remoteParticipants.values) {
      final id = p.identity.trim();
      out.add(
        LivekitVoicePartyAvatar(
          label: _remoteLabel(p),
          isSpeaking: id.isNotEmpty && _speakingIdentities.contains(id),
        ),
      );
    }
    return out;
  }

  Future<void> _connect() async {
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    setState(() => _busy = true);
    try {
      await _disconnect();
      final room = await LivekitCommsBridgeService.connectFleetChannel(
        channel: 'operation',
        incidentId: id,
        boundHospitalDocId: widget.boundHospitalDocId,
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
      _listener = room.createListener()
        ..on<RoomConnectedEvent>((_) => setState(() {}))
        ..on<ParticipantConnectedEvent>((_) => setState(() {}))
        ..on<ParticipantDisconnectedEvent>((_) => setState(() {}))
        ..on<TrackPublishedEvent>((_) => setState(() {}))
        ..on<TrackSubscribedEvent>((_) => setState(() {}))
        ..on<ActiveSpeakersChangedEvent>((e) {
          if (!mounted) return;
          setState(() {
            _speakingIdentities
              ..clear()
              ..addAll(
                e.speakers.map((s) => s.identity.trim()).where((x) => x.isNotEmpty),
              );
          });
        });
      setState(() => _room = room);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operator channel: $e')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mic: $e')));
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
        title: Text(context.opsTr('Operator channel (LiveKit)')),
        actions: [
          const LanguageSwitcherButton(),
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
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(context.opsTr('Hospital / command operations net for this incident. Mute when not speaking.'), style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 20),
              if (connected) ...[
                LivekitVoicePartyStrip(avatars: party),
                const SizedBox(height: 12),
                Text(
                  party.length <= 1 ? 'Waiting for dispatch / hospital…' : 'Connected',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : () => unawaited(connected ? _disconnect() : _connect()),
                style: FilledButton.styleFrom(
                  backgroundColor: connected ? Colors.red.shade800 : const Color(0xFF238636),
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
