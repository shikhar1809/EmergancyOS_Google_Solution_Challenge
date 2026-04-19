import 'package:flutter/material.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Stub - full channel screen is embedded in bridge_home_screen.dart
class BridgeChannelScreen extends StatelessWidget {
  const BridgeChannelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Text(
          context.opsTr('Use BridgeHomeScreen instead'),
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}
