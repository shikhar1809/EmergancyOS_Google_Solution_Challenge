import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/providers/drill_session_provider.dart';
import '../../../services/drill_dashboard_fakes.dart';
import '../../../services/leaderboard_service.dart';
import '../../../services/incident_service.dart';
import '../../../core/providers/duty_provider.dart';
import '../../../core/providers/high_contrast_ops_provider.dart';
import '../../../services/volunteer_presence_service.dart';
import '../../../core/providers/active_volunteers_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/drill_entry_service.dart';
import '../../../services/drill_session_persistence.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key, this.isDrillShell = false});

  /// Practice routes under `/drill/...` — demo stats only, separate from live Home.
  final bool isDrillShell;

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _refreshing = false;

  static String _getTimeGreeting(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hour = DateTime.now().hour;
    if (hour < 12) return l.goodMorning;
    if (hour < 17) return l.goodAfternoon;
    return l.goodEvening;
  }

  static String _getUserDisplayName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      final local = user.email!.split('@').first.trim();
      if (local.isEmpty) return 'Volunteer';
      return local[0].toUpperCase() + (local.length > 1 ? local.substring(1).toLowerCase() : '');
    }
    if (user?.phoneNumber != null && user!.phoneNumber!.isNotEmpty) {
      return user.phoneNumber!;
    }
    return 'Volunteer'; // runtime fallback; localized in _VolunteerToggle
  }

  void _goGridMap() {
    context.go(widget.isDrillShell ? '/drill/map' : '/map');
  }

  Future<void> _onRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    ref.invalidate(leaderboardProvider);
    ref.invalidate(myResponseCountProvider);
    ref.invalidate(activeAlertCountProvider);
    await Future.delayed(const Duration(milliseconds: 600));
    if (context.mounted) setState(() => _refreshing = false);
  }

  Future<void> _onExitDrillPressed() async {
    final loc = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B2634),
        title: Text(loc.dashboardExitDrillTitle, style: const TextStyle(color: Colors.white)),
        content: Text(
          loc.dashboardExitDrillBody,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(loc.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.dashboardExitDrillConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final sos = prefs.getString('active_sos_incident_id')?.trim();
    if (sos == AppConstants.drillIncidentId) {
      await IncidentService.clearActiveSos();
    }
    final vol = prefs.getString(IncidentService.prefVolunteerIncidentId)?.trim();
    if (vol == AppConstants.drillIncidentId) {
      await IncidentService.clearVolunteerAssignment();
    }
    await prefs.remove('pendingIncidentId');
    await DrillSessionPersistence.clear();
    await DrillEntryService.clearArmedMode();
    if (!context.mounted) return;
    ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
    ref.read(drillVictimPracticeShellProvider.notifier).set(false);
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final useDrillDash =
        widget.isDrillShell || ref.watch(drillSessionDashboardDemoProvider);
    // Synthetic leaderboard/stats only on `/drill/dashboard` — main Home always uses live data.
    final useSyntheticLeaderboard = widget.isDrillShell;
    final AsyncValue<List<LeaderboardEntry>> leaderboardAsync =
        useSyntheticLeaderboard
            ? AsyncData(DrillDashboardFakes.leaderboard())
            : ref.watch(leaderboardProvider);
    final AsyncValue<int> myResponseAsync = useSyntheticLeaderboard
        ? AsyncData(DrillDashboardFakes.fakeMyResponses)
        : ref.watch(myResponseCountProvider);
    final AsyncValue<int> activeAlertsAsync = useSyntheticLeaderboard
        ? AsyncData(DrillDashboardFakes.fakeActiveAlerts)
        : ref.watch(activeAlertCountProvider);

    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (useDrillDash) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: _onExitDrillPressed,
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                      tooltip: AppLocalizations.of(context).dashboardBackLoginTooltip,
                    ),
                    IconButton(
                      onPressed: _onExitDrillPressed,
                      icon: const Icon(Icons.logout_rounded, color: AppColors.primaryDanger),
                      tooltip: 'Exit drill mode',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (widget.isDrillShell) ...[
                Material(
                  color: Colors.cyan.shade900.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.school_rounded, color: Colors.cyanAccent.shade200, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Practice Home — not your live dashboard. Leaderboard and counts are demo-only.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTimeGreeting(context),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getUserDisplayName(),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _VolunteerToggle(),
                      const SizedBox(height: 8),
                      const _OutdoorContrastToggle(),
                      if (FirebaseAuth.instance.currentUser != null) _OnDutyVolunteersHint(),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.turnOnDutyMsg,
                style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.35),
              ),
              if (useSyntheticLeaderboard) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4DD0E1).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4DD0E1).withValues(alpha: 0.45)),
                  ),
                  child: const Text(
                    'Practice dashboard: leaderboard and stats below are demo-only (not your live account).',
                    style: TextStyle(color: Color(0xFFB2EBF2), fontSize: 12, height: 1.35),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Live Stats Row ───────────────────────────────────────────
              Row(
                children: [
                  // My Responses (real)
                  _buildStatCard(
                    context,
                    myResponseAsync.when(
                      data: (n) => n == 0 ? 'Ready to help' : l.livesSaved,
                      loading: () => l.livesSaved,
                      error: (_, __) => l.livesSaved,
                    ),
                    myResponseAsync.when(
                      data: (n) => n == 0 ? '♡' : '$n',
                      loading: () => '–',
                      error: (_, __) => '?',
                    ),
                    Icons.favorite_rounded,
                    AppColors.primaryDanger,
                  ),
                  const SizedBox(width: 8),
                  // Active Alerts (real)
                  _buildStatCard(
                    context,
                    l.activeAlerts,
                    activeAlertsAsync.when(
                      data: (n) => '$n',
                      loading: () => '–',
                      error: (_, __) => '?',
                    ),
                    Icons.notifications_active_rounded,
                    Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  // Rank — derive from leaderboard
                  _buildStatCard(
                    context,
                    l.rank,
                    leaderboardAsync.when(
                      data: (entries) {
                        final idx = entries.indexWhere((e) => e.userId == currentUid);
                        if (idx == -1) return l.unranked;
                        return '#${idx + 1}';
                      },
                      loading: () => '–',
                      error: (_, __) => '–',
                    ),
                    Icons.leaderboard_rounded,
                    Colors.purpleAccent,
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // ── Leaderboard Section ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l.topLifeSavers, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purpleAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          useSyntheticLeaderboard ? 'DEMO' : l.live,
                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _onRefresh,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: _refreshing
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.purpleAccent),
                                )
                              : const Icon(Icons.refresh_rounded, color: Colors.purpleAccent, size: 18),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Expanded(
                child: StreamBuilder<List<ConnectivityResult>>(
                  stream: Connectivity().onConnectivityChanged,
                  builder: (context, connSnap) {
                    final isOffline = connSnap.hasData &&
                        connSnap.data!.every((r) => r == ConnectivityResult.none);

                    final leaderboardContent = leaderboardAsync.when(
                      loading: () => _buildLeaderboardSkeleton(),
                      error: (e, _) => Center(
                        child: Text('Could not load leaderboard.\n$e',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                  data: (entries) {
                        final isMeOnLeaderboard = entries.any((e) => e.isCurrentUser);

                        if (entries.isEmpty) {
                          return ref.watch(onDutyVolunteersSnapshotProvider).when(
                            loading: () => const Center(
                              child: CircularProgressIndicator(
                                color: Colors.purpleAccent,
                                strokeWidth: 2,
                              ),
                            ),
                            error: (_, __) =>
                                _leaderboardEmptyPlaceholder(context, soloOnDuty: false, onViewGrid: _goGridMap),
                            data: (snap) {
                              final myUid = FirebaseAuth.instance.currentUser?.uid;
                              final others = snap.docs.where((d) => d.id != myUid).toList()
                                ..sort(
                                  (a, b) => VolunteerPresenceService.displayNameFromUserDoc(a.data())
                                      .toLowerCase()
                                      .compareTo(
                                        VolunteerPresenceService.displayNameFromUserDoc(b.data()).toLowerCase(),
                                      ),
                                );
                              if (others.isEmpty) {
                                final soloOnDuty = myUid != null &&
                                    snap.docs.any((d) => d.id == myUid);
                                return _leaderboardEmptyPlaceholder(
                                  context,
                                  soloOnDuty: soloOnDuty,
                                  onViewGrid: _goGridMap,
                                );
                              }
                              const maxRows = 20;
                              final n = others.length > maxRows ? maxRows : others.length;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      l.leaderboardEmptySecondary,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.45),
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                                    child: Text(
                                      l.leaderboardOnDutyFallbackTitle,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: n,
                                      itemBuilder: (ctx, i) {
                                        final d = others[i];
                                        final name =
                                            VolunteerPresenceService.displayNameFromUserDoc(d.data());
                                        return _buildLeaderRow(
                                          context,
                                          i + 1,
                                          name,
                                          l.leaderboardOnDutyStat,
                                          '🟢',
                                          const Color(0xFF69F0AE),
                                          isMe: false,
                                        );
                                      },
                                    ),
                                  ),
                                  Center(
                                    child: TextButton.icon(
                                      onPressed: _goGridMap,
                                      icon: const Icon(Icons.map_rounded, color: AppColors.primaryInfo, size: 20),
                                      label: Text(
                                        l.leaderboardViewGrid,
                                        style: const TextStyle(
                                          color: AppColors.primaryInfo,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        }

                        return Column(
                          children: [
                            Expanded(
                              child: ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (ctx, i) {
                                  final e = entries[i];
                                  final rank = i + 1;
                                  String medal;
                                  Color medalColor;
                                  if (rank == 1) { medal = '🥇'; medalColor = Colors.amber; }
                                  else if (rank == 2) { medal = '🥈'; medalColor = Colors.grey.shade300; }
                                  else if (rank == 3) { medal = '🥉'; medalColor = Colors.brown.shade300; }
                                  else { medal = '#$rank'; medalColor = Colors.white38; }

                                  return _buildLeaderRow(
                                    context, rank, e.displayName,
                                    '${e.score} ${l.xpResponses.replaceAll('{0}', '${e.responseCount}')}',
                                    medal, medalColor,
                                    isMe: e.isCurrentUser,
                                  );
                                },
                              ),
                            ),
                            if (!isMeOnLeaderboard) ...[
                              const Divider(color: Colors.white10),
                              myResponseAsync.when(
                                data: (count) => _buildLeaderRow(
                                  context, 0, _getUserDisplayName(), 
                                  count == 0 ? l.saved : '$count ${l.saved}', 
                                  'NEW', Colors.tealAccent, 
                                  isMe: true
                                ),
                                loading: () => const SizedBox.shrink(),
                                error: (_, __) => const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        );
                      },
                    );

                    if (isOffline) {
                      return Stack(
                        children: [
                          Opacity(opacity: 0.3, child: leaderboardContent),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              decoration: BoxDecoration(
                                color: AppColors.background.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.wifi_off_rounded, color: Colors.white54, size: 36),
                                  const SizedBox(height: 12),
                                  Text(l.leaderboardOffline, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                  const SizedBox(height: 4),
                                  Text(l.leaderboardOfflineSub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return leaderboardContent;
                  },
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboardSkeleton() {
    return ListView.builder(
      itemCount: 6,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (ctx, i) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 0.7),
          duration: Duration(milliseconds: 700 + i * 80),
          curve: Curves.easeInOut,
          builder: (_, value, child) => Opacity(opacity: value, child: child),
          onEnd: () {},
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.surfaceHighlight),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    height: 13,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 60, height: 13,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceHighlight),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaderRow(BuildContext context, int rank, String name, String stat, String medal, Color medalColor, {bool isMe = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? Colors.purpleAccent.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe ? Colors.purpleAccent.withValues(alpha: 0.5) : AppColors.surfaceHighlight,
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: medal == 'NEW'
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: medalColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: medalColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(medal, style: TextStyle(fontSize: 9, color: medalColor, fontWeight: FontWeight.w900, letterSpacing: 0.5), textAlign: TextAlign.center),
                  )
                : Text(medal, style: TextStyle(fontSize: rank <= 3 ? 22 : 14, color: medalColor, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, style: TextStyle(color: isMe ? Colors.white : Colors.white70, fontWeight: isMe ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
          ),
          if (isMe)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.purpleAccent, borderRadius: BorderRadius.circular(10)),
              child: Text(AppLocalizations.of(context).you, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          Text(stat, style: const TextStyle(color: AppColors.primaryDanger, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

/// High-contrast theme for outdoor / direct-sunlight use (persisted). Tap sun to toggle.
class _OutdoorContrastToggle extends ConsumerWidget {
  const _OutdoorContrastToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(highContrastOpsProvider);
    return Tooltip(
      message: on ? 'Outdoor contrast on (tap to turn off)' : 'Outdoor contrast off (tap to turn on)',
      child: Material(
        color: on ? Colors.amber.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => ref.read(highContrastOpsProvider.notifier).setEnabled(!on),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(
              Icons.wb_sunny_rounded,
              size: 24,
              color: on ? Colors.amber.shade200 : Colors.white38,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Volunteer Toggle Widget ───────────────────────────────────────────────

class _VolunteerToggle extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VolunteerToggle> createState() => _VolunteerToggleState();
}

class _VolunteerToggleState extends ConsumerState<_VolunteerToggle> {
  DateTime? _dutyStartTime;

  @override
  Widget build(BuildContext context) {
    final isOnDuty = ref.watch(isOnDutyProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOnDuty ? AppColors.primaryDanger.withValues(alpha: 0.1) : AppColors.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isOnDuty ? AppColors.primaryDanger : AppColors.surfaceHighlight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOnDuty ? Icons.sensors_rounded : Icons.sensors_off_rounded,
            color: isOnDuty ? AppColors.primaryDanger : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isOnDuty ? AppLocalizations.of(context).onDuty : AppLocalizations.of(context).standby,
            style: TextStyle(
              color: isOnDuty ? AppColors.primaryDanger : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: isOnDuty,
              activeColor: AppColors.primaryDanger,
              onChanged: (val) async {
                if (val) {
                  // Going ON DUTY
                  _dutyStartTime = DateTime.now();
                  ref.read(isOnDutyProvider.notifier).toggle(true);
                  unawaited(VolunteerPresenceService.publishDutyPresence(onDuty: true));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🟢 ${AppLocalizations.of(context).onDutySnack}')),
                  );
                } else {
                  // Going OFF DUTY — drop persisted response + record session
                  await IncidentService.clearVolunteerAssignment();
                  ref.read(isOnDutyProvider.notifier).toggle(false);
                  unawaited(VolunteerPresenceService.publishDutyPresence(onDuty: false));
                  if (_dutyStartTime != null) {
                    await recordDutySession(_dutyStartTime!);
                    _dutyStartTime = null;
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('⚪ ${AppLocalizations.of(context).offDutySnack}')),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Small caption under the duty toggle: how many other on-duty volunteers are in the same grid radius as the map.
class _OnDutyVolunteersHint extends ConsumerStatefulWidget {
  const _OnDutyVolunteersHint();

  @override
  ConsumerState<_OnDutyVolunteersHint> createState() => _OnDutyVolunteersHintState();
}

class _OnDutyVolunteersHintState extends ConsumerState<_OnDutyVolunteersHint> {
  LatLng? _center;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_syncCenter()));
  }

  Future<void> _syncCenter() async {
    if (!context.mounted) return;
    setState(() => _locating = true);
    try {
      Position? p = await Geolocator.getLastKnownPosition();
      p ??= await Geolocator.getCurrentPosition();
      if (!context.mounted) return;
      setState(() {
        _center = LatLng(p!.latitude, p.longitude);
        _locating = false;
      });
    } catch (_) {
      if (!context.mounted) return;
      setState(() {
        _center = null;
        _locating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapAsync = ref.watch(onDutyVolunteersSnapshotProvider);
    final l = AppLocalizations.of(context);

    final String text;
    if (_locating) {
      text = l.nearbyVolunteersLocating;
    } else if (_center == null) {
      text = l.activeVolunteersGridNone;
    } else {
      text = snapAsync.when(
        data: (snap) {
          final n = VolunteerPresenceService.filterNearby(
            snap.docs,
            _center!,
            VolunteerPresenceService.defaultNearbyRadiusM,
            excludeUid: FirebaseAuth.instance.currentUser?.uid,
          ).length;
          return l.activeVolunteersGridCount(n);
        },
        loading: () => l.nearbyVolunteersLocating,
        error: (_, __) => l.activeVolunteersGridNone,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 168),
        child: Text(
          text,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// When SOS-response leaderboard is empty: explain ranks + optional solo-on-duty hint + link to grid.
Widget _leaderboardEmptyPlaceholder(
  BuildContext context, {
  required bool soloOnDuty,
  required VoidCallback onViewGrid,
}) {
  final l = AppLocalizations.of(context);
  return Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined, size: 42, color: Colors.white.withValues(alpha: 0.22)),
          const SizedBox(height: 14),
          Text(
            l.leaderboardEmptyPrimary,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l.leaderboardEmptySecondary,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              height: 1.45,
            ),
          ),
          if (soloOnDuty) ...[
            const SizedBox(height: 14),
            Text(
              l.leaderboardSoloOnDuty,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: onViewGrid,
            icon: const Icon(Icons.map_rounded, color: AppColors.primaryInfo, size: 20),
            label: Text(
              l.leaderboardViewGrid,
              style: const TextStyle(color: AppColors.primaryInfo, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
