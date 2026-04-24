import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/drill_session_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/incident_service.dart';
import '../../../services/staff_session_service.dart';
import '../../../services/drill_session_persistence.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
    
    _checkRouting();
  }

  Future<void> _checkRouting() async {
    // Wait for the animation to feel smooth (minimum 2s splash)
    await Future.delayed(const Duration(seconds: 2));
    if (!context.mounted) return;

    try {
      try {
        await IncidentService.autoArchiveExpiredIncidents()
            .timeout(const Duration(seconds: 14));
      } catch (_) {}

      final user = FirebaseAuth.instance.currentUser;

      // ── Security: always clear staff / admin sessions on fresh launch ────────
      // Staff roles (admin panel, fleet gateway) must never auto-resume.
      // Users must authenticate every time they open the app.
      await StaffSessionService.clearRole();
      
      // Drill sessions are also cleared on fresh launch so back-nav doesn't
      // accidentally re-enter drill mode. If the user was anonymous (only used for drills), sign them out.
      await DrillSessionPersistence.clear();
      
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('active_sos_incident_id') == AppConstants.drillIncidentId) {
        await prefs.remove('active_sos_incident_id');
      }
      if (prefs.getString(IncidentService.prefVolunteerIncidentId) == AppConstants.drillIncidentId) {
        await IncidentService.clearVolunteerAssignment();
      }
      
      if (user != null && user.isAnonymous) {
        await FirebaseAuth.instance.signOut();
        // Since we signed out, clear any other stale local state.
        await IncidentService.clearVolunteerAssignment();
        if (context.mounted) {
          ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
          ref.read(drillVictimPracticeShellProvider.notifier).set(false);
          context.go('/login');
        }
        return;
      }

      ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
      ref.read(drillVictimPracticeShellProvider.notifier).set(false);

      // ── Regular-user crash recovery ────────────────────────────────────────
      // SECURITY: All local pref / crash-recovery checks are gated behind
      // FirebaseAuth.currentUser so that stale SharedPreferences / IndexedDB
      // data on web (e.g. from a previous non-incognito session) cannot route
      // an unauthenticated user into the volunteer or SOS screens.
      if (user != null) {
        // 1. Fast path: check SharedPreferences for an active SOS this user started.
        final localSosId = await IncidentService.checkActiveSosOnStartup();
        if (localSosId != null && localSosId.isNotEmpty) {
          if (localSosId == AppConstants.drillIncidentId) {
            if (context.mounted) {
              context.go('/sos-active/${Uri.encodeComponent(localSosId)}?drill=1');
            }
            return;
          }
          if (context.mounted) context.go('/sos-active/${Uri.encodeComponent(localSosId)}');
          return;
        }

        // 2. Check for Active Volunteer Assignment (Volunteer Crash Recovery)
        final assignment = await IncidentService.loadVolunteerAssignment();
        final volId = assignment.incidentId;
        if (volId != null && volId.isNotEmpty) {
          final type = assignment.incidentType ?? 'Emergency';
          if (context.mounted) {
            final q = volId == AppConstants.drillIncidentId ? '&drill=1' : '';
            context.go(
              '/active-consignment/${Uri.encodeComponent(volId)}?type=${Uri.encodeComponent(type)}$q',
            );
          }
          return;
        }

        if (context.mounted) {
          ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
          ref.read(drillVictimPracticeShellProvider.notifier).set(false);
          context.go('/dashboard');
        }
      } else {
        // Not signed in — clear any stale local state and send to login.
        await DrillSessionPersistence.clear();
        await IncidentService.clearVolunteerAssignment();
        if (context.mounted) {
          ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
          ref.read(drillVictimPracticeShellProvider.notifier).set(false);
          context.go('/login');
        }
      }
    } catch (_) {
      // Prefer resuming SOS / volunteer mission from local prefs if Firestore/auth checks failed.
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.isAnonymous) {
          await FirebaseAuth.instance.signOut();
          await DrillSessionPersistence.clear();
          await IncidentService.clearVolunteerAssignment();
          if (context.mounted) {
            ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
            ref.read(drillVictimPracticeShellProvider.notifier).set(false);
            context.go('/login');
          }
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        if (user != null && (prefs.getBool(DrillSessionPersistence.prefKeyActive) ?? false)) {
          final victim = prefs.getBool(DrillSessionPersistence.prefKeyVictimPractice) ?? false;
          ref.read(drillSessionDashboardDemoProvider.notifier).set(true);
          ref.read(drillVictimPracticeShellProvider.notifier).set(victim);
          if (context.mounted) context.go('/drill/dashboard');
          return;
        }
        // SECURITY: Only resume an active SOS if the user is actually signed in.
        final sos = user != null ? prefs.getString('active_sos_incident_id')?.trim() : null;
        if (sos != null && sos.isNotEmpty) {
          if (sos == AppConstants.drillIncidentId) {
            if (context.mounted) context.go('/sos-active/${Uri.encodeComponent(sos)}?drill=1');
            return;
          }
          if (context.mounted) context.go('/sos-active/${Uri.encodeComponent(sos)}');
          return;
        }
        final vol = prefs.getString(IncidentService.prefVolunteerIncidentId)?.trim();
        if (vol != null && vol.isNotEmpty && FirebaseAuth.instance.currentUser != null) {
          final t = (prefs.getString(IncidentService.prefVolunteerIncidentType) ?? 'Emergency').trim();
          final q = vol == AppConstants.drillIncidentId ? '&drill=1' : '';
          if (context.mounted) {
            context.go(
              '/active-consignment/${Uri.encodeComponent(vol)}?type=${Uri.encodeComponent(t.isEmpty ? 'Emergency' : t)}$q',
            );
          }
          return;
        }
      } catch (_) {}
      if (context.mounted) {
        ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
        ref.read(drillVictimPracticeShellProvider.notifier).set(false);
        context.go('/login');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.asset(
                  AppConstants.splashLogoPath,
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.medical_services_rounded,
                    size: 72,
                    color: AppColors.primaryDanger,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Designed to save lives',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
