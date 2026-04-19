import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/fleet_gate_credentials_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Master console: show or rotate `ops_fleet_accounts` password for a unit.
class FleetCredentialsDialog extends StatefulWidget {
  const FleetCredentialsDialog({
    super.key,
    required this.fleetCallSign,
    required this.vehicleType,
  });

  final String fleetCallSign;
  final String vehicleType;

  @override
  State<FleetCredentialsDialog> createState() => _FleetCredentialsDialogState();
}

class _FleetCredentialsDialogState extends State<FleetCredentialsDialog> {
  bool _loadingMeta = true;
  bool _loadingAction = false;
  bool _alreadyHasAccount = false;
  String? _password;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGateFlag();
  }

  Future<void> _loadGateFlag() async {
    final has = await FleetGateCredentialsService.gateAccountExists(
      widget.fleetCallSign,
    );
    String? existingPw;
    if (has) {
      existingPw = await FleetGateCredentialsService.readPassword(
        widget.fleetCallSign,
      );
    }
    if (!mounted) return;
    setState(() {
      _alreadyHasAccount = has;
      if (existingPw != null && existingPw.isNotEmpty) {
        _password = existingPw;
      }
      _loadingMeta = false;
    });
  }

  Future<void> _getCredentials() async {
    setState(() {
      _loadingAction = true;
      _error = null;
    });
    try {
      final pw = await FleetGateCredentialsService.ensureGateAccount(
        fleetCallSign: widget.fleetCallSign,
        vehicleType: widget.vehicleType,
      );
      if (!mounted) return;
      setState(() {
        _password = pw;
        _alreadyHasAccount = true;
        _loadingAction = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingAction = false;
      });
    }
  }

  Future<void> _resetCredentials() async {
    setState(() {
      _loadingAction = true;
      _error = null;
    });
    try {
      final pw = await FleetGateCredentialsService.rotatePassword(
        fleetCallSign: widget.fleetCallSign,
        vehicleType: widget.vehicleType,
      );
      if (!mounted) return;
      setState(() {
        _password = pw;
        _alreadyHasAccount = true;
        _loadingAction = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingAction = false;
      });
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.slate700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.fleetCallSign.trim();
    final primaryCta =
        _alreadyHasAccount ? 'Reset credentials' : 'Get credentials';

    return Dialog(
      backgroundColor: AppColors.slate800,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loadingMeta
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accentBlue),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _alreadyHasAccount
                                ? Icons.directions_car_filled
                                : Icons.local_shipping_outlined,
                            color: Colors.orangeAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.opsTr('Fleet credentials'), style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                cs,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white54,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (_password != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.orangeAccent.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(context.opsTr('Operator sign-in (fleet console)'), style: TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _row(
                              'Call sign',
                              cs,
                              Icons.badge_outlined,
                            ),
                            const SizedBox(height: 8),
                            _row(
                              'Password',
                              _password!,
                              Icons.lock_outline,
                            ),
                            const SizedBox(height: 8),
                            const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.white38,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Resetting credentials invalidates the previous password immediately.',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _loadingAction ? null : _resetCredentials,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: Text(context.opsTr('Reset credentials')),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orangeAccent,
                                foregroundColor: Colors.black,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: Text(context.opsTr('Done')),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const Text(
                        'Creates or reveals the gate password in Firestore (ops_fleet_accounts). '
                        'Operators use this call sign and password on the fleet console.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadingAction
                            ? null
                            : (_alreadyHasAccount
                                ? _resetCredentials
                                : _getCredentials),
                        icon: _loadingAction
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(
                                _alreadyHasAccount ? Icons.refresh : Icons.vpn_key,
                                size: 18,
                              ),
                        label: Text(
                          _loadingAction ? 'Working...' : primaryCta,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => _copy(value, label),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.copy, color: Colors.white54, size: 14),
          ),
        ),
      ],
    );
  }
}
