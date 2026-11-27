import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/nutrition_label_scanner_screen.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen> {
  final TextEditingController _manualController = TextEditingController();
  MobileScannerController? _scannerController;

  bool _isSearching = false;
  bool _torchOn = false;
  String? _error;

  bool get _useCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (_useCamera) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _manualController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _lookupBarcode(String barcode) async {
    final clean = barcode.trim();
    if (clean.isEmpty || _isSearching) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final food =
          await ref.read(foodRepositoryProvider).getFoodByBarcode(clean);
      if (!mounted) return;
      Navigator.of(context).pop<FoodModel>(food);
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        setState(() => _isSearching = false);
        await _handleNotFound(clean);
        return;
      }
      final detail = e.response?.data is Map<String, dynamic>
          ? (e.response?.data['detail'] as String?)
          : null;
      setState(() {
        _isSearching = false;
        _error = detail ?? 'Produit introuvable pour le code $clean';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = 'Erreur lors de la recherche du code-barres';
      });
    }
  }

  Future<void> _handleNotFound(String barcode) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Produit inconnu'),
        content: Text(
          'Le code EAN $barcode est introuvable sur Open Food Facts.\n\nSouhaitez-vous scanner l’étiquette nutritionnelle ou saisir les valeurs manuellement ?',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('manual'),
            child: const Text('Saisir manuellement'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop('ocr'),
            icon: const Icon(LucideIcons.camera, size: 17),
            label: const Text('Scanner l’étiquette (OCR)'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    final created = await Navigator.of(context).push<FoodModel>(
      MaterialPageRoute(
        builder: (_) => NutritionLabelScannerScreen(
          barcode: barcode,
          startManualOnly: choice == 'manual',
        ),
      ),
    );
    if (created != null && mounted) {
      Navigator.of(context).pop<FoodModel>(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner un code-barres'),
        actions: [
          if (_useCamera)
            IconButton(
              tooltip: 'Flash',
              onPressed: () {
                _scannerController?.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
              icon: Icon(
                _torchOn ? LucideIcons.flashlightOff : LucideIcons.flashlight,
              ),
            ),
        ],
      ),
      body: _useCamera ? _buildCameraView() : _buildManualView(),
    );
  }

  Widget _buildCameraView() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: (capture) {
            final barcode = capture.barcodes.firstOrNull?.rawValue;
            if (barcode != null && barcode.isNotEmpty) {
              _lookupBarcode(barcode);
            }
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.calories, width: 2.5),
            ),
          ),
        ),
        if (_isSearching)
          Container(
            color: AppColors.background.withValues(alpha: 0.7),
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.calories),
            ),
          ),
        if (_error != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: Card(
              color: AppColors.error.withValues(alpha: 0.92),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildManualView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: AppColors.calories,
                    size: 44,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Saisie manuelle du code EAN',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'La caméra est disponible sur Android/iOS. Sur PC ou Web, saisissez un code EAN (ex. 3017620422003).',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _manualController,
                    keyboardType: TextInputType.number,
                    style: AppTheme.numericStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'Code-barres EAN',
                      hintText: '3017620422003',
                      prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                    ),
                    onSubmitted: _lookupBarcode,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isSearching
                        ? null
                        : () => _lookupBarcode(_manualController.text),
                    icon: _isSearching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : const Icon(LucideIcons.search),
                    label: const Text('Rechercher sur Open Food Facts'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
