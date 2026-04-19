import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/staff_session_service.dart';
import '../navigation/app_root_navigator_key.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/sos/presentation/sos_screen.dart';
import '../../features/sos/presentation/sos_quick_intake_page.dart';
import '../../features/sos/presentation/sos_active_locked_screen.dart';
import '../../features/sos/presentation/post_incident_feedback_screen.dart';
import '../../features/ai_assist/presentation/ai_assist_screen.dart';
import '../../features/ai_assist/presentation/triage_camera_screen.dart';
import '../../features/profile/presentation/profile_hub_screen.dart';
import '../../features/profile/presentation/general_preferences_screen.dart';
import '../../features/profile/presentation/emergency_settings_screen.dart';
import '../../features/profile/presentation/medical_details_screen.dart';
import '../../features/profile/presentation/privacy_policy_screen.dart';
import '../../features/profile/presentation/help_screen.dart';
import '../../features/profile/presentation/volunteer_details_screen.dart';
import '../../features/family/presentation/family_tracker_screen.dart';
import '../../features/volunteers/presentation/active_consignment_screen.dart';
import '../../features/ptt/presentation/ptt_channel_screen.dart';
import '../../features/staff/navigation/ops_admin_routes.dart';
import '../../features/staff/presentation/admin_panel_screen.dart';
import '../../features/staff/presentation/emergency_services_panel_screen.dart';
import '../../features/staff/presentation/fleet_comms_operation_screen.dart';
import '../../features/staff/presentation/fleet_emergency_bridge_screen.dart';
import '../../core/widgets/main_navigation_shell.dart';
import 'app_variant.dart';

final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter(AppVariant variant) {
  return GoRouter(
    navigatorKey: appRootNavigatorKey,
    initialLocation: switch (variant) {
      AppVariant.admin => OpsAdminRoutes.masterDashboard,
      AppVariant.fleet => '/fleet',
      AppVariant.main => '/',
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/login',
        redirect: (context, state) {
          if (variant == AppVariant.admin) return OpsAdminRoutes.masterDashboard;
          return null;
        },
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/ops-dashboard',
        redirect: (context, state) {
          final q = state.uri.query;
          return q.isEmpty
              ? OpsAdminRoutes.masterDashboard
              : '${OpsAdminRoutes.masterDashboard}?$q';
        },
      ),
      GoRoute(
        path: OpsAdminRoutes.masterDashboard,
        redirect: (context, state) async {
          if (variant == AppVariant.admin) return null;
          if (FirebaseAuth.instance.currentUser == null) return '/login';
          final role = await StaffSessionService.loadRole();
          if (role != StaffConsoleRole.admin) return '/login';
          return null;
        },
        builder: (context, state) => OpsDashboardScreen(
          focusIncidentId: state.uri.queryParameters['focus'],
        ),
      ),
      GoRoute(
        path: OpsAdminRoutes.hospitalDashboard,
        redirect: (context, state) async {
          if (variant == AppVariant.admin) return null;
          if (FirebaseAuth.instance.currentUser == null) return '/login';
          final role = await StaffSessionService.loadRole();
          if (role != StaffConsoleRole.admin) return '/login';
          return null;
        },
        builder: (context, state) => OpsDashboardScreen(
          focusIncidentId: state.uri.queryParameters['focus'],
        ),
      ),

      // Fleet operator hosting entrypoint.
      GoRoute(
        path: '/fleet',
        builder: (context, state) => EmergencyServicesPanelScreen(
          focusIncidentId: state.uri.queryParameters['focus'],
        ),
      ),
      GoRoute(
        path: '/fleet-live/emergency/:incidentId',
        builder: (context, state) {
          final id = state.pathParameters['incidentId'] ?? '';
          return FleetEmergencyBridgeScreen(incidentId: id);
        },
      ),
      GoRoute(
        path: '/fleet-live/operation/:incidentId',
        builder: (context, state) {
          final id = state.pathParameters['incidentId'] ?? '';
          final h = state.uri.queryParameters['h'];
          return FleetCommsOperationScreen(
            incidentId: id,
            boundHospitalDocId: (h != null && h.isNotEmpty) ? h : null,
          );
        },
      ),

      // Keep legacy combined-app URL working, but prefer /fleet on fleet hosting.
      GoRoute(
        path: '/emergency-services',
        redirect: (context, state) async {
          if (variant == AppVariant.fleet) {
            final q = state.uri.query;
            return q.isEmpty ? '/fleet' : '/fleet?$q';
          }
          if (FirebaseAuth.instance.currentUser == null) return '/login';
          final role = await StaffSessionService.loadRole();
          if (role != StaffConsoleRole.emergencyServices) return '/login';
          return null;
        },
        builder: (context, state) => EmergencyServicesPanelScreen(
          focusIncidentId: state.uri.queryParameters['focus'],
        ),
      ),
      GoRoute(
        path: '/sos-active/:incidentId',
        redirect: (context, state) {
          if (FirebaseAuth.instance.currentUser == null) return '/login';
          return null;
        },
        builder: (context, state) {
          final incidentId = state.pathParameters['incidentId'] ?? '';
          final isDrill = state.uri.queryParameters['drill'] == '1';
          return SosActiveLockedScreen(
            incidentId: incidentId,
            isDrillMode: isDrill,
          );
        },
      ),
      GoRoute(
        path: '/family-tracker/:incidentId',
        builder: (context, state) {
          final id = state.pathParameters['incidentId'] ?? '';
          final token = state.uri.queryParameters['t'];
          return FamilyTrackerScreen(incidentId: id, token: token);
        },
      ),
      GoRoute(
        path: '/incident-feedback/:incidentId',
        builder: (context, state) {
          final incidentId = state.pathParameters['incidentId'] ?? '';
          final closed = state.uri.queryParameters['closed'];
          return PostIncidentFeedbackScreen(
            incidentId: incidentId,
            closureHint: closed,
          );
        },
      ),
      GoRoute(
        path: '/active-consignment/:incidentId',
        redirect: (context, state) {
          if (FirebaseAuth.instance.currentUser == null) return '/login';
          return null;
        },
        builder: (context, state) {
          final id = state.pathParameters['incidentId'] ?? '';
          final type = state.uri.queryParameters['type'] ?? 'Emergency';
          final isVictimStr = state.uri.queryParameters['isVictim'] ?? 'false';
          final isDrill = state.uri.queryParameters['drill'] == '1';
          return ActiveConsignmentScreen(
            incidentId: id,
            incidentType: type,
            isVictim: isVictimStr == 'true',
            isDrillMode: isDrill,
          );
        },
      ),
      GoRoute(
        path: '/triage',
        builder: (context, state) {
          final incidentId = state.uri.queryParameters['incidentId'];
          return TriageCameraScreen(incidentId: (incidentId != null && incidentId.isNotEmpty) ? incidentId : null);
        },
      ),
      GoRoute(
        path: '/ptt-channel/:incidentId',
        builder: (context, state) {
          final incidentId = state.pathParameters['incidentId'] ?? '';
          final incidentType = state.uri.queryParameters['type'] ?? 'Emergency';
          return PttChannelScreen(incidentId: incidentId, incidentType: incidentType);
        },
      ),

      if (variant == AppVariant.main)
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => MainNavigationShell(child: child),
          routes: [
            GoRoute(
              path: '/dashboard',
              redirect: (context, state) {
                if (FirebaseAuth.instance.currentUser == null) return '/login';
                return null;
              },
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(path: '/map', builder: (context, state) => const MapScreen()),
            GoRoute(path: '/sos', builder: (context, state) => const SosScreen()),
            GoRoute(path: '/sos-intake', builder: (context, state) => const SosQuickIntakePage()),
            GoRoute(
              path: '/lifeline',
              builder: (context, state) {
                final openAid = state.uri.queryParameters['openAid'];
                final mode = state.uri.queryParameters['mode'];
                final incidentId = state.uri.queryParameters['incidentId'];
                return AIAssistScreen(
                  openAid: openAid,
                  mode: mode,
                  incidentId: incidentId,
                );
              },
            ),
            GoRoute(
              path: '/profile',
              redirect: (context, state) {
                if (FirebaseAuth.instance.currentUser == null) return '/login';
                return null;
              },
              builder: (context, state) => const ProfileHubScreen(),
              routes: [
                GoRoute(
                  path: 'preferences',
                  builder: (context, state) => const GeneralPreferencesScreen(),
                ),
                GoRoute(
                  path: 'emergency',
                  builder: (context, state) => const EmergencySettingsScreen(),
                ),
                GoRoute(
                  path: 'medical',
                  builder: (context, state) => const MedicalDetailsScreen(),
                ),
                GoRoute(
                  path: 'privacy',
                  builder: (context, state) => const PrivacyPolicyScreen(),
                ),
                GoRoute(
                  path: 'help',
                  builder: (context, state) => const HelpScreen(),
                ),
                GoRoute(
                  path: 'volunteer',
                  builder: (context, state) => const VolunteerDetailsScreen(),
                ),
              ],
            ),
            GoRoute(path: '/home', redirect: (context, state) => '/dashboard'),

            GoRoute(
              path: '/drill',
              redirect: (context, state) => '/drill/dashboard',
            ),
            GoRoute(
              path: '/drill/dashboard',
              builder: (context, state) => const DashboardScreen(isDrillShell: true),
            ),
            GoRoute(
              path: '/drill/map',
              builder: (context, state) => const MapScreen(isDrillShell: true),
            ),
            GoRoute(
              path: '/drill/sos-intake',
              builder: (context, state) => const SosQuickIntakePage(isDrillShell: true),
            ),
            GoRoute(
              path: '/drill/lifeline',
              builder: (context, state) {
                final openAid = state.uri.queryParameters['openAid'];
                final mode = state.uri.queryParameters['mode'];
                final incidentId = state.uri.queryParameters['incidentId'];
                return AIAssistScreen(
                  openAid: openAid,
                  mode: mode,
                  incidentId: incidentId,
                  isDrillShell: true,
                );
              },
            ),
            GoRoute(
              path: '/drill/profile',
              builder: (context, state) => const ProfileHubScreen(isDrillShell: true),
              routes: [
                GoRoute(
                  path: 'preferences',
                  builder: (context, state) => const GeneralPreferencesScreen(),
                ),
                GoRoute(
                  path: 'emergency',
                  builder: (context, state) => const EmergencySettingsScreen(),
                ),
                GoRoute(
                  path: 'medical',
                  builder: (context, state) => const MedicalDetailsScreen(),
                ),
                GoRoute(
                  path: 'privacy',
                  builder: (context, state) => const PrivacyPolicyScreen(),
                ),
                GoRoute(
                  path: 'help',
                  builder: (context, state) => const HelpScreen(),
                ),
                GoRoute(
                  path: 'volunteer',
                  builder: (context, state) => const VolunteerDetailsScreen(),
                ),
              ],
            ),
          ],
        ),
    ],
  );
}

