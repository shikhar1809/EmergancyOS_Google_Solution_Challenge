import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:emergency_os/core/constants/app_constants.dart';
import 'package:emergency_os/core/constants/demo_credentials.dart';
import 'package:emergency_os/core/constants/demo_gate_password.dart';
import 'package:emergency_os/core/theme/app_colors.dart';
import 'package:emergency_os/services/admin_panel_session_service.dart';
import 'package:emergency_os/services/ops_hospital_service.dart';
import 'package:emergency_os/services/staff_session_service.dart';
import '../domain/admin_panel_access.dart';
import '../navigation/ops_admin_routes.dart';

import '../domain/command_center_accent.dart';
import 'admin_analytics_dashboard.dart';
import 'admin_command_center_screen.dart';
import 'admin_fleet_management_screen.dart';
import 'comms_bridge_screen.dart';
import 'hospital_live_ops_screen.dart' show HospitalLiveOperationsScreen;
import 'admin_reports_hub_screen.dart';
import 'master_management_hub_screen.dart';
import 'master_insights_screen.dart';
import 'master_systems_hub_screen.dart';
import 'widgets/master_dashboard_health_bar.dart';
import 'widgets/ops_dashboard_status_bar.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class OpsDashboardScreen extends ConsumerStatefulWidget {
  const OpsDashboardScreen({super.key, this.focusIncidentId});

  /// Optional deep-link from router query `?focus=`.
  final String? focusIncidentId;

  @override
  ConsumerState<OpsDashboardScreen> createState() => _OpsDashboardScreenState();
}

class _OpsDashboardScreenState extends ConsumerState<OpsDashboardScreen> {
  int _selectedIndex = 0;
  AdminPanelAccess? _access;
  bool _loading = true;

  /// From `?comms=operation|emergency` + `?focus=<incidentId>`: switch to Comms and join.
  CommsPendingJoin? _commsPendingJoin;
  String? _appliedRouteCommsSig;
  String? _appliedDockFocusSig;

  AdminConsoleRole _gateRole = AdminConsoleRole.master;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _hospitalIdCtrl = TextEditingController();

  bool _checkingCredentials = false;
  bool _showingSuccessMessage = false;

  /// Set when medical gate succeeds — `ops_hospitals` `name`, else hospital doc id.
  String? _medicalGateSuccessFacility;

  /// Avoid resetting gate role dropdown on every rebuild; sync when URL path changes.
  String? _lastSyncedGatePath;

  final DateTime _dashboardSessionStarted = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Pre-fill demo credentials for judge demo access.
    const demoEmail = DemoCredentials.adminEmail;
    const demoPw = DemoCredentials.adminPassword;
    const demoHospitalId = DemoCredentials.hospitalId;
    if (demoEmail.isNotEmpty) _emailCtrl.text = demoEmail;
    if (demoPw.isNotEmpty) _passwordCtrl.text = demoPw;
    if (demoHospitalId.isNotEmpty) _hospitalIdCtrl.text = demoHospitalId;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = (user?.email ?? '').trim();
      if (user == null || (email.isEmpty && !user.isAnonymous)) {
        await AdminPanelSessionService.clear();
        if (!context.mounted) return;
        setState(() {
          _access = null;
          _loading = false;
        });
        return;
      }
      final a = await AdminPanelSessionService.load();
      if (!context.mounted) return;

      if (a != null &&
          a.role == AdminConsoleRole.medical &&
          (a.boundHospitalDocId ?? '').trim().isNotEmpty) {
        await _syncStaffHospitalToUserProfile(
          uid: user.uid,
          hospitalDocId: a.boundHospitalDocId!.trim(),
        );
      }

      if (a != null) {
        final expectedPath = OpsAdminRoutes.pathForRole(a.role);
        final currentUri = GoRouterState.of(context).uri;
        if (currentUri.path != expectedPath) {
          final next = currentUri.hasQuery ? '$expectedPath?${currentUri.query}' : expectedPath;
          context.go(next);
          // Allow the new route to rebuild this screen
          return;
        }
      }

      setState(() {
        _access = a;
        _loading = false;
        _selectedIndex = 0;
      });
    } catch (e) {
      if (!context.mounted) return;
      setState(() {
        _loading = false;
        _access = null;
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _hospitalIdCtrl.dispose();
    super.dispose();
  }

  /// Cloud Functions `acceptHospitalDispatch` / `declineHospitalDispatch` require
  /// `users/{uid}.staffHospitalId` (or `boundHospitalDocId`) to match the facility.
  /// Medical gate uses anonymous auth — merge the verified hospital id onto the profile.
  Future<void> _syncStaffHospitalToUserProfile({
    required String uid,
    required String hospitalDocId,
  }) async {
    final hid = hospitalDocId.trim();
    if (hid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        <String, dynamic>{
          'staffHospitalId': hid,
          'boundHospitalDocId': hid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      debugPrint('[admin_panel] staffHospitalId profile sync failed: $e $st');
    }
  }

  int? _commsTabIndexForAccess(AdminPanelAccess a) {
    if (!a.canUseCommsBridge) return null;
    // Master: Live Ops, Management, Systems, Analytics, Comms, Insights
    // Medical: Overview, Live Operations, Fleet, Comms
    if (a.role == AdminConsoleRole.master) return 4;
    if (a.role == AdminConsoleRole.medical) return 3;
    return null;
  }

  void _syncGateRoleFromRoute() {
    if (_access != null) return;
    late final String path;
    try {
      path = GoRouterState.of(context).uri.path;
    } catch (_) {
      return;
    }
    if (_lastSyncedGatePath == path) return;
    _lastSyncedGatePath = path;
    final medical = OpsAdminRoutes.pathPrefersMedicalGate(path);
    final want =
        medical ? AdminConsoleRole.medical : AdminConsoleRole.master;
    if (_gateRole != want) {
      setState(() => _gateRole = want);
    }
  }

  Widget _demoBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F6FEB).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF58A6FF), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF58A6FF), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF58A6FF),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _gateTitleForPath() {
    try {
      final path = GoRouterState.of(context).uri.path;
      if (OpsAdminRoutes.pathPrefersMedicalGate(path)) {
        return 'Hospital Dashboard';
      }
      return 'Master Dashboard';
    } catch (_) {
      return 'Master Dashboard';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncGateRoleFromRoute();
    final access = _access;
    if (access == null) return;
    final uri = GoRouterState.of(context).uri;
    final commsRaw = uri.queryParameters['comms']?.trim().toLowerCase() ?? '';
    final dock = uri.queryParameters['dock']?.trim().toLowerCase() ?? '';
    final focusForDock = uri.queryParameters['focus']?.trim() ?? '';
    if (dock == 'live' || dock == 'command' || dock == '0') {
      final sig = 'dock|$dock|$focusForDock';
      if (_appliedDockFocusSig != sig) {
        _appliedDockFocusSig = sig;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedIndex = 0);
          final path = OpsAdminRoutes.pathForRole(access.role);
          final params = Map<String, String>.from(uri.queryParameters);
          params.remove('dock');
          final q = Uri(queryParameters: params).query;
          context.go(q.isEmpty ? path : '$path?$q');
        });
      }
    }

    if (commsRaw != 'operation' && commsRaw != 'emergency') {
      _appliedRouteCommsSig = null;
      return;
    }
    if (!access.canUseCommsBridge) return;
    final focus = uri.queryParameters['focus']?.trim() ?? '';
    if (focus.isEmpty) return;
    final sig = '$focus|$commsRaw';
    if (_appliedRouteCommsSig == sig) return;
    _appliedRouteCommsSig = sig;
    final idx = _commsTabIndexForAccess(access);
    if (idx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = idx;
        _commsPendingJoin = CommsPendingJoin(
          incidentId: focus,
          channel: commsRaw,
        );
      });
    });
  }

  /// Firestore rules require a signed-in user for `ops_hospitals` reads.
  Future<void> _ensureFirebaseUserForGateRead() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance.signInAnonymously();
  }

  // ignore: unused_element
  Future<String?> _promptMedicalHospitalCredentials() async {
    final hid = TextEditingController();
    final pw = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(context.opsTr('Hospital login'), style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hid,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: context.opsTr('Hospital document ID'),
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pw,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: context.opsTr('Access password'),
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.opsTr('Cancel')),
          ),
          TextButton(
            onPressed: () async {
              final id = hid.text.trim().toUpperCase();
              final p = pw.text.trim();
              if (id.isEmpty || p.isEmpty) return;
              try {
                await _ensureFirebaseUserForGateRead();
                await OpsHospitalService.ensureHospitalGateDocumentsMerged();
              } catch (_) {}
              final doc = await FirebaseFirestore.instance
                  .collection('ops_hospitals')
                  .doc(id)
                  .get();
              final gate =
                  (doc.data()?['gatePassword'] ?? DemoGatePassword.value)
                      .toString()
                      .trim();
              final ok = doc.exists && gate == p;
              if (!ok) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(context.opsTr('Unknown hospital or wrong password.')),
                    ),
                  );
                }
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx, id);
            },
            child: Text(context.opsTr('OK')),
          ),
        ],
      ),
    );
  }

  /// Firebase may return [invalid-credential] instead of [user-not-found] when
  /// email enumeration protection is enabled — still try account creation in that case.
  /// Always signs out first so anonymous / prior sessions do not block email/password.
  Future<void> _signInOrCreateEmailUser(String email, String password) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return;
    } on FirebaseAuthException catch (e) {
      final code = e.code;
      if (code == 'user-not-found' || code == 'invalid-credential') {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          return;
        } on FirebaseAuthException catch (e2) {
          if (e2.code == 'email-already-in-use') {
            throw FirebaseAuthException(
              code: 'wrong-password',
              message:
                  'Incorrect password for this email. If this is the demo account, use the password shown on this screen or reset it in Firebase Console.',
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<void> _submitGate() async {
    if (_checkingCredentials || _showingSuccessMessage) return;
    setState(() => _checkingCredentials = true);
    await Future.delayed(const Duration(milliseconds: 600));

    try {
      late final AdminPanelAccess access;

      if (_gateRole == AdminConsoleRole.medical) {
        final hid = _hospitalIdCtrl.text.trim().toUpperCase();
        final pw = _passwordCtrl.text.trim();
        if (hid.isEmpty || pw.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.opsTr('Enter hospital ID and access password.')),
            ),
          );
          setState(() => _checkingCredentials = false);
          return;
        }
        await _ensureFirebaseUserForGateRead();
        await OpsHospitalService.ensureHospitalGateDocumentsMerged();
        final doc = await FirebaseFirestore.instance
            .collection('ops_hospitals')
            .doc(hid)
            .get();
        final gate = (doc.data()?['gatePassword'] ?? DemoGatePassword.value)
            .toString()
            .trim();
        if (!doc.exists || gate != pw) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unknown hospital ID or wrong password. Use the facility id and gate password from ops_hospitals.',
              ),
            ),
          );
          setState(() => _checkingCredentials = false);
          return;
        }
        final hospitalDisplay = (doc.data()?['name'] as String?)?.trim();
        _medicalGateSuccessFacility =
            (hospitalDisplay != null && hospitalDisplay.isNotEmpty)
            ? hospitalDisplay
            : hid;
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
        await FirebaseAuth.instance.signInAnonymously();
        access = AdminPanelAccess(
          role: AdminConsoleRole.medical,
          boundHospitalDocId: hid,
        );
        final nUid = FirebaseAuth.instance.currentUser?.uid;
        if (nUid != null) {
          await _syncStaffHospitalToUserProfile(uid: nUid, hospitalDocId: hid);
        }
      } else {
        final email = _emailCtrl.text.trim();
        final password = _passwordCtrl.text;
        if (email.isEmpty || password.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.opsTr('Enter admin email and password.'))),
          );
          setState(() => _checkingCredentials = false);
          return;
        }
        try {
          await _signInOrCreateEmailUser(email, password);
        } on FirebaseAuthException catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'Sign-in failed (${e.code})')),
          );
          setState(() => _checkingCredentials = false);
          return;
        }
        access = switch (_gateRole) {
          AdminConsoleRole.master => const AdminPanelAccess(
            role: AdminConsoleRole.master,
          ),
          AdminConsoleRole.medical => const AdminPanelAccess(
            role: AdminConsoleRole.medical,
            boundHospitalDocId: null,
          ),
        };
        _medicalGateSuccessFacility = null;
      }

      if (!context.mounted) return;
      setState(() {
        _checkingCredentials = false;
        _showingSuccessMessage = true;
      });
      await Future.delayed(const Duration(milliseconds: 1500));

      await AdminPanelSessionService.save(access);
      if (!context.mounted) return;
      final uri = GoRouterState.of(context).uri;
      final target = OpsAdminRoutes.pathForRole(access.role);
      final next =
          uri.hasQuery ? '$target?${uri.query}' : target;
      setState(() {
        _showingSuccessMessage = false;
        _access = access;
        _selectedIndex = 0;
      });
      if (context.mounted) context.go(next);
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _checkingCredentials = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not enter console: $e')));
    }
  }

  Future<void> _signOutConsole() async {
    final returnMedical = _access?.role == AdminConsoleRole.medical;
    await AdminPanelSessionService.clear();
    await StaffSessionService.clearRole();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!context.mounted) return;
    setState(() {
      _access = null;
      _lastSyncedGatePath = null;
      _loading = false;
      _appliedDockFocusSig = null;
    });
    context.go(
      returnMedical == true
          ? OpsAdminRoutes.hospitalDashboard
          : OpsAdminRoutes.masterDashboard,
    );
  }

  List<NavigationRailDestination> _destinationsFor(AdminPanelAccess a) {
    final list = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: const Icon(Icons.dashboard_customize),
        label: Text(
          a.role == AdminConsoleRole.medical ? 'Overview' : 'Live Ops',
        ),
      ),
    ];
    if (a.role == AdminConsoleRole.master) {
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          label: Text(context.opsTr('Management')),
        ),
      );
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.tune_rounded),
          selectedIcon: Icon(Icons.tune),
          label: Text(context.opsTr('Systems')),
        ),
      );
      if (a.canUseAnalytics) {
        list.add(
          NavigationRailDestination(
            icon: Icon(Icons.analytics),
            label: Text(context.opsTr('Analytics')),
          ),
        );
      }
      if (a.canUseCommsBridge) {
        list.add(
          NavigationRailDestination(
            icon: Icon(Icons.headset_mic_outlined),
            selectedIcon: Icon(Icons.headset_mic),
            label: Text(context.opsTr('Comms')),
          ),
        );
      }
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.insights_rounded),
          label: Text(context.opsTr('Insights')),
        ),
      );
    }
    if (a.role == AdminConsoleRole.medical) {
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.crisis_alert),
          label: Text(context.opsTr('Live Operations')),
        ),
      );
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.directions_car_filled),
          label: Text(context.opsTr('Fleet')),
        ),
      );
      if (a.canUseCommsBridge) {
        list.add(
          NavigationRailDestination(
            icon: Icon(Icons.headset_mic_outlined),
            selectedIcon: Icon(Icons.headset_mic),
            label: Text(context.opsTr('Comms')),
          ),
        );
      }
    }
    if (a.canUseAnalytics && a.role != AdminConsoleRole.master) {
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.analytics),
          label: Text(context.opsTr('Analytics')),
        ),
      );
      list.add(
        NavigationRailDestination(
          icon: Icon(Icons.description_outlined),
          label: Text(context.opsTr('Reports')),
        ),
      );
    }
    return list;
  }

  Widget _opsDockItem({
    required NavigationRailDestination destination,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme.merge(
                  data: IconThemeData(
                    color: selected ? accent : Colors.white54,
                    size: 22,
                  ),
                  child: destination.icon,
                ),
                const SizedBox(height: 4),
                DefaultTextStyle(
                  style: TextStyle(
                    color: selected ? accent : Colors.white54,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: destination.label,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _opsTaskbarDock({
    required List<NavigationRailDestination> destinations,
    required int selectedIndex,
    required Color accent,
    required DateTime sessionStartedAt,
  }) {
    return Material(
      color: const Color(0xFF1B2634),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          // Explicit height: a Stack with only [Positioned.fill] can confuse column layout
          // and starve the Expanded body above (blank master dashboard).
          child: SizedBox(
            height: 62,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < destinations.length; i++)
                          _opsDockItem(
                            destination: destinations[i],
                            selected: i == selectedIndex,
                            accent: accent,
                            onTap: () => setState(() => _selectedIndex = i),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: OpsDashboardStatusBar(
                      sessionStartedAt: sessionStartedAt,
                      dockTray: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyForIndex(AdminPanelAccess a, int i) {
    if (a.role == AdminConsoleRole.master) {
      var idx = 0;
      if (i == idx++) {
        return AdminCommandCenterScreen(
          access: a,
          focusIncidentId: widget.focusIncidentId,
          masterSidebarMode: MasterCommandSidebarMode.none,
        );
      }
      if (i == idx++) return MasterManagementHubScreen(access: a);
      if (i == idx++) return MasterSystemsHubScreen(access: a);
      if (a.canUseAnalytics) {
        if (i == idx++) return AdminAnalyticsDashboard(access: a);
      }
      if (a.canUseCommsBridge) {
        if (i == idx++) {
          return CommsBridgeScreen(
            access: a,
            pendingJoin: _commsPendingJoin,
            onPendingJoinConsumed: () {
              if (mounted) setState(() => _commsPendingJoin = null);
            },
          );
        }
      }
      if (i == idx++) return MasterInsightsScreen(access: a);
      return AdminCommandCenterScreen(
        access: a,
        focusIncidentId: widget.focusIncidentId,
        masterSidebarMode: MasterCommandSidebarMode.none,
      );
    }

    var idx = 0;
    if (i == idx++) {
      return AdminCommandCenterScreen(
        access: a,
        focusIncidentId: widget.focusIncidentId,
      );
    }
    if (a.role == AdminConsoleRole.medical) {
      if (i == idx++) {
        return HospitalLiveOperationsScreen(access: a);
      }
      if (i == idx++) {
        return AdminFleetManagementScreen(access: a);
      }
      if (a.canUseCommsBridge) {
        if (i == idx++) {
          return CommsBridgeScreen(
            access: a,
            pendingJoin: _commsPendingJoin,
            onPendingJoinConsumed: () {
              if (mounted) setState(() => _commsPendingJoin = null);
            },
          );
        }
      }
      if (a.canUseAnalytics) {
        if (i == idx++) return AdminAnalyticsDashboard(access: a);
        if (i == idx++) return AdminReportsHubScreen(access: a);
      }
    }
    return AdminCommandCenterScreen(
      access: a,
      focusIncidentId: widget.focusIncidentId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).size.width < 1024) {
      return Scaffold(
        backgroundColor: AppColors.slate900,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(AppConstants.logoPath, width: 120),
              const SizedBox(height: 32),
              const Icon(
                Icons.desktop_windows,
                size: 80,
                color: AppColors.accentBlue,
              ),
              const SizedBox(height: 24),
              Text(context.opsTr('Desktop Only'), style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(context.opsTr('The Admin Console requires a larger screen.'), style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.slate900,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.accentBlue),
        ),
      );
    }

    if (_access == null) {
      Widget content;

      if (_checkingCredentials || _showingSuccessMessage) {
        String message = 'Checking credentials...';
        IconData icon = Icons.lock_clock;
        Color accent = AppColors.accentBlue;

        if (_showingSuccessMessage) {
          icon = Icons.check_circle;
          switch (_gateRole) {
            case AdminConsoleRole.master:
              message = 'Authorized access as Master Controller.';
              accent = AppColors.accentBlue;
              break;
            case AdminConsoleRole.medical:
              final facility = _medicalGateSuccessFacility;
              message = (facility != null && facility.isNotEmpty)
                  ? 'Authorized access as Medical Staff of $facility.'
                  : 'Authorized access as Medical Staff.';
              accent = CommandCenterAccent.forRole(
                AdminConsoleRole.medical,
              ).primary;
              break;
          }
        }

        content = ScaleTransition(
          scale: const AlwaysStoppedAnimation(1.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _showingSuccessMessage
                    ? Icon(
                        icon,
                        size: 72,
                        color: accent,
                        key: const ValueKey('success'),
                      )
                    : SizedBox(
                        width: 72,
                        height: 72,
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 6,
                        ),
                      ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_checkingCredentials) ...[
                const SizedBox(height: 16),
                Text(context.opsTr('Verifying clearance level...'), style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ],
          ),
        );
      } else {
        content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            color: AppColors.slate800,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _gateTitleForPath(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _gateRole == AdminConsoleRole.medical
                        ? 'Medical console: enter your ops_hospitals document ID and gate password.'
                        : 'Sign in with staff email and password, then choose your console role.',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Demo hint banner
                  if (_gateRole == AdminConsoleRole.master &&
                      DemoCredentials.adminEmail.isNotEmpty) ...[
                    _demoBanner(
                      '🎯 Demo: Email & password pre-filled. Select "Master" and tap Enter console.',
                    ),
                    const SizedBox(height: 12),
                  ] else if (_gateRole == AdminConsoleRole.medical &&
                      DemoCredentials.hospitalId.isNotEmpty) ...[
                    _demoBanner(
                      '🎯 Demo: Hospital ID & password pre-filled. Tap Enter console.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: context.opsTr('Role'),
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: AppColors.slate900,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AdminConsoleRole>(
                        value: _gateRole,
                        isExpanded: true,
                        dropdownColor: AppColors.slate800,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: AdminConsoleRole.master,
                            child: Text(context.opsTr('Master — full access')),
                          ),
                          DropdownMenuItem(
                            value: AdminConsoleRole.medical,
                            child: Text(context.opsTr('Medical — EMS + hospital')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _gateRole = v);
                          // Re-sync demo password for the newly selected role.
                          const demoPw = DemoCredentials.adminPassword;
                          if (demoPw.isNotEmpty) _passwordCtrl.text = demoPw;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_gateRole == AdminConsoleRole.medical) ...[
                    TextField(
                      controller: _hospitalIdCtrl,
                      autocorrect: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: context.opsTr('Hospital ID'),
                        hintText: context.opsTr('HOSPITAL-DOC-ID'),
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: AppColors.slate900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: context.opsTr('Admin email'),
                        labelStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: AppColors.slate900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: _gateRole == AdminConsoleRole.medical
                          ? 'Hospital access password'
                          : 'Password',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: AppColors.slate900,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: (_checkingCredentials || _showingSuccessMessage)
                        ? null
                        : _submitGate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _checkingCredentials && !_showingSuccessMessage
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(context.opsTr('Enter console')),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Scaffold(
        backgroundColor: AppColors.slate900,
        body: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: content,
          ),
        ),
      );
    }

    final access = _access!;
    final destinations = _destinationsFor(access);
    final safeIndex = _selectedIndex.clamp(0, destinations.length - 1);
    final railAccent = CommandCenterAccent.forRole(access.role).primary;

    return Scaffold(
      backgroundColor: AppColors.slate900,
      resizeToAvoidBottomInset: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.slate800,
              border: Border(
                bottom: BorderSide(color: Colors.white12, width: 1),
              ),
            ),
            child: Row(
              children: [
                Image.asset(
                  AppConstants.logoPath,
                  height: 28,
                  width: 28,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.local_hospital_rounded,
                    color: AppColors.accentBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  access.role == AdminConsoleRole.master
                      ? 'Master Dashboard'
                      : 'Hospital Dashboard',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: _signOutConsole,
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: Text(context.opsTr('Log out'), style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (access.role == AdminConsoleRole.master)
            const MasterDashboardHealthBar(),
          Expanded(child: ClipRect(child: _bodyForIndex(access, safeIndex))),
          _opsTaskbarDock(
            destinations: destinations,
            selectedIndex: safeIndex,
            accent: railAccent,
            sessionStartedAt: _dashboardSessionStarted,
          ),
        ],
      ),
    );
  }
}
