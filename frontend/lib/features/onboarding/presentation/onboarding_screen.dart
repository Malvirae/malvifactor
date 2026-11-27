import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/services/health_connect_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/analytics/presentation/analytics_detail_screen.dart';
import 'package:malvifactor/features/auth/providers/auth_provider.dart';
import 'package:malvifactor/features/dashboard/data/dashboard_repository.dart';
import 'package:malvifactor/features/dashboard/providers/dashboard_provider.dart';
import 'package:malvifactor/features/profile/data/profile_repository.dart';
import 'package:malvifactor/features/profile/providers/profile_provider.dart';
import 'package:malvifactor/features/strategy/presentation/strategy_screen.dart';

enum _OnboardingPhase { wizard, calculating, summary }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const int _totalSteps = 6;

  _OnboardingPhase _phase = _OnboardingPhase.wizard;
  int _step = 0;

  // Step 1
  late final TextEditingController _nameCtrl;
  String _sex = 'M';
  DateTime _birthDate = DateTime(1995, 1, 1);
  final TextEditingController _heightCtrl = TextEditingController(text: '175');

  // Step 2
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _bodyFatCtrl = TextEditingController();
  bool _importingHealthConnect = false;

  // Step 3
  String _neatLevel = 'lightly_active_daily';

  // Step 4
  int _workoutsPerWeek = 3;
  String _workoutType = 'mixed';
  bool _showManualTdee = false;
  final TextEditingController _manualTdeeCtrl = TextEditingController();

  // Step 5
  String _goalType = 'maintain';
  double _targetRate = 0.0;
  final TextEditingController _targetWeightCtrl = TextEditingController();

  // Step 6
  String _proteinPreference = 'high';
  String _dietStyle = 'balanced';
  int _checkinDay = 0;

  // Animation & Summary
  late final AnimationController _calcController;
  UserProfileModel? _computedProfile;
  String? _errorMessage;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    final existingProfile = ref.read(profileProvider).valueOrNull;

    _nameCtrl = TextEditingController(text: user?.displayName ?? '');
    if (existingProfile != null) {
      _sex = existingProfile.sex;
      _birthDate = existingProfile.birthDate;
      _heightCtrl.text = existingProfile.heightCm.round().toString();
      _goalType = existingProfile.goalType;
      _targetRate = existingProfile.targetRateKgPerWeek;
      if (existingProfile.targetWeightKg != null) {
        _targetWeightCtrl.text =
            existingProfile.targetWeightKg!.toStringAsFixed(1);
      }
      _proteinPreference = existingProfile.proteinPreference;
      _dietStyle = existingProfile.dietStyle;
      _checkinDay = existingProfile.checkinDay;
    }

    _calcController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _bodyFatCtrl.dispose();
    _manualTdeeCtrl.dispose();
    _targetWeightCtrl.dispose();
    _calcController.dispose();
    super.dispose();
  }

  Future<void> _importFromHealthConnect() async {
    setState(() => _importingHealthConnect = true);
    final (weight, fat) =
        await ref.read(healthConnectProvider.notifier).fetchLatestMeasurement();
    if (!mounted) return;
    setState(() => _importingHealthConnect = false);

    if (weight != null) {
      _weightCtrl.text = weight.toStringAsFixed(1);
    }
    if (fat != null) {
      _bodyFatCtrl.text = fat.toStringAsFixed(1);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          weight != null
              ? 'Mesure importée depuis Health Connect (${weight.toStringAsFixed(1)} kg).'
              : 'Aucune mesure récente trouvée dans Health Connect.',
        ),
        backgroundColor:
            weight != null ? AppColors.success : AppColors.surfaceElevated,
      ),
    );
  }

  bool _validateCurrentStep() {
    setState(() => _errorMessage = null);
    if (_step == 0) {
      if (_nameCtrl.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Indique ton prénom pour continuer.');
        return false;
      }
      final h = double.tryParse(_heightCtrl.text.replaceAll(',', '.'));
      if (h == null || h <= 50 || h >= 300) {
        setState(() => _errorMessage = 'Taille invalide (en cm).');
        return false;
      }
    } else if (_step == 1) {
      final w = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
      if (w == null || w <= 20 || w >= 350) {
        setState(() => _errorMessage = 'Poids actuel requis (en kg).');
        return false;
      }
      final fatRaw = _bodyFatCtrl.text.trim().replaceAll(',', '.');
      if (fatRaw.isNotEmpty) {
        final f = double.tryParse(fatRaw);
        if (f == null || f < 5 || f > 60) {
          setState(() => _errorMessage = 'Masse grasse entre 5 % et 60 %.');
          return false;
        }
      }
    }
    return true;
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _calculatePlan();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() {
        _errorMessage = null;
        _step--;
      });
    }
  }

  Future<void> _calculatePlan() async {
    final height = double.parse(_heightCtrl.text.replaceAll(',', '.'));
    final weight = double.parse(_weightCtrl.text.replaceAll(',', '.'));
    final fatRaw = _bodyFatCtrl.text.trim().replaceAll(',', '.');
    final bodyFat = fatRaw.isEmpty ? null : double.tryParse(fatRaw);
    final manualTdeeRaw = _manualTdeeCtrl.text.trim();
    final manualTdee =
        manualTdeeRaw.isEmpty ? null : int.tryParse(manualTdeeRaw);
    final targetWeightRaw = _targetWeightCtrl.text.trim().replaceAll(',', '.');
    final targetWeight =
        targetWeightRaw.isEmpty ? null : double.tryParse(targetWeightRaw);
    final effectiveRate = _goalType == 'maintain' ? 0.0 : _targetRate;

    setState(() {
      _phase = _OnboardingPhase.calculating;
      _errorMessage = null;
    });
    _calcController.forward(from: 0);

    try {
      final apiFuture = Future.wait<dynamic>([
        ref.read(profileRepositoryProvider).completeOnboarding(
              displayName: _nameCtrl.text.trim(),
              sex: _sex,
              birthDate: _birthDate,
              heightCm: height,
              weightKg: weight,
              bodyFatPct: bodyFat,
              neatLevel: _neatLevel,
              workoutsPerWeek: _workoutsPerWeek,
              workoutType: _workoutType,
              manualInitialTdeeKcal: manualTdee,
              goalType: _goalType,
              targetRateKgPerWeek: effectiveRate,
              targetWeightKg: targetWeight,
              proteinPreference: _proteinPreference,
              dietStyle: _dietStyle,
              checkinDay: _checkinDay,
            ),
        ref.read(dashboardRepositoryProvider).createManualWeight(
              measuredAt: DateTime.now(),
              weightKg: weight,
              bodyFatPct: bodyFat,
            ),
      ]);

      final results = await Future.wait<dynamic>([
        apiFuture,
        Future<void>.delayed(const Duration(milliseconds: 2500)),
      ]);

      final updatedProfile =
          (results[0] as List<dynamic>)[0] as UserProfileModel;
      ref.read(profileProvider.notifier).setProfile(updatedProfile);
      await ref.read(authProvider.notifier).restoreSession();

      if (!mounted) return;
      setState(() {
        _computedProfile = updatedProfile;
        _phase = _OnboardingPhase.summary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _OnboardingPhase.wizard;
        _errorMessage = 'Erreur lors du calcul : $e';
      });
    }
  }

  void _finishOnboarding() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(analyticsSeriesProvider);
    ref.invalidate(strategyProvider);
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          child: switch (_phase) {
            _OnboardingPhase.wizard => _buildWizard(),
            _OnboardingPhase.calculating => _buildCalculating(),
            _OnboardingPhase.summary => _buildSummary(),
          },
        ),
      ),
    );
  }

  Widget _buildWizard() {
    final progress = (_step + 1) / _totalSteps;
    return Column(
      key: const ValueKey('wizard'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              if (_step > 0)
                IconButton(
                  onPressed: _prevStep,
                  icon: const Icon(LucideIcons.arrowLeft, size: 20),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Étape ${_step + 1} sur $_totalSteps',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 260),
                        builder: (_, val, __) => LinearProgressIndicator(
                          value: val,
                          minHeight: 5,
                          backgroundColor: AppColors.surfaceElevated,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.calories,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                switch (_step) {
                  0 => _buildStep1(),
                  1 => _buildStep2(),
                  2 => _buildStep3(),
                  3 => _buildStep4(),
                  4 => _buildStep5(),
                  _ => _buildStep6(),
                },
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: ElevatedButton(
            onPressed: _nextStep,
            child: Text(
              _step == _totalSteps - 1
                  ? 'Calculer mon programme'
                  : 'Continuer',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Faisons connaissance',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ces informations permettent de calibrer ton métabolisme de base.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(labelText: 'Prénom d’affichage'),
        ),
        const SizedBox(height: 16),
        const Text(
          'Sexe biologique',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _SelectCard(
                title: 'Homme',
                icon: LucideIcons.user,
                selected: _sex == 'M',
                onTap: () => setState(() => _sex = 'M'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SelectCard(
                title: 'Femme',
                icon: LucideIcons.user,
                selected: _sex == 'F',
                onTap: () => setState(() => _sex = 'F'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _birthDate,
              firstDate: DateTime(1930),
              lastDate: DateTime.now().subtract(const Duration(days: 365 * 14)),
              locale: const Locale('fr', 'FR'),
            );
            if (picked != null) setState(() => _birthDate = picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date de naissance',
              suffixIcon: Icon(LucideIcons.calendar, size: 18),
            ),
            child: Text(
              DateFormat('dd/MM/yyyy').format(_birthDate),
              style: AppTheme.numericStyle(fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _heightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.numericStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: 'Taille (cm)',
            suffixText: 'cm',
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tes mensurations actuelles',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ton poids sert de point de départ au suivi EWMA et au calcul des protéines.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 22),
        if (_isAndroid) ...[
          OutlinedButton.icon(
            onPressed: _importingHealthConnect ? null : _importFromHealthConnect,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: AppColors.calories,
              side: const BorderSide(color: AppColors.calories),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _importingHealthConnect
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.calories,
                    ),
                  )
                : const Icon(LucideIcons.heartPulse, size: 18),
            label: const Text('Importer depuis Health Connect'),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _weightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.numericStyle(fontSize: 18),
          decoration: const InputDecoration(
            labelText: 'Poids actuel (kg) *',
            suffixText: 'kg',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _bodyFatCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.numericStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: '% de masse grasse (optionnel)',
            suffixText: '%',
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.matteCardDecoration(borderRadius: 12),
          child: const Row(
            children: [
              Icon(LucideIcons.info, size: 16, color: AppColors.calories),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Si tu connais ton % de masse grasse, nous utilisons la formule Katch-McArdle (plus précise sur la masse maigre).',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    const options = [
      (
        'sedentary_desk',
        'Plutôt assis',
        '< 5 000 pas/jour · travail de bureau',
        LucideIcons.armchair,
      ),
      (
        'lightly_active_daily',
        'Actif au quotidien',
        '5 000 à 8 000 pas/jour · déplacements modérés',
        LucideIcons.footprints,
      ),
      (
        'standing_active',
        'Souvent debout',
        '8 000 à 12 000 pas/jour · métier actif',
        LucideIcons.personStanding,
      ),
      (
        'very_mobile',
        'Très mobile',
        '> 12 000 pas/jour · activité physique continue',
        LucideIcons.zap,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ton rythme de vie hors sport',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Évalue ton activité quotidienne (NEAT) en dehors des séances de sport.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        ...options.map(
          (opt) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              title: opt.$2,
              subtitle: opt.$3,
              icon: opt.$4,
              selected: _neatLevel == opt.$1,
              onTap: () => setState(() => _neatLevel = opt.$1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4() {
    const frequencies = [
      (0, 'Aucune séance'),
      (2, '1 à 2 / sem'),
      (4, '3 à 4 / sem'),
      (6, '5+ / sem'),
    ];
    const types = [
      ('strength', 'Musculation / Renfo', LucideIcons.dumbbell),
      ('cardio', 'Cardio / Course', LucideIcons.heartPulse),
      ('mixed', 'Mixte', LucideIcons.flame),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tes entraînements',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Combien de fois t’entraînes-tu par semaine en moyenne ?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: frequencies.map((f) {
            final selected = _workoutsPerWeek == f.$1;
            return ChoiceChip(
              label: Text(f.$2),
              selected: selected,
              selectedColor: AppColors.calories,
              backgroundColor: AppColors.surface,
              labelStyle: TextStyle(
                color: selected ? AppColors.background : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              side: BorderSide(
                color: selected ? AppColors.calories : AppColors.border,
              ),
              onSelected: (_) => setState(() => _workoutsPerWeek = f.$1),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Type dominant',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        ...types.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectCard(
              title: t.$2,
              icon: t.$3,
              selected: _workoutType == t.$1,
              onTap: () => setState(() => _workoutType = t.$1),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _showManualTdee = !_showManualTdee),
          child: const Text(
            'Je connais déjà mon TDEE exact',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        if (_showManualTdee) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _manualTdeeCtrl,
            keyboardType: TextInputType.number,
            style: AppTheme.numericStyle(fontSize: 16),
            decoration: const InputDecoration(
              labelText: 'TDEE exact (kcal/jour)',
              hintText: 'Ex: 2450',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep5() {
    final dailyDelta = (_targetRate * 7700 / 7).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ton objectif',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tu pourras ajuster ton rythme à tout moment.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        _SelectCard(
          title: 'Perdre du poids',
          subtitle: 'Déficit calorique progressif',
          icon: LucideIcons.trendingDown,
          selected: _goalType == 'lose',
          onTap: () => setState(() {
            _goalType = 'lose';
            if (_targetRate >= 0) _targetRate = -0.4;
          }),
        ),
        const SizedBox(height: 10),
        _SelectCard(
          title: 'Maintenir mon poids',
          subtitle: 'Stabilité énergétique et recomposition',
          icon: LucideIcons.minus,
          selected: _goalType == 'maintain',
          onTap: () => setState(() {
            _goalType = 'maintain';
            _targetRate = 0.0;
          }),
        ),
        const SizedBox(height: 10),
        _SelectCard(
          title: 'Prendre du muscle',
          subtitle: 'Surplus maîtrisé',
          icon: LucideIcons.trendingUp,
          selected: _goalType == 'gain',
          onTap: () => setState(() {
            _goalType = 'gain';
            if (_targetRate <= 0) _targetRate = 0.25;
          }),
        ),
        if (_goalType != 'maintain') ...[
          const SizedBox(height: 20),
          Container(
            decoration: AppTheme.matteCardDecoration(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Rythme hebdomadaire',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${_targetRate >= 0 ? '+' : ''}${_targetRate.toStringAsFixed(2)} kg/sem (${dailyDelta >= 0 ? '+' : ''}$dailyDelta kcal/j)',
                      style: AppTheme.numericStyle(
                        fontSize: 12,
                        color: AppColors.calories,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _targetRate.clamp(-0.75, 0.50),
                  min: -0.75,
                  max: 0.50,
                  divisions: 25,
                  activeColor: AppColors.calories,
                  onChanged: (v) => setState(() => _targetRate = v),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: _targetWeightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTheme.numericStyle(fontSize: 16),
          decoration: const InputDecoration(
            labelText: 'Poids cible (kg, optionnel)',
            suffixText: 'kg',
          ),
        ),
      ],
    );
  }

  Widget _buildStep6() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Tes préférences de macros',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Dernière étape avant de calibrer ton plan nutritionnel.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          initialValue: _proteinPreference,
          decoration: const InputDecoration(labelText: 'Apport en protéines'),
          items: const [
            DropdownMenuItem(
              value: 'moderate',
              child: Text('Modéré · 1,7 g/kg'),
            ),
            DropdownMenuItem(
              value: 'high',
              child: Text('Élevé · 2,0 g/kg'),
            ),
            DropdownMenuItem(
              value: 'extra_high',
              child: Text('Très élevé · 2,3 g/kg'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _proteinPreference = v);
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: _dietStyle,
          decoration: const InputDecoration(labelText: 'Style alimentaire'),
          items: const [
            DropdownMenuItem(value: 'balanced', child: Text('Équilibré')),
            DropdownMenuItem(
              value: 'low_fat',
              child: Text('Pauvre en lipides'),
            ),
            DropdownMenuItem(
              value: 'low_carb',
              child: Text('Pauvre en glucides'),
            ),
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
            DropdownMenuItem(value: 2, child: Text('Mercredi')),
            DropdownMenuItem(value: 3, child: Text('Jeudi')),
            DropdownMenuItem(value: 4, child: Text('Vendredi')),
            DropdownMenuItem(value: 5, child: Text('Samedi')),
            DropdownMenuItem(value: 6, child: Text('Dimanche')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _checkinDay = v);
          },
        ),
      ],
    );
  }

  Widget _buildCalculating() {
    const steps = [
      'Analyse de ton profil métabolique…',
      'Estimation de ta dépense énergétique…',
      'Calibrage de tes macros sur mesure…',
    ];

    return Center(
      key: const ValueKey('calculating'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: AnimatedBuilder(
          animation: _calcController,
          builder: (context, _) {
            final t = _calcController.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CustomPaint(
                    painter: _GlowingProgressRingPainter(progress: t),
                    child: Center(
                      child: Text(
                        '${(t * 100).round()} %',
                        style: AppTheme.numericStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                ...List.generate(steps.length, (idx) {
                  final threshold = (idx + 1) / steps.length;
                  final visible = t >= idx / steps.length;
                  final done = t >= threshold;
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: visible ? 1.0 : 0.25,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            done
                                ? LucideIcons.checkCircle2
                                : LucideIcons.loader,
                            size: 18,
                            color: done
                                ? AppColors.carbs
                                : AppColors.calories,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            steps[idx],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  done ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final p = _computedProfile!;
    return Padding(
      key: const ValueKey('summary'),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Icon(
            LucideIcons.sparkles,
            color: AppColors.calories,
            size: 42,
          ),
          const SizedBox(height: 14),
          const Text(
            'Ton plan est prêt !',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Dépense estimée (TDEE) : ${p.currentTdeeKcal.round()} kcal/jour',
            textAlign: TextAlign.center,
            style: AppTheme.numericStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: AppTheme.matteCardDecoration(),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'CIBLE QUOTIDIENNE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${p.currentCalorieTarget.round()} kcal',
                  style: AppTheme.numericStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppColors.calories,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MacroSummaryTile(
                        label: 'Protéines',
                        value: '${p.currentProteinG.round()} g',
                        color: AppColors.protein,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MacroSummaryTile(
                        label: 'Lipides',
                        value: '${p.currentFatG.round()} g',
                        color: AppColors.fat,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MacroSummaryTile(
                        label: 'Glucides',
                        value: '${p.currentCarbsG.round()} g',
                        color: AppColors.carbs,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: _finishOnboarding,
            child: const Text('C’est parti !'),
          ),
        ],
      ),
    );
  }
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.calories.withValues(alpha: 0.12)
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? AppColors.calories : AppColors.border,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? AppColors.calories : AppColors.textSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  LucideIcons.checkCircle2,
                  size: 18,
                  color: AppColors.calories,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroSummaryTile extends StatelessWidget {
  const _MacroSummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTheme.numericStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowingProgressRingPainter extends CustomPainter {
  _GlowingProgressRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - stroke;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = AppColors.surfaceElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final sweepPaint = Paint()
      ..shader = const SweepGradient(
        colors: [AppColors.calories, AppColors.weight, AppColors.calories],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        sweepPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlowingProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
