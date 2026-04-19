import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../services/ops_system_health_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Master console: compact GCP / LiveKit / SMS status with periodic refresh.
class OpsSystemStatusStrip extends StatefulWidget {
  const OpsSystemStatusStrip({super.key});

  @override
  State<OpsSystemStatusStrip> createState() => _OpsSystemStatusStripState();
}

class _OpsSystemStatusStripState extends State<OpsSystemStatusStrip> {
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

  void _showDetails() {
    final r = _report;
    final err = _error;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(context.opsTr('System status'), style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (err != null)
                Text(
                  'Could not load status: $err',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.opsTr('Close')),
          ),
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
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11, height: 1.3),
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
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _showDetails,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                )
              else if (_error != null)
                const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 18)
              else if (_report != null)
                Icon(
                  _report!.ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
                  color: _report!.ok ? const Color(0xFF4CAF50) : Colors.orangeAccent,
                  size: 20,
                )
              else
                const Icon(Icons.help_outline, color: Colors.white38, size: 18),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  _loading
                      ? 'Checking services…'
                      : _error != null
                          ? 'Status unavailable — tap for details'
                          : (_report?.summary ?? ''),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
