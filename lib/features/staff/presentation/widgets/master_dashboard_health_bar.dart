import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/ops_system_health_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

enum _MasterHealthTier {
  loading,
  healthy,
  degraded,
  critical,
}

/// Master dashboard: full-width status bar — green (all OK), orange (integration issue), red (backend/GCP or probe failure).
class MasterDashboardHealthBar extends StatefulWidget {
  const MasterDashboardHealthBar({super.key});

  @override
  State<MasterDashboardHealthBar> createState() => _MasterDashboardHealthBarState();
}

class _MasterDashboardHealthBarState extends State<MasterDashboardHealthBar> {
  OpsSystemHealthReport? _report;
  Object? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await OpsSystemHealthService.fetch();
      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  _MasterHealthTier _tier() {
    if (_report == null && _error == null && _loading) {
      return _MasterHealthTier.loading;
    }
    if (_error != null) return _MasterHealthTier.critical;
    final r = _report;
    if (r == null) return _MasterHealthTier.loading;
    if (!r.gcp.ok) return _MasterHealthTier.critical;
    if (!r.livekit.ok) return _MasterHealthTier.degraded;
    return _MasterHealthTier.healthy;
  }

  ({Color bg, Color fg, IconData icon, String title, String subtitle}) _style(
    BuildContext context,
    _MasterHealthTier t,
  ) {
    switch (t) {
      case _MasterHealthTier.loading:
        return (
          bg: const Color(0xFF37474F),
          fg: Colors.white70,
          icon: Icons.hourglass_empty_rounded,
          title: context.opsTr('Checking system health…'),
          subtitle: context.opsTr('GCP · LiveKit · SMS'),
        );
      case _MasterHealthTier.healthy:
        final r = _report;
        final smsNote = r != null && !r.sms.ok;
        return (
          bg: const Color(0xFF1B5E20),
          fg: const Color(0xFFE8F5E9),
          icon: Icons.health_and_safety_rounded,
          title: context.opsTr('All systems operational'),
          subtitle: smsNote
              ? context.opsTr(
                  'Firestore and LiveKit OK · SMS relay optional (not configured)',
                )
              : context.opsTr('Firestore, LiveKit, and SMS checks passed'),
        );
      case _MasterHealthTier.degraded:
        return (
          bg: const Color(0xFFE65100),
          fg: const Color(0xFFFFF3E0),
          icon: Icons.warning_amber_rounded,
          title: context.opsTr('Degraded — one or more integrations need attention'),
          subtitle: _degradedSubtitle(context, _report!),
        );
      case _MasterHealthTier.critical:
        return (
          bg: const Color(0xFFB71C1C),
          fg: const Color(0xFFFFEBEE),
          icon: Icons.error_outline_rounded,
          title: _error != null
              ? context.opsTr('Critical — cannot reach backend health service')
              : context.opsTr('Critical — Firestore / GCP check failed'),
          subtitle:
              _error != null ? '$_error' : (_report?.gcp.detail ?? context.opsTr('Backend may be unavailable')),
        );
    }
  }

  static String _degradedSubtitle(BuildContext context, OpsSystemHealthReport r) {
    final parts = <String>[];
    if (!r.livekit.ok) parts.add('LiveKit');
    if (parts.isEmpty) return context.opsTr('Review Systems tab for details');
    return context
        .opsTr('Issue: {parts} — tap for details')
        .replaceAll('{parts}', parts.join(' · '));
  }

  void _showDetails() {
    final r = _report;
    final err = _error;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(context.opsTr('Integration health'), style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (err != null)
                Text(
                  'Health probe failed (treated as critical):\n$err',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.35),
                )
              else if (r != null) ...[
                Text(
                  r.summary,
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 16),
                _detailRow(r.gcp),
                _detailRow(r.livekit),
                _detailRow(r.sms),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.opsTr('Close'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_load());
            },
            child: Text(context.opsTr('Refresh')),
          ),
        ],
      ),
    );
  }

  static Widget _detailRow(OpsServiceHealth s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            s.ok ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 18,
            color: s.ok ? const Color(0xFF4CAF50) : Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.detail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
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

  @override
  Widget build(BuildContext context) {
    final tier = _tier();
    final st = _style(context, tier);

    return Material(
      color: st.bg,
      child: InkWell(
        onTap: _showDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (tier == _MasterHealthTier.loading)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: st.fg.withValues(alpha: 0.9),
                  ),
                )
              else
                Icon(st.icon, color: st.fg, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      st.title,
                      style: TextStyle(
                        color: st.fg,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      st.subtitle,
                      maxLines: tier == _MasterHealthTier.critical && _error != null ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: st.fg.withValues(alpha: 0.88),
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: st.fg.withValues(alpha: 0.7), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
