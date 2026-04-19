import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_root_navigator_key.dart';

/// In-memory only: fake home dashboard (leaderboard/stats) during an explicit drill-from-login session.
/// Never persisted — cleared on real sign-in, cold start → dashboard, and when drill screens close.
class DrillSessionDashboardDemoNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
  void clear() => state = false;
}

final drillSessionDashboardDemoProvider =
    NotifierProvider<DrillSessionDashboardDemoNotifier, bool>(
        DrillSessionDashboardDemoNotifier.new);

void clearDrillSessionDashboardDemoFromRoot() {
  final ctx = appRootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  ProviderScope.containerOf(ctx, listen: false)
      .read(drillSessionDashboardDemoProvider.notifier)
      .clear();
}

/// True after victim drill from login until practice SOS closes — shell FAB opens practice, not a live SOS.
class DrillVictimPracticeShellNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
  void clear() => state = false;
}

final drillVictimPracticeShellProvider =
    NotifierProvider<DrillVictimPracticeShellNotifier, bool>(
        DrillVictimPracticeShellNotifier.new);

void clearDrillVictimPracticeShellFromRoot() {
  final ctx = appRootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  ProviderScope.containerOf(ctx, listen: false)
      .read(drillVictimPracticeShellProvider.notifier)
      .clear();
}
