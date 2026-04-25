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

  static const _staffAccent = Color(0xFFFF6B35);
  bool _staffExpanded = true;

  Widget _buildStaffPortalsSection() {
    final disabled = _isLoading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: disabled ? null : () => setState(() => _staffExpanded = !_staffExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 22,
                    color: _staffAccent.withValues(alpha: 0.95),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff Portals',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Access Fleet, Hospital or Admin dashboards',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.white54,
                                height: 1.25,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _staffExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: Colors.white54,
                  ),
                ],
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
                // Fleet Operator App
                _StaffPortalButton(
                  icon: Icons.local_shipping_rounded,
                  label: 'Fleet Operator App',
                  subtitle: 'emergencyos-fleet.web.app',
                  color: const Color(0xFF64B5F6),
                  onTap: disabled ? null : _enterFleetConsole,
                ),
                const SizedBox(height: 10),
                // Hospital Dashboard
                _StaffPortalButton(
                  icon: Icons.local_hospital_rounded,
                  label: 'Hospital Dashboard',
                  subtitle: 'emergencyos-hospital.web.app',
                  color: const Color(0xFF81C784),
                  onTap: disabled ? null : _enterHospitalConsole,
                ),
                const SizedBox(height: 10),
                // Master Admin Dashboard
                _StaffPortalButton(
                  icon: Icons.shield_rounded,
                  label: 'Master Admin Dashboard',
                  subtitle: 'emergencyos-admin.web.app',
                  color: _staffAccent,
                  onTap: disabled ? null : _enterAdminConsole,
                ),
              ],
            ),
          ),
          crossFadeState: _staffExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
                    else ...[
                      Text(
                        'LOGIN TO VICTIM/VOLUNTEER APP',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              letterSpacing: 1.2,
                            ),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 10),
                      _buildStaffPortalsSection(),
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

/// A compact staff portal entry row with an icon, label, subtitle and tap handler.
class _StaffPortalButton extends StatelessWidget {
  const _StaffPortalButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
