import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../services/staff_session_service.dart';
import '../../../services/drill_session_persistence.dart';
import '../../../services/incident_service.dart';

/// Auth gate that waits for Firebase to confirm authentication after OAuth redirect.
///
/// On mobile Safari/Chrome, getRedirectResult() is unreliable. This gate uses
/// authStateChanges() + currentUser polling as the source of truth.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<User?>? _authSub;
  Timer? _pollTimer;
  bool _resolving = false;
  int _tick = 0;
  static const _maxTicks = 40; // 20 seconds max

  @override
  void initState() {
    super.initState();
    debugPrint('[AuthGate] initState');
    _startListening();
  }

  void _startListening() {
    // Listen to auth state changes (fires when redirect completes)
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      debugPrint(
        '[AuthGate] authStateChanges: user=${user?.uid ?? "null"}, isAnonymous=${user?.isAnonymous}',
      );
      if (user != null && !user.isAnonymous) {
        _resolveAuth(user);
      }
    });

    // Check immediately
    _checkCurrentUser();

    // Poll currentUser every 500ms (mobile Safari may delay restoring session)
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _tick++;
      debugPrint(
        '[AuthGate] poll $_tick: currentUser=${FirebaseAuth.instance.currentUser?.uid ?? "null"}',
      );
      _checkCurrentUser();
      if (_tick >= _maxTicks) {
        debugPrint('[AuthGate] timeout after ${_tick * 500}ms');
        _showLogin();
      }
    });
  }

  void _checkCurrentUser() {
    if (_resolving) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      _resolveAuth(user);
    }
  }

  Future<void> _resolveAuth(User user) async {
    if (_resolving) return;
    _resolving = true;
    _pollTimer?.cancel();
    _authSub?.cancel();

    debugPrint('[AuthGate] authenticated: ${user.uid}');

    if (!mounted) return;

    await StaffSessionService.clearRole();
    await DrillSessionPersistence.clear();
    if (!mounted) return;
    final dest = await IncidentService.recoverEmergencyRoutePath();
    if (!mounted) return;
    context.go(dest ?? '/dashboard');
  }

  void _showLogin() {
    if (_resolving) return;
    _resolving = true;
    _pollTimer?.cancel();
    _authSub?.cancel();

    debugPrint('[AuthGate] showing login');

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/login');
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primaryDanger),
            const SizedBox(height: 16),
            Text(
              'Signing you in...',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
