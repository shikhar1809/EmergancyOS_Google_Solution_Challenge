import 'dart:html' as html;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/providers/drill_session_provider.dart';
import '../../../services/drill_entry_service.dart';
import '../../../services/drill_session_persistence.dart';
import '../../../services/staff_session_service.dart';
import '../../../services/incident_service.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  bool _isPhoneAuth = false;
  bool _otpSent = false;
  /// Collapsed by default so the auth page stays calm; tap to show practice routes.
  bool _drillExpanded = false;
  
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  /// Maps raw Firebase / platform exceptions to short, user-friendly copy.
  /// Never surface the stringified exception to the user — it exposes internal
  /// error codes and looks unfinished in a demo / review.
  String _friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'No internet connection. Check your network and try again.';
        case 'user-disabled':
          return 'This account has been disabled. Contact support.';
        case 'invalid-phone-number':
          return 'That phone number doesn\u2019t look right. Please include country code.';
        case 'invalid-verification-code':
        case 'invalid-verification-id':
          return 'The code you entered isn\u2019t valid. Try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a minute and try again.';
        case 'credential-already-in-use':
        case 'account-exists-with-different-credential':
          return 'This account is already signed in somewhere else.';
        case 'operation-not-allowed':
          return 'Sign-in isn\u2019t enabled right now. Try again later.';
        case 'popup-closed-by-user':
        case 'cancelled':
        case 'user-cancelled':
          return 'Sign-in was cancelled.';
        case 'sign_in_failed':
          return 'Google sign-in failed. Please try again.';
        default:
          return error.message?.trim().isNotEmpty == true
              ? error.message!
              : 'Sign-in failed. Please try again.';
      }
    }
    final msg = error.toString();
    if (msg.toLowerCase().contains('network')) {
      return 'Network issue. Check your connection and try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _showAuthError(Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_friendlyAuthError(error)),
        backgroundColor: AppColors.primaryDanger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    await StaffSessionService.clearRole();
    setState(() => _isLoading = true);
    try {
      final user = await ref.read(authRepositoryProvider).signInWithGoogle();
      if (user != null && context.mounted) {
        ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
        ref.read(drillVictimPracticeShellProvider.notifier).set(false);
        final dest = await IncidentService.recoverEmergencyRoutePath();
        if (context.mounted) context.go(dest ?? '/home');
      }
    } catch (e) {
      _showAuthError(e);
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() => _isLoading = true);
    await ref.read(authRepositoryProvider).sendPhoneOTP(
      phone,
      onCodeSent: (verId) {
        if (context.mounted) {
          setState(() {
            _otpSent = true;
            _isLoading = false;
          });
        }
      },
      onError: (err) {
        if (context.mounted) {
          setState(() => _isLoading = false);
          _showAuthError(err);
        }
      },
    );
  }

  Future<void> _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) return;

    await StaffSessionService.clearRole();
    setState(() => _isLoading = true);
    try {
      final user = await ref.read(authRepositoryProvider).verifyPhoneOTP(otp);
      if (user != null && context.mounted) {
        ref.read(drillSessionDashboardDemoProvider.notifier).set(false);
        ref.read(drillVictimPracticeShellProvider.notifier).set(false);
        final dest = await IncidentService.recoverEmergencyRoutePath();
        if (context.mounted) context.go(dest ?? '/home');
      }
    } catch (e) {
      _showAuthError(e);
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enterAdminConsole() async {
    setState(() => _isLoading = true);
    try {
      await StaffSessionService.ensureFirebaseUserForConsole();
      await StaffSessionService.setRole(StaffConsoleRole.admin);
      if (context.mounted) context.go('/master-dashboard');
    } catch (e) {
      _showAuthError(e);
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  void _enterEmergencyServicesConsole() {
    setState(() => _isLoading = true);
    try {
      StaffSessionService.ensureFirebaseUserForConsole();
      StaffSessionService.setRole(StaffConsoleRole.emergencyServices);
      html.window.location.assign('https://emergencyos-admin.web.app');
    } catch (e) {
      _showAuthError(e);
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  void _enterHospitalConsole() {
    setState(() => _isLoading = true);
    try {
      StaffSessionService.ensureFirebaseUserForConsole();
      StaffSessionService.setRole(StaffConsoleRole.hospital);
      html.window.location.assign('https://emergencyos-hospital.web.app');
    } catch (e) {
      _showAuthError(e);
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  void _enterFleetConsole() {
    setState(() => _isLoading = true);
    try {
      StaffSessionService.ensureFirebaseUserForConsole();
      StaffSessionService.clearRole();
      html.window.location.assign('https://emergencyos-fleet.web.app/fleet');
    } catch (e) {
      _showAuthError(e);
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  static const _drillAccent = Color(0xFF4DD0E1);

  Future<void> _startVictimDrill() async {
    if (_isLoading) return;
    if (!AppConstants.demoModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo mode is disabled. Please sign in with Google or phone number.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await StaffSessionService.clearRole();
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      await DrillEntryService.arm('sos');
      await DrillSessionPersistence.activate(victimPractice: true);
      if (context.mounted) {
        ref.read(drillSessionDashboardDemoProvider.notifier).set(true);
        ref.read(drillVictimPracticeShellProvider.notifier).set(true);
        context.go('/drill/dashboard');
      }
    } catch (e) {
      _showAuthError(e);
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startVolunteerDrill() async {
    if (_isLoading) return;
    if (!AppConstants.demoModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo mode is disabled. Please sign in with Google or phone number.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await StaffSessionService.clearRole();
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      await DrillEntryService.arm('volunteer');
      await DrillSessionPersistence.activate(victimPractice: false);
      if (context.mounted) {
        ref.read(drillSessionDashboardDemoProvider.notifier).set(true);
        ref.read(drillVictimPracticeShellProvider.notifier).set(false);
        context.go('/drill/dashboard');
      }
    } catch (e) {
      _showAuthError(e);
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildDrillSection() {
    final disabled = _isLoading;
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            expanded: _drillExpanded,
            label: l.loginDrillSemantics,
            child: InkWell(
              onTap: disabled ? null : () => setState(() => _drillExpanded = !_drillExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.fitness_center_rounded,
                      size: 22,
                      color: _drillAccent.withValues(alpha: 0.95),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.loginDrillMode,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.loginDrillSubtitle,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white54,
                                  height: 1.25,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _drillExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: Colors.white54,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.tonal(
                  onPressed: disabled ? null : _startVictimDrill,
                  style: FilledButton.styleFrom(
                    backgroundColor: _drillAccent.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(l.loginPractiseVictim, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: disabled ? null : _startVolunteerDrill,
                  style: FilledButton.styleFrom(
                    backgroundColor: _drillAccent.withValues(alpha: 0.12),
                    foregroundColor: Colors.white.withValues(alpha: 0.92),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(l.loginPractiseVolunteer, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          crossFadeState: _drillExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeOutCubic,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        AppConstants.logoPath,
                        width: 88,
                        height: 88,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      l.loginTagline,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 28),

                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primaryDanger)),
                      )
                    else if (!_isPhoneAuth) ...[
                      ElevatedButton.icon(
                        onPressed: _handleGoogleSignIn,
                        icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                        label: Text(l.loginContinueGoogle),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _isPhoneAuth = true;
                          _drillExpanded = false;
                        }),
                        icon: const Icon(Icons.phone_android_rounded),
                        label: Text(l.loginContinuePhone),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Colors.white24, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          foregroundColor: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        '── STAFF DASHBOARDS ──',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _enterAdminConsole,
                              icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                              label: const Text('Admin'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.black87,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _enterHospitalConsole,
                              icon: const Icon(Icons.local_hospital_rounded, size: 18),
                              label: const Text('Hospital'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4CAF50),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildDrillSection(),
                      const SizedBox(height: 28),
                      Text(
                        l.loginAdminNote,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white38,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _enterEmergencyServicesConsole,
                        icon: const Icon(Icons.medical_services_rounded),
                        label: const Text('EMS Services'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Colors.amberAccent, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          foregroundColor: Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _enterEmergencyServicesConsole,
                        icon: const Icon(Icons.local_hospital_outlined),
                        label: Text(l.loginEmergencyOperator),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF4FC3F7), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          foregroundColor: const Color(0xFF4FC3F7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _enterHospitalConsole,
                        icon: const Icon(Icons.local_pharmacy_rounded),
                        label: const Text('Hospital Dashboard'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF81C784), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          foregroundColor: const Color(0xFF81C784),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _enterFleetConsole,
                        icon: const Icon(Icons.directions_car_rounded),
                        label: const Text('Fleet Operator'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFFFB74D), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          foregroundColor: const Color(0xFFFFB74D),
                        ),
                      ),
                    ] else if (!_otpSent) ...[
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: l.loginPhoneLabel,
                          hintText: l.loginPhoneHint,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _sendOTP,
                        child: Text(l.loginSendCode),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _isPhoneAuth = false),
                        child: Text(l.loginBackOptions, style: const TextStyle(color: Colors.white70)),
                      ),
                    ] else ...[
                      TextField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l.loginOtpLabel,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _verifyOTP,
                        child: Text(l.loginVerifyLogin),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _otpSent = false),
                        child: Text(l.loginChangePhone, style: const TextStyle(color: Colors.white70)),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
