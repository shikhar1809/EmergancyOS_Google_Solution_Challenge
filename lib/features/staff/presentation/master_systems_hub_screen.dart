import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/admin_panel_access.dart';
import '../domain/command_center_accent.dart';
import 'widgets/master_systems_status_section.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Master **Systems** area (dock tab): integration routing, health, Firestore ping.
class MasterSystemsHubScreen extends StatelessWidget {
  const MasterSystemsHubScreen({super.key, required this.access});

  final AdminPanelAccess access;

  @override
  Widget build(BuildContext context) {
    final accent = CommandCenterAccent.forRole(access.role).primary;
    return ColoredBox(
      color: AppColors.slate900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: accent, size: 28),
                const SizedBox(width: 12),
                Text(context.opsTr('Systems'), style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: MasterSystemsStatusSection(
                accent: accent,
                initiallyExpanded: true,
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
