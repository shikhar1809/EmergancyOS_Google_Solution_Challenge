import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/maps/maps_leaflet_fallback_provider.dart';
import '../../../../core/providers/ops_integration_routing_provider.dart';
import '../../../../services/ops_integration_routing_service.dart';
import '../../../../services/ops_system_health_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Master-only panel: fleet voice/maps routing, integration health, Firestore ping.
class MasterSystemsStatusSection extends ConsumerStatefulWidget {
  const MasterSystemsStatusSection({
    super.key,
    required this.accent,
    this.initiallyExpanded = false,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 10),
  });

  final Color accent;
  /// When true (e.g. dedicated Systems dock tab), the panel starts expanded.
  final bool initiallyExpanded;
  final EdgeInsetsGeometry margin;

  @override
  ConsumerState<MasterSystemsStatusSection> createState() => _MasterSystemsStatusSectionState();
}

class _MasterSystemsStatusSectionState extends ConsumerState<MasterSystemsStatusSection> {
  OpsSystemHealthReport? _health;
  Object? _healthError;
  bool _healthLoading = false;
  DateTime? _lastHealthFetch;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _refreshHealth() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() {
        _healthLoading = true;
        _healthError = null;
      });
      try {
        final r = await OpsSystemHealthService.fetch();
        if (!mounted) return;
        setState(() {
          _health = r;
          _lastHealthFetch = DateTime.now();
          _healthLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _healthError = e;
          _healthLoading = false;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHealth());
  }

  Future<bool> _confirmVoiceSwitch(bool toFirebasePtt) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: Text(
          toFirebasePtt ? 'Switch to Firebase PTT?' : 'Enable LiveKit bridge?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          toFirebasePtt
              ? 'Victim and volunteer WebRTC emergency voice will stop. Text and PTT on the incident channel remain. The volunteer LiveKit join card will stay disabled until you switch back.'
              : 'Victims will connect to the LiveKit emergency bridge again. Confirm LiveKit and agents are healthy.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.opsTr('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.opsTr('Confirm')),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<bool> _confirmMapsSwitch(bool toLeaflet) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: Text(
          toLeaflet ? 'Use OpenStreetMap tiles fleet-wide?' : 'Use Google Maps tiles?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          toLeaflet
              ? 'All signed-in clients will use OSM-style map tiles instead of Google.'
              : 'Clients will prefer Google tiles. Automatic OSM fallback may still apply if Google fails (quota or auth).',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.opsTr('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.opsTr('Confirm')),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _setVoiceTransport(VictimVoiceTransport next) async {
    final cur = ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v);
    if (cur == null || cur.victimVoiceTransport == next) return;
    final ok = await _confirmVoiceSwitch(next == VictimVoiceTransport.firebasePtt);
    if (!ok || !mounted) return;
    try {
      await OpsIntegrationRoutingService.writeGlobal(
        OpsIntegrationRouting(
          victimVoiceTransport: next,
          mapsTiles: cur.mapsTiles,
        ),
      );
      await OpsIntegrationRoutingService.appendAudit(
        flag: 'victimVoiceTransport',
        oldValue: cur.victimVoiceTransport.firestoreValue,
        newValue: next.firestoreValue,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Voice routing updated.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  Future<void> _setMapsTiles(OpsMapsTiles next) async {
    final cur = ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v);
    if (cur == null || cur.mapsTiles == next) return;
    final ok = await _confirmMapsSwitch(next == OpsMapsTiles.leaflet);
    if (!ok || !mounted) return;
    try {
      await OpsIntegrationRoutingService.writeGlobal(
        OpsIntegrationRouting(
          victimVoiceTransport: cur.victimVoiceTransport,
          mapsTiles: next,
        ),
      );
      await OpsIntegrationRoutingService.appendAudit(
        flag: 'mapsTiles',
        oldValue: cur.mapsTiles.firestoreValue,
        newValue: next.firestoreValue,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Map tiles routing updated.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final routingAsync = ref.watch(opsIntegrationRoutingProvider);
    final routing = routingAsync.whenOrNull(data: (v) => v) ?? OpsIntegrationRouting.defaults;
    final autoLeaflet = ref.watch(mapsLeafletFallbackProvider);

    return Card(
      color: const Color(0xFF111827),
      margin: widget.margin,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.white10),
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          title: Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: widget.accent, size: 22),
              const SizedBox(width: 10),
              Text(context.opsTr('Systems status'), style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          subtitle: Text(
            routingAsync.isLoading ? 'Loading routing…' : 'Voice, maps, backend health',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            _sectionLabel('Victim voice transport'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.opsTr('LiveKit emergency bridge'), style: TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(
                routing.useFirebasePttOnly
                    ? 'Off — Firebase PTT / incident channel only'
                    : 'On — WebRTC bridge for SOS and join card',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
              value: !routing.useFirebasePttOnly,
              onChanged: routingAsync.isLoading
                  ? null
                  : (v) => unawaited(
                        _setVoiceTransport(
                          v ? VictimVoiceTransport.livekit : VictimVoiceTransport.firebasePtt,
                        ),
                      ),
            ),
            const Divider(),
            _sectionLabel('Map tiles'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.opsTr('Google Maps'), style: TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(
                routing.mapsTiles == OpsMapsTiles.leaflet
                    ? 'Volunteer / home maps use OSM. Staff ops consoles stay on Google unless this device auto-fallbacks.'
                    : 'Volunteer / home maps prefer Google (auto OSM fallback may still apply).',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
              value: routing.mapsTiles == OpsMapsTiles.google,
              onChanged: routingAsync.isLoading
                  ? null
                  : (v) => unawaited(
                        _setMapsTiles(v ? OpsMapsTiles.google : OpsMapsTiles.leaflet),
                      ),
            ),
            if (autoLeaflet && routing.mapsTiles == OpsMapsTiles.google) ...[
              const SizedBox(height: 6),
              Text(
                'This device still uses OSM (Google load/auth failed). Clear to retry Google on staff consoles and volunteer maps.',
                style: TextStyle(color: Colors.amberAccent.withValues(alpha: 0.85), fontSize: 10, height: 1.3),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    ref.read(mapsLeafletFallbackProvider.notifier).setLeafletExplicit(
                          false,
                          reason: 'master_cleared_auto_fallback',
                        );
                  },
                  child: Text(context.opsTr('Clear auto-fallback on this device')),
                ),
              ),
            ],
            const Divider(),
            _sectionLabel('SMS service'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.opsTr('Relay status'), style: TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: Text(
                _health == null && _healthError == null
                    ? 'Use Refresh health below'
                    : _healthError != null
                        ? 'Error: $_healthError'
                        : '${_health!.sms.label}: ${_health!.sms.ok ? "OK" : "check"} — ${_health!.sms.detail}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
              trailing: Tooltip(
                message: 'Planned — no Twilio or function changes in this build.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Inactive',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10),
                  ),
                ),
              ),
            ),
            const Divider(),
            _sectionLabel('Firebase & integrations'),
            if (_health != null) ...[
              _healthRow('Overall', _health!.ok ? 'OK' : 'Issues', _health!.summary),
              _healthRow('GCP', _health!.gcp.ok ? 'OK' : 'Issue', _health!.gcp.detail),
              _healthRow('LiveKit', _health!.livekit.ok ? 'OK' : 'Issue', _health!.livekit.detail),
              if (_lastHealthFetch != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Last check: ${_lastHealthFetch!.toLocal().toIso8601String()}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
                  ),
                ),
            ] else if (_healthError != null)
              Text(
                'Health call failed. Use Refresh or check Cloud Function deployment.',
                style: TextStyle(color: Colors.orangeAccent.withValues(alpha: 0.9), fontSize: 11),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _healthLoading ? null : _refreshHealth,
                  style: FilledButton.styleFrom(backgroundColor: widget.accent.withValues(alpha: 0.85)),
                  icon: _healthLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(context.opsTr('Refresh health')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await FirebaseFirestore.instance.collection('_health_check').limit(1).get();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.opsTr('Firestore ping OK'))),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Firestore: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.storage_rounded, size: 18, color: Colors.white70),
                  label: Text(context.opsTr('Firestore ping'), style: TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        t,
        style: TextStyle(
          color: widget.accent,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _healthRow(String k, String st, String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(k, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  st,
                  style: TextStyle(
                    color: st == 'OK' ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  detail,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
