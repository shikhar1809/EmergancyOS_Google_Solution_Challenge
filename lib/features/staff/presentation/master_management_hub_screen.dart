import 'package:flutter/material.dart';

import '../../../core/l10n/dashboard_l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/admin_panel_access.dart';
import '../domain/command_center_accent.dart';
import 'widgets/master_management_map_workspace.dart';

/// Master **Management** area: map-first fleet & hospitals, collapsible detail panel, onboarding rail.
class MasterManagementHubScreen extends StatelessWidget {
  const MasterManagementHubScreen({super.key, required this.access});

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
                Icon(Icons.admin_panel_settings_outlined, color: accent, size: 28),
                const SizedBox(width: 12),
                Text(
                  context.opsTr('Management'),
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: MasterManagementMapWorkspace(
              access: access,
              accent: accent,
            ),
          ),
        ],
      ),
    );
  }
}
