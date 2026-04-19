import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/hospital_onboarding_service.dart';
import '../../domain/hospital_staff_credentials.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class HospitalOnboardingDialog extends StatefulWidget {
  const HospitalOnboardingDialog({
    super.key,
    required this.hospitalDocId,
    required this.hospitalName,
    required this.hospitalVicinity,
    required this.adminEmail,
    this.alreadyOnboarded = false,
    this.onboardingLatitude,
    this.onboardingLongitude,
  });

  final String hospitalDocId;
  final String hospitalName;
  final String hospitalVicinity;
  final String adminEmail;
  final bool alreadyOnboarded;
  /// Saved to `ops_hospitals` with staff credentials (e.g. from map pick).
  final double? onboardingLatitude;
  final double? onboardingLongitude;

  @override
  State<HospitalOnboardingDialog> createState() =>
      _HospitalOnboardingDialogState();
}

class _HospitalOnboardingDialogState extends State<HospitalOnboardingDialog> {
  bool _loading = false;
  HospitalStaffCredentials? _generatedCredentials;
  String? _error;

  Future<void> _onboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final creds = await HospitalOnboardingService.onboardHospital(
        hospitalDocId: widget.hospitalDocId,
        adminEmail: widget.adminEmail,
        latitude: widget.onboardingLatitude,
        longitude: widget.onboardingLongitude,
        displayName: widget.hospitalName,
        region: widget.hospitalVicinity,
      );
      if (!mounted) return;
      setState(() {
        _generatedCredentials = creds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await HospitalOnboardingService.regenerateCredentials(
        widget.hospitalDocId,
        widget.adminEmail,
      );
      final creds = HospitalStaffCredentials.generate(widget.hospitalDocId);
      if (!mounted) return;
      setState(() {
        _generatedCredentials = creds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
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
    final primaryCtaLabel =
        widget.alreadyOnboarded ? 'Reset credentials' : 'Get credentials';
    return Dialog(
      backgroundColor: AppColors.slate800,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.alreadyOnboarded
                          ? Icons.check_circle
                          : Icons.add_business,
                      color: Colors.cyanAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hospital credentials',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          widget.hospitalName,
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
              if (widget.hospitalVicinity.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    widget.hospitalVicinity,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ),
              if (widget.onboardingLatitude != null &&
                  widget.onboardingLongitude != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.place_rounded,
                        size: 16,
                        color: Colors.cyanAccent.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Exact map location:\n'
                          '${widget.onboardingLatitude!.toStringAsFixed(6)}, '
                          '${widget.onboardingLongitude!.toStringAsFixed(6)}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
              if (_generatedCredentials != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(context.opsTr('Staff Credentials'), style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _credentialRow(
                        'Staff ID',
                        _generatedCredentials!.staffId,
                        Icons.badge,
                      ),
                      const SizedBox(height: 8),
                      _credentialRow(
                        'Temp Password',
                        _generatedCredentials!.tempPassword,
                        Icons.lock,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.white38,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
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
                        onPressed: _loading ? null : _regenerate,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(context.opsTr('Reset credentials')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text(context.opsTr('Done')),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Text(context.opsTr('This will generate unique staff credentials for this hospital. Resetting credentials cancels out old ones.'), style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _loading
                      ? null
                      : (widget.alreadyOnboarded ? _regenerate : _onboard),
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.add_business, size: 18),
                  label: Text(
                    _loading ? 'Working...' : primaryCtaLabel,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
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

  Widget _credentialRow(String label, String value, IconData icon) {
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
          onTap: () => _copyToClipboard(value, label),
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
