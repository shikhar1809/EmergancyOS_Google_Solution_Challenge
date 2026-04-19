import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/utils/map_avatar_pronouns.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class MedicalDetailsScreen extends ConsumerStatefulWidget {
  const MedicalDetailsScreen({super.key});

  @override
  ConsumerState<MedicalDetailsScreen> createState() =>
      _MedicalDetailsScreenState();
}

class _MedicalDetailsScreenState extends ConsumerState<MedicalDetailsScreen> {
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _medicationsController = TextEditingController();
  final _donorController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _useEmergencyContactForSms = true;
  String _mapAvatarPronouns = MapAvatarPronouns.heHim;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _addChangeListeners();
  }

  void _addChangeListeners() {
    for (final c in [
      _bloodTypeController,
      _allergiesController,
      _conditionsController,
      _contactNameController,
      _contactPhoneController,
      _contactEmailController,
      _relationshipController,
      _medicationsController,
      _donorController,
    ]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    for (final c in [
      _bloodTypeController,
      _allergiesController,
      _conditionsController,
      _contactNameController,
      _contactPhoneController,
      _contactEmailController,
      _relationshipController,
      _medicationsController,
      _donorController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _normalizeMapAvatarPronouns(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == MapAvatarPronouns.sheHer) return MapAvatarPronouns.sheHer;
    if (s == MapAvatarPronouns.theyThem) return MapAvatarPronouns.theyThem;
    return MapAvatarPronouns.heHim;
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!context.mounted) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _bloodTypeController.text = data['bloodType'] ?? '';
        _allergiesController.text = data['allergies'] ?? '';
        _conditionsController.text = data['conditions'] ?? '';
        _contactNameController.text = data['contactName'] ?? '';
        _contactPhoneController.text = data['contactPhone'] ?? '';
        _contactEmailController.text = data['contactEmail'] ?? '';
        _relationshipController.text = data['relationship'] ?? '';
        _medicationsController.text = data['medications'] ?? '';
        _donorController.text = data['donorStatus'] ?? '';
        _useEmergencyContactForSms =
            (data['useEmergencyContactForSms'] as bool?) ?? true;
        _mapAvatarPronouns = _normalizeMapAvatarPronouns(
          data[MapAvatarPronouns.fieldMapAvatarPronouns] as String?,
        );
      }
    } on TimeoutException {
      debugPrint('Error: Firestore connection timed out.');
    } catch (e) {
      debugPrint('Error loading medical info: $e');
    } finally {
      if (context.mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!context.mounted) return;
    final l = AppLocalizations.of(context);

    setState(() => _isSaving = true);
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final offline = connectivity.every((r) => r == ConnectivityResult.none);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'bloodType': _bloodTypeController.text.trim(),
            'allergies': _allergiesController.text.trim(),
            'conditions': _conditionsController.text.trim(),
            'contactName': _contactNameController.text.trim(),
            'contactPhone': _contactPhoneController.text.trim(),
            'contactEmail': _contactEmailController.text.trim(),
            'relationship': _relationshipController.text.trim(),
            'medications': _medicationsController.text.trim(),
            'donorStatus': _donorController.text.trim(),
            'useEmergencyContactForSms': _useEmergencyContactForSms,
            MapAvatarPronouns.fieldMapAvatarPronouns: _mapAvatarPronouns,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              offline ? l.profileSavedOfflineMsg : l.profileSavedMsg,
            ),
            backgroundColor: offline ? Colors.orange : Colors.green,
          ),
        );
      }
      if (context.mounted) setState(() => _isDirty = false);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.profileSaveError('$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (context.mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_isDirty) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              l.profileUnsavedTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              l.profileUnsavedBody,
              style: const TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  l.profileStay,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  l.profileDiscard,
                  style: const TextStyle(color: AppColors.primaryDanger),
                ),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) context.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(l.criticalMedicalInfo),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          actions: [
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(
                  Icons.check_rounded,
                  color: AppColors.primaryDanger,
                ),
                onPressed: _save,
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _buildCard(
                    icon: Icons.bloodtype,
                    title: 'Critical Info',
                    children: [
                      _buildTextField(
                        _bloodTypeController,
                        l.bloodType,
                        l.profileHintBloodType,
                        icon: Icons.bloodtype,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _buildTextField(
                        _allergiesController,
                        l.allergies,
                        l.profileHintAllergies,
                        icon: Icons.warning_rounded,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _buildTextField(
                        _conditionsController,
                        l.medicalConditions,
                        l.profileHintConditions,
                        icon: Icons.health_and_safety,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    icon: Icons.family_restroom,
                    title: l.emergencyContacts,
                    children: [
                      _buildTextField(
                        _contactNameController,
                        l.contactName,
                        l.profileHintContactName,
                        icon: Icons.person,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _buildTextField(
                        _relationshipController,
                        l.relationship,
                        l.profileHintRelationship,
                        icon: Icons.family_restroom,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _buildTextField(
                        _contactPhoneController,
                        l.contactPhone,
                        l.profileHintPhone,
                        icon: Icons.phone,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _buildTextField(
                        _contactEmailController,
                        l.contactEmail,
                        l.profileHintContactEmail,
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.profileSmsContactTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          l.profileSmsContactSubtitle,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        value: _useEmergencyContactForSms,
                        activeColor: AppColors.primaryDanger,
                        onChanged: (v) =>
                            setState(() => _useEmergencyContactForSms = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    icon: Icons.medication,
                    title: l.profileAdditionalInfo,
                    children: [
                      _buildTextField(
                        _medicationsController,
                        l.medications,
                        l.profileHintMedications,
                        icon: Icons.medication,
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      _buildTextField(
                        _donorController,
                        l.organDonor,
                        l.profileHintDonor,
                        icon: Icons.volunteer_activism,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    icon: Icons.face,
                    title: l.profilePronounsTitle,
                    children: [
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildPronounChip(
                            l.profilePronounsHeHim,
                            MapAvatarPronouns.heHim,
                          ),
                          _buildPronounChip(
                            l.profilePronounsSheHer,
                            MapAvatarPronouns.sheHer,
                          ),
                          _buildPronounChip(
                            l.profilePronounsTheyThem,
                            MapAvatarPronouns.theyThem,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildPronounChip(String label, String value) {
    final isSelected = _mapAvatarPronouns == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _mapAvatarPronouns = value),
      selectedColor: AppColors.primaryDanger.withValues(alpha: 0.25),
      checkmarkColor: AppColors.primaryDanger,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      side: BorderSide(
        color: isSelected ? AppColors.primaryDanger : Colors.white12,
        width: isSelected ? 1.5 : 1,
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryDanger, size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white54),
          hintStyle: const TextStyle(color: Colors.white30),
          prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primaryDanger,
              width: 1.5,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }
}
