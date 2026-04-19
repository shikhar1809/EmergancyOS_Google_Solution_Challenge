import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/emergency_consent_dialog.dart';
import 'dart:async';

import '../../../services/connectivity_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/offline_sos_status_service.dart';
import '../../../services/sms_gateway_service.dart';
import '../../../services/voice_comms_service.dart';
import '../../../core/utils/dispatch_incident_priority.dart';
import 'sms_sos_screen.dart';

class SosQuickIntakePage extends ConsumerStatefulWidget {
  const SosQuickIntakePage({super.key, this.isDrillShell = false});

  final bool isDrillShell;

  @override
  ConsumerState<SosQuickIntakePage> createState() => _SosQuickIntakePageState();
}

class _SosQuickIntakePageState extends ConsumerState<SosQuickIntakePage>
    with SingleTickerProviderStateMixin {
  String? _selectedType;
  bool? _forSomeoneElse;
  String? _victimConscious;
  String? _victimBreathing;
  int _peopleCount = 1;
  bool _submitting = false;

  late AnimationController _pulseCtrl;

  static const _emergencyTypes = <Map<String, dynamic>>[
    {'type': 'Cardiac arrest / Heart attack', 'icon': Icons.favorite_rounded, 'color': Color(0xFFFF1744)},
    {'type': 'CPR / AED (cardiac emergency)', 'icon': Icons.electrical_services_rounded, 'color': Color(0xFF00BFA5)},
    {'type': 'Stroke / Sudden weakness', 'icon': Icons.psychology_rounded, 'color': Color(0xFF9575CD)},
    {'type': 'Severe bleeding / Hemorrhage', 'icon': Icons.water_drop_rounded, 'color': Color(0xFFD50000)},
    {'type': 'Breathing difficulty / Choking', 'icon': Icons.air_rounded, 'color': Color(0xFFFF5252)},
    {'type': 'Unconscious / Unresponsive', 'icon': Icons.bedtime_rounded, 'color': Color(0xFF5C6BC0)},
    {'type': 'Seizure / Convulsions', 'icon': Icons.electric_bolt_rounded, 'color': Color(0xFFFFAB00)},
    {'type': 'Severe allergic reaction', 'icon': Icons.coronavirus_rounded, 'color': Color(0xFF00C853)},
    {'type': 'Poisoning / Overdose', 'icon': Icons.medication_rounded, 'color': Color(0xFF8E24AA)},
    {'type': 'Head / Spinal injury', 'icon': Icons.personal_injury_rounded, 'color': Color(0xFFFF6D00)},
    {'type': 'Other medical emergency', 'icon': Icons.warning_amber_rounded, 'color': Color(0xFFFFD600)},
  ];

  final TextEditingController _otherDescCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _otherDescCtrl.dispose();
    super.dispose();
  }

  /// Maps quick-intake emergency category to hospital service tags for dispatch.
  static List<String> _requiredServicesForType(String type) =>
      requiredServicesForType(type);

  bool get _canSubmit {
    if (_selectedType == null || _forSomeoneElse == null || _submitting) return false;
    if (_selectedType == 'Other medical emergency' && _otherDescCtrl.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submitSos() async {
    if (!_canSubmit) return;
    if (widget.isDrillShell) {
      if (!context.mounted) return;
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.quickSosDrillSubmitDisabled),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }
    if (kIsWeb) {
      VoiceCommsService.primeForVoiceGuidance();
    }
    setState(() => _submitting = true);

    final pinReady = await _ensureSosPinReady();
    if (!pinReady) {
      if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
      setState(() => _submitting = false);
      return;
    }

    if (!context.mounted) return;
    final consented = await showEmergencyDataConsentIfNeeded(context);
    if (!consented) {
      if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
      setState(() => _submitting = false);
      return;
    }

    String? createdId;
    try {
      final pos = await Geolocator.getCurrentPosition();
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid ?? 'guest';
      final displayName = user?.displayName ??
          (user?.email?.split('@').first ?? user?.phoneNumber ?? 'Volunteer');

      final typeForIncident = (_selectedType == 'Other medical emergency')
          ? 'Other medical emergency: ${_otherDescCtrl.text.trim()}'
          : _selectedType!;

      final incident = await IncidentService.createIncident(
        userId: userId,
        userDisplayName: displayName,
        location: LatLng(pos.latitude, pos.longitude),
        type: typeForIncident,
      );
      createdId = incident.id;
      ConnectivityService().start();
      unawaited(
        OfflineSosStatusService.markPendingIfOffline(
          incidentId: createdId,
          likelyOffline: !ConnectivityService().isOnline,
        ),
      );

      if (kIsWeb) {
        unawaited(
          SmsGatewayService.offerWebParallelGeoSmsIfNeeded(
            context,
            lat: pos.latitude,
            lng: pos.longitude,
            type: typeForIncident,
            incidentId: createdId,
            victimCount: _peopleCount,
            freeText: 'emergencyOS intake SOS',
          ),
        );
      } else {
        unawaited(
          SmsGatewayService.tryOpenParallelGeoSmsRelay(
            lat: pos.latitude,
            lng: pos.longitude,
            type: typeForIncident,
            incidentId: createdId,
            victimCount: _peopleCount,
            freeText: 'emergencyOS intake SOS',
          ),
        );
      }

      await IncidentService.persistActiveSos(createdId);

      final triage = <String, dynamic>{
        'forSomeoneElse': _forSomeoneElse,
        'peopleCount': _peopleCount,
        'intakeCompleted': true,
        'requiredServices': _requiredServicesForType(typeForIncident),
      };
      if (_forSomeoneElse == true) {
        triage['victimConscious'] = _victimConscious;
        triage['victimBreathing'] = _victimBreathing;
      }

      await FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(createdId)
          .update(triage);
    } catch (e) {
      debugPrint('[SOS Intake] creation failed: $e');
      if (context.mounted) {
        if (!ConnectivityService().isOnline) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SmsSosScreen()),
          );
        }
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              loc.quickSosFailed(
                e is StateError ? e.message : loc.sosCheckConnectionRetry,
              ),
            ),
            backgroundColor: AppColors.primaryDanger,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: loc.sosRetry,
              textColor: Colors.white,
              onPressed: _submitSos,
            ),
          ),
        );
      }
      setState(() => _submitting = false);
      return;
    }

    if (!context.mounted) return;
    final id = createdId;
    if (id.isNotEmpty) {
      context.go('/sos-active/${Uri.encodeComponent(id)}');
    } else {
      if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.quickSosCouldNotStart),
          backgroundColor: AppColors.primaryDanger,
        ),
      );
    }
    setState(() => _submitting = false);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            if (widget.isDrillShell)
              Material(
                color: Colors.cyan.shade900.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school_rounded, color: Colors.cyanAccent.shade200, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l.quickSosPracticeBanner,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _buildHeader(l),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      number: '1',
                      title: l.quickSosSectionWhat,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTypeGrid(l),
                          if (_selectedType == 'Other medical emergency') ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _otherDescCtrl,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: l.quickSosOtherHint,
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.05),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.primaryDanger),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ]
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildSection(
                      number: '2',
                      title: l.quickSosSectionSomeoneElse,
                      child: _buildForSomeoneElseToggle(l),
                    ),
                    if (_forSomeoneElse == true) ...[
                      const SizedBox(height: 24),
                      _buildSection(
                        number: '3',
                        title: l.quickSosSectionVictim,
                        subtitle: l.quickSosVictimSubtitle,
                        child: _buildVictimStatus(l),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildSection(
                      number: _forSomeoneElse == true ? '4' : '3',
                      title: l.quickSosSectionPeople,
                      child: _buildPeopleCount(l),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildBottomAction(l),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(AppLocalizations l) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.primaryDanger.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l.quickSosClose,
            child: GestureDetector(
              onTap: () => context.go('/dashboard'),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.close, color: Colors.white70, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.quickSosTitle,
                  style: const TextStyle(
                    color: AppColors.primaryDanger,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.quickSosSubtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, child) => Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryDanger,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDanger
                          .withValues(alpha: 0.3 + _pulseCtrl.value * 0.5),
                      blurRadius: 6 + _pulseCtrl.value * 8,
                      spreadRadius: _pulseCtrl.value * 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section wrapper ───────────────────────────────────────────────────────

  Widget _buildSection({
    required String number,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.primaryDanger.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: const TextStyle(
                  color: AppColors.primaryDanger,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  // ─── Emergency type grid ──────────────────────────────────────────────────

  Widget _buildTypeGrid(AppLocalizations l) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.1, // Adjusted slightly to fit 10 items better
      children: _emergencyTypes.map((e) {
        final type = e['type'] as String;
        final icon = e['icon'] as IconData;
        final color = e['color'] as Color;
        final selected = _selectedType == type;

        return Semantics(
          button: true,
          selected: selected,
          label: type,
          child: GestureDetector(
            onTap: () => setState(() => _selectedType = type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.2) : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? color : Colors.white.withValues(alpha: 0.08),
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 12)]
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, color: selected ? color : Colors.white54, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      type,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── For someone else toggle ──────────────────────────────────────────────

  Widget _buildForSomeoneElseToggle(AppLocalizations l) {
    return Row(
      children: [
        _buildToggleCard(
          label: l.quickSosYesSomeoneElse,
          icon: Icons.people_rounded,
          selected: _forSomeoneElse == true,
          onTap: () => setState(() => _forSomeoneElse = true),
        ),
        const SizedBox(width: 10),
        _buildToggleCard(
          label: l.quickSosNoForMe,
          icon: Icons.person_rounded,
          selected: _forSomeoneElse == false,
          onTap: () => setState(() {
            _forSomeoneElse = false;
            _victimConscious = null;
            _victimBreathing = null;
          }),
        ),
      ],
    );
  }

  Widget _buildToggleCard({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryDanger.withValues(alpha: 0.15)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.primaryDanger
                    : Colors.white.withValues(alpha: 0.08),
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primaryDanger.withValues(alpha: 0.2),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  color: selected ? AppColors.primaryDanger : Colors.white54,
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Victim status ────────────────────────────────────────────────────────

  Widget _buildVictimStatus(AppLocalizations l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.quickSosVictimConsciousQ,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildChip(l.quickSosLabelYes, _victimConscious == 'yes', AppColors.primarySafe,
                () => setState(() => _victimConscious = 'yes')),
            const SizedBox(width: 8),
            _buildChip(l.quickSosLabelNo, _victimConscious == 'no', AppColors.primaryDanger,
                () => setState(() => _victimConscious = 'no')),
            const SizedBox(width: 8),
            _buildChip(l.quickSosLabelUnsure, _victimConscious == 'unsure', AppColors.primaryWarning,
                () => setState(() => _victimConscious = 'unsure')),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          l.quickSosVictimBreathingQ,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildChip(l.quickSosLabelYes, _victimBreathing == 'yes', AppColors.primarySafe,
                () => setState(() => _victimBreathing = 'yes')),
            const SizedBox(width: 8),
            _buildChip(l.quickSosLabelNo, _victimBreathing == 'no', AppColors.primaryDanger,
                () => setState(() => _victimBreathing = 'no')),
            const SizedBox(width: 8),
            _buildChip(l.quickSosLabelUnsure, _victimBreathing == 'unsure', AppColors.primaryWarning,
                () => setState(() => _victimBreathing = 'unsure')),
          ],
        ),
      ],
    );
  }

  Widget _buildChip(String label, bool selected, Color activeColor, VoidCallback onTap) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? activeColor.withValues(alpha: 0.18) : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? activeColor : Colors.white.withValues(alpha: 0.08),
                width: selected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── People count ─────────────────────────────────────────────────────────

  Widget _buildPeopleCount(AppLocalizations l) {
    return Row(
      children: [1, 2, 3].map((n) {
        final label = n == 3 ? l.quickSosPeopleThreePlus : '$n';
        final selected = _peopleCount == n;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: n < 3 ? 10 : 0),
            child: Semantics(
              button: true,
              selected: selected,
              label: '$label ${n == 1 ? l.quickSosPerson : l.quickSosPeople}',
              child: GestureDetector(
                onTap: () => setState(() => _peopleCount = n),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryDanger.withValues(alpha: 0.15)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppColors.primaryDanger
                          : Colors.white.withValues(alpha: 0.08),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: selected ? AppColors.primaryDanger : Colors.white70,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n == 1 ? l.quickSosPerson : l.quickSosPeople,
                        style: TextStyle(
                          color: selected ? Colors.white70 : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Bottom submit button ─────────────────────────────────────────────────

  Widget _buildBottomAction(AppLocalizations l) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.primaryDanger.withValues(alpha: 0.25)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: Semantics(
            button: true,
            enabled: _canSubmit && !_submitting,
            label: _canSubmit ? l.quickSosSendNow : l.quickSosSelectFirst,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submitSos : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _canSubmit ? AppColors.primaryDanger : AppColors.surfaceHighlight,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceHighlight,
                disabledForegroundColor: Colors.white30,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: _canSubmit ? 8 : 0,
                shadowColor: AppColors.primaryDanger.withValues(alpha: 0.5),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sos_rounded,
                          size: 22,
                          color: _canSubmit ? Colors.white : Colors.white30,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _canSubmit ? l.quickSosSendNow : l.quickSosSelectFirst,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.2,
                            color: _canSubmit ? Colors.white : Colors.white30,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── PIN check (same as SosScreen) ────────────────────────────────────────

  Future<bool> _ensureSosPinReady() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) return true;

    final prefs = await SharedPreferences.getInstance();
    var hash = (prefs.getString('sos_pin_hash') ?? '').trim();
    if (hash.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        hash = ((doc.data()?['sosPinHash'] as String?) ?? '').trim();
        if (hash.isNotEmpty) {
          await prefs.setString('sos_pin_hash', hash);
        }
      } catch (_) {}
    }
    if (hash.isNotEmpty) return true;
    if (!context.mounted) return false;

    final l = AppLocalizations.of(context);
    final goSet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          l.setSosPinFirst,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          l.sosPinDispatchBody,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.later, style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDanger,
            ),
            child: Text(l.setPinNow),
          ),
        ],
      ),
    );
    if (goSet == true && context.mounted) {
      final path = GoRouterState.of(context).uri.path;
      context.go(path.startsWith('/drill/') ? '/drill/profile' : '/profile');
    }
    return false;
  }
}
