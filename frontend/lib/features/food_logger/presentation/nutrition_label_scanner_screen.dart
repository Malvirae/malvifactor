import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:malvifactor/core/services/nutrition_ocr_service.dart';
import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/data/nutrition_label_parser.dart';

class NutritionLabelScannerScreen extends ConsumerStatefulWidget {
  const NutritionLabelScannerScreen({
    super.key,
    this.barcode,
    this.startManualOnly = false,
  });

  final String? barcode;
  final bool startManualOnly;

  @override
  ConsumerState<NutritionLabelScannerScreen> createState() =>
      _NutritionLabelScannerScreenState();
}

class _NutritionLabelScannerScreenState
    extends ConsumerState<NutritionLabelScannerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final _proteinCtrl = TextEditingController(text: '0');
  final _fatCtrl = TextEditingController(text: '0');
  final _carbsCtrl = TextEditingController(text: '0');
  final _fiberCtrl = TextEditingController(text: '0');

  String? _imagePath;
  bool _isScanning = false;
  bool _isSaving = false;
  String? _ocrInfo;

  @override
  void initState() {
    super.initState();
    if (!widget.startManualOnly && NutritionOcrService.isSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickAndScan(ImageSource.camera);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _kcalCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbsCtrl.dispose();
    _fiberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndScan(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1800,
      );
      if (picked == null || !mounted) return;

      setState(() {
        _imagePath = picked.path;
        _isScanning = true;
        _ocrInfo = null;
      });

      final rawText =
          await NutritionOcrService.recognizeTextFromImagePath(picked.path);
      if (!mounted) return;

      if (rawText == null || rawText.trim().isEmpty) {
        setState(() {
          _isScanning = false;
          _ocrInfo = NutritionOcrService.isSupported
              ? 'Aucun texte détecté. Complétez manuellement.'
              : 'OCR disponible sur Android/iOS. Saisissez les valeurs ci-dessous.';
        });
        return;
      }

      final parsed = NutritionLabelParser.parse(rawText);
      if (parsed.kcalPer100g != null) {
        _kcalCtrl.text = _fmt(parsed.kcalPer100g!);
      }
      if (parsed.proteinPer100g != null) {
        _proteinCtrl.text = _fmt(parsed.proteinPer100g!);
      }
      if (parsed.fatPer100g != null) {
        _fatCtrl.text = _fmt(parsed.fatPer100g!);
      }
      if (parsed.carbsPer100g != null) {
        _carbsCtrl.text = _fmt(parsed.carbsPer100g!);
      }
      if (parsed.fiberPer100g != null) {
        _fiberCtrl.text = _fmt(parsed.fiberPer100g!);
      }

      setState(() {
        _isScanning = false;
        _ocrInfo = 'Valeurs extraites par OCR. Vérifiez et complétez le nom.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _ocrInfo = 'Erreur OCR : $e';
      });
    }
  }

  String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0.0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final food = await ref.read(foodRepositoryProvider).createCustomFood(
            name: _nameCtrl.text.trim(),
            brand: _brandCtrl.text.trim(),
            externalId: widget.barcode,
            kcalPer100g: _parse(_kcalCtrl),
            proteinPer100g: _parse(_proteinCtrl),
            fatPer100g: _parse(_fatCtrl),
            carbsPer100g: _parse(_carbsCtrl),
            fiberPer100g: _parse(_fiberCtrl),
          );
      if (!mounted) return;
      Navigator.of(context).pop<FoodModel>(food);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la création : $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.startManualOnly
              ? 'Nouvel aliment (100 g)'
              : 'Scanner l’étiquette (OCR)',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (widget.barcode != null && widget.barcode!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: AppTheme.matteCardDecoration(borderRadius: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 16,
                        color: AppColors.calories,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Code-barres associé : ${widget.barcode}',
                        style: AppTheme.numericStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                if (NutritionOcrService.isSupported) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isScanning
                          ? null
                          : () => _pickAndScan(ImageSource.camera),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        side: const BorderSide(color: AppColors.calories),
                        foregroundColor: AppColors.calories,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(LucideIcons.camera, size: 17),
                      label: const Text('Caméra OCR'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isScanning
                        ? null
                        : () => _pickAndScan(ImageSource.gallery),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(LucideIcons.image, size: 17),
                    label: const Text('Galerie'),
                  ),
                ),
              ],
            ),
            if (_isScanning) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(color: AppColors.calories),
            ],
            if (_imagePath != null && !kIsWeb) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 120,
                  child: Image.file(
                    File(_imagePath!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            if (_ocrInfo != null) ...[
              const SizedBox(height: 10),
              Text(
                _ocrInfo!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.calories,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom du produit *',
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nom requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(
                labelText: 'Marque (optionnel)',
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Valeurs nutritionnelles pour 100 g',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _kcalCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Calories (kcal) *',
                    ),
                    validator: (v) {
                      final parsed = double.tryParse(
                        (v ?? '').trim().replaceAll(',', '.'),
                      );
                      if (parsed == null || parsed < 0) return 'Invalide';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _fiberCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Fibres (g)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _proteinCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Protéines (g)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _fatCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Lipides (g)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _carbsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Glucides (g)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background,
                      ),
                    )
                  : const Icon(LucideIcons.save),
              label: const Text('Enregistrer et choisir la quantité'),
            ),
          ],
        ),
      ),
    );
  }
}
