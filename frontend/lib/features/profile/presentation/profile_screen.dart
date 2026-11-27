import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';

enum ProfileEditMode {
  physiological,
  program,
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    this.mode = ProfileEditMode.physiological,
  });

  final ProfileEditMode mode;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _heightController = TextEditingController();
  final _rateController = TextEditingController();

  String _sex = 'M';
  DateTime _birthDate = DateTime(1995, 1, 1);
  String _activityLevel = 'moderate';
  String _goalType = 'maintain';
  String _proteinPreference = 'high';
  String _dietStyle = 'balanced';
  int _checkinDay = 0;

  bool _hydrated = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _heightController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  void _hydrateFromProfile(UserProfileModel profile) {
    if (_hydrated) return;
    _hydrated = true;
    _sex = profile.sex;
    _birthDate = profile.birthDate;
    _heightController.text = profile.heightCm.toStringAsFixed(0);
    _activityLevel = profile.activityLevel;
    _goalType = profile.goalType;
    _rateController.text = profile.targetRateKgPerWeek.toStringAsFixed(2);
    _proteinPreference = profile.proteinPreference;
    _dietStyle = profile.dietStyle;
    _checkinDay = profile.checkinDay;
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate,
      firstDate: DateTime(1930),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 14)),
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final height = double.parse(_heightController.text.replaceAll(',', '.'));
    final rate = double.parse(_rateController.text.replaceAll(',', '.'));

    setState(() => _isSaving = true);
    final error = await ref.read(profileProvider.notifier).saveAndRecalculate(
          sex: _sex,
          birthDate: _birthDate,
          heightCm: height,
          activityLevel: _activityLevel,
          goalType: _goalType,
          targetRateKgPerWeek: rate,
          proteinPreference: _proteinPreference,
          dietStyle: _dietStyle,
          checkinDay: _checkinDay,
        );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (widget.mode == ProfileEditMode.program
                  ? 'Programme enregistré et cibles macros recalculées.'
                  : 'Profil physiologique enregistré.'),
        ),
        backgroundColor: error != null ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final isProgram = widget.mode == ProfileEditMode.program;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isProgram ? 'Modifier le programme' : 'Profil physiologique',
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.calories),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Erreur : $error'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.read(profileProvider.notifier).load(),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          _hydrateFromProfile(profile);

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!isProgram) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Paramètres physiologiques',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'M', label: Text('Homme')),
                              ButtonSegment(value: 'F', label: Text('Femme')),
                            ],
                            selected: {_sex},
                            onSelectionChanged: (sel) {
                              setState(() => _sex = sel.first);
                            },
                          ),
                          const SizedBox(height: 14),
                          InkWell(
                            onTap: _pickBirthDate,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date de naissance',
                                suffixIcon: Icon(Icons.calendar_today_outlined),
                              ),
                              child: Text(
                                DateFormat('dd/MM/yyyy').format(_birthDate),
                                style: AppTheme.numericStyle(fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _heightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Taille (cm)',
                            ),
                            validator: (v) {
                              final parsed = double.tryParse(
                                  (v ?? '').replaceAll(',', '.'));
                              if (parsed == null ||
                                  parsed <= 50 ||
                                  parsed >= 300) {
                                return 'Taille invalide';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _activityLevel,
                            decoration: const InputDecoration(
                              labelText: 'Niveau d’activité physique quotidienne',
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'sedentary',
                                  child: Text('Sédentaire')),
                              DropdownMenuItem(
                                  value: 'light',
                                  child: Text('Légèrement actif')),
                              DropdownMenuItem(
                                  value: 'moderate', child: Text('Modéré')),
                              DropdownMenuItem(
                                  value: 'active', child: Text('Actif')),
                              DropdownMenuItem(
                                  value: 'very_active',
                                  child: Text('Très actif')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _activityLevel = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cibles actuelles',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _TargetChip(
                                label: 'TDEE',
                                value: '${profile.currentTdeeKcal.round()} kcal',
                                color: AppColors.textSecondary,
                              ),
                              _TargetChip(
                                label: 'Cible',
                                value:
                                    '${profile.currentCalorieTarget.round()} kcal',
                                color: AppColors.calories,
                              ),
                              _TargetChip(
                                label: 'P / L / G',
                                value:
                                    '${profile.currentProteinG.round()} / ${profile.currentFatG.round()} / ${profile.currentCarbsG.round()} g',
                                color: AppColors.carbs,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Objectifs & Répartition des macros',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _goalType,
                            decoration: const InputDecoration(
                              labelText: 'Objectif',
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'lose', child: Text('Perte de poids')),
                              DropdownMenuItem(
                                  value: 'maintain', child: Text('Maintien')),
                              DropdownMenuItem(
                                  value: 'gain', child: Text('Prise de muscle')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _goalType = v);
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _rateController,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Rythme hebdomadaire (kg / semaine)',
                              hintText: 'Ex: -0.5, 0.0, 0.25',
                            ),
                            validator: (v) {
                              final parsed = double.tryParse(
                                  (v ?? '').replaceAll(',', '.'));
                              if (parsed == null || parsed < -2 || parsed > 2) {
                                return 'Entre -2.0 et +2.0 kg/sem';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _proteinPreference,
                            decoration: const InputDecoration(
                              labelText: 'Apport en protéines',
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'moderate',
                                  child: Text('Modéré (1.7 g/kg)')),
                              DropdownMenuItem(
                                  value: 'high', child: Text('Élevé (2.0 g/kg)')),
                              DropdownMenuItem(
                                  value: 'extra_high',
                                  child: Text('Très élevé (2.3 g/kg)')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _proteinPreference = v);
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: _dietStyle,
                            decoration: const InputDecoration(
                              labelText: 'Répartition des macros',
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'balanced', child: Text('Équilibré')),
                              DropdownMenuItem(
                                  value: 'low_fat',
                                  child: Text('Pauvre en lipides')),
                              DropdownMenuItem(
                                  value: 'low_carb',
                                  child: Text('Pauvre en glucides')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _dietStyle = v);
                            },
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<int>(
                            initialValue: _checkinDay,
                            decoration: const InputDecoration(
                              labelText: 'Jour du bilan hebdomadaire',
                            ),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Lundi')),
                              DropdownMenuItem(value: 1, child: Text('Mardi')),
                              DropdownMenuItem(
                                  value: 2, child: Text('Mercredi')),
                              DropdownMenuItem(value: 3, child: Text('Jeudi')),
                              DropdownMenuItem(
                                  value: 4, child: Text('Vendredi')),
                              DropdownMenuItem(value: 5, child: Text('Samedi')),
                              DropdownMenuItem(
                                  value: 6, child: Text('Dimanche')),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => _checkinDay = v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.background,
                          ),
                        )
                      : Icon(
                          isProgram
                              ? Icons.calculate_outlined
                              : Icons.save_outlined,
                        ),
                  label: Text(
                    isProgram
                        ? 'Enregistrer et recalculer mes macros'
                        : 'Enregistrer le profil physiologique',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTheme.numericStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
