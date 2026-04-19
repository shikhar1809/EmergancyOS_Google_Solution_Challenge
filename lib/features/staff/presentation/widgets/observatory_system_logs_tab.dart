import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/admin_panel_access.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class ObservatorySystemLogsTab extends StatefulWidget {
  const ObservatorySystemLogsTab({
    super.key,
    required this.accent,
    required this.access,
  });

  final Color accent;
  final AdminPanelAccess access;

  @override
  State<ObservatorySystemLogsTab> createState() =>
      _ObservatorySystemLogsTabState();
}

class _LogEntry {
  _LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  final DateTime timestamp;
  final String level;
  final String source;
  final String message;
}

class _ObservatorySystemLogsTabState extends State<ObservatorySystemLogsTab> {
  final List<_LogEntry> _logs = [];
  bool _loading = true;
  String _filter = '';
  String _levelFilter = 'all';

  @override
  void initState() {
    super.initState();
    unawaited(_loadLogs());
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    try {
      final entries = <_LogEntry>[];

      final recentIncidents = await FirebaseFirestore.instance
          .collection('sos_incidents')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      for (final doc in recentIncidents.docs) {
        final data = doc.data();
        final ts =
            (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final type = (data['type'] as String?) ?? 'unknown';
        final status = (data['status'] as String?) ?? 'unknown';
        final victimId = (data['victimId'] as String?) ?? '';

        entries.add(
          _LogEntry(
            timestamp: ts,
            level: status == 'resolved' ? 'info' : 'warning',
            source: 'incident',
            message:
                '[$type] $status — ${doc.id} ${victimId.isNotEmpty ? "($victimId)" : ""}',
          ),
        );
      }

      final auditSnap = await FirebaseFirestore.instance
          .collectionGroup('audit_log')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .get();

      for (final doc in auditSnap.docs) {
        final data = doc.data();
        final ts =
            (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
        final action = (data['action'] as String?) ?? 'unknown';
        final note = (data['note'] as String?) ?? '';

        entries.add(
          _LogEntry(
            timestamp: ts,
            level: 'info',
            source: 'audit',
            message: '$action ${note.isNotEmpty ? "— $note" : ""}',
          ),
        );
      }

      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (!mounted) return;
      setState(() {
        _logs.clear();
        _logs.addAll(entries.take(50));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<_LogEntry> get _filteredLogs {
    var result = _logs;
    if (_levelFilter != 'all') {
      result = result.where((e) => e.level == _levelFilter).toList();
    }
    final f = _filter.trim().toLowerCase();
    if (f.isNotEmpty) {
      result = result
          .where(
            (e) =>
                e.message.toLowerCase().contains(f) ||
                e.source.toLowerCase().contains(f),
          )
          .toList();
    }
    return result;
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'error':
        return Colors.redAccent;
      case 'warning':
        return Colors.orangeAccent;
      case 'info':
      default:
        return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    final logs = _filteredLogs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: context.opsTr('Filter logs…'),
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _levelFilter,
                dropdownColor: const Color(0xFF111827),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(context.opsTr('All'))),
                  DropdownMenuItem(value: 'info', child: Text(context.opsTr('Info'))),
                  DropdownMenuItem(value: 'warning', child: Text(context.opsTr('Warning'))),
                  DropdownMenuItem(value: 'error', child: Text(context.opsTr('Error'))),
                ],
                onChanged: (v) => setState(() => _levelFilter = v ?? 'all'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _loading ? null : () => unawaited(_loadLogs()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.opsTr('Refresh')),
                style: FilledButton.styleFrom(
                  backgroundColor: a.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${logs.length} entries · Incident events + audit trail',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : logs.isEmpty
              ? Center(
                  child: Text(
                    'No log entries found.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),
                )
              : Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: logs.length,
                    itemBuilder: (context, i) {
                      final e = logs[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(
                                  top: 5,
                                  right: 12,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _levelColor(e.level),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.message,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          e.source.toUpperCase(),
                                          style: TextStyle(
                                            color: a.withValues(alpha: 0.7),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateFormat.MMMd().add_Hms().format(
                                            e.timestamp.toLocal(),
                                          ),
                                          style: TextStyle(
                                            color: Colors.white.withValues(
                                              alpha: 0.3,
                                            ),
                                            fontSize: 9,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
