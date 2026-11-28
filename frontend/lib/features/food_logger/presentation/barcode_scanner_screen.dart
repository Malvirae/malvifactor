import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:malvifactor/core/theme/app_theme.dart';
import 'package:malvifactor/features/food_logger/data/food_repository.dart';
import 'package:malvifactor/features/food_logger/presentation/nutrition_label_scanner_screen.dart';

class BarcodeScannerScreen extends ConsumerStatefulWidget {
  const BarcodeScannerScreen({
    super.key,
    this.isActive = true,
  });

  final bool isActive;

  @override
  ConsumerState<BarcodeScannerScreen> createState() =>
      _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends ConsumerState<BarcodeScannerScreen>
    with WidgetsBindingObserver {
  final TextEditingController _manualController = TextEditingController();
  MobileScannerController? _scannerController;

  bool _isSearching = false;
  bool _torchOn = false;
  bool _startingCamera = false;
  bool _permissionGranted = false;
  bool _permanentlyDenied = false;
  String? _cameraError;
  String? _error;

  bool get _useCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_useCamera) {
      _scannerController = MobileScannerController(
        autoStart: false,
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      if (widget.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.isActive) {
            _initAndStartCamera();
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant BarcodeScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_useCamera) return;
    if (!oldWidget.isActive && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) {
          _initAndStartCamera();
        }
      });
    } else if (oldWidget.isActive && !widget.isActive) {
      _stopCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_useCamera) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && widget.isActive) {
      _initAndStartCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _stopCamera() async {
    final ctrl = _scannerController;
    if (ctrl == null) return;
    try {
      if (ctrl.value.isRunning) {
        await ctrl.stop();
      }
    } catch (_) {
      // Ignore stop errors during teardown/backgrounding.
    }
  }

  Future<void> _initAndStartCamera() async {
    final ctrl = _scannerController;
    if (!_useCamera || ctrl == null || _startingCamera || !widget.isActive) {
      return;
    }

    _startingCamera = true;
    if (mounted) {
      setState(() {
        _cameraError = null;
      });
    }

    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request();
      }

      if (!mounted) return;

      if (status.isPermanentlyDenied || status.isRestricted) {
        setState(() {
          _permissionGranted = false;
          _permanentlyDenied = true;
          _cameraError =
              'L’accès à la caméra est refusé de façon permanente. Activez-le dans les paramètres de l’application.';
        });
        return;
      }

      if (!status.isGranted) {
        setState(() {
          _permissionGranted = false;
          _permanentlyDenied = false;
          _cameraError =
              'La permission caméra est nécessaire pour scanner un code-barres.';
        });
        return;
      }

      setState(() {
        _permissionGranted = true;
        _permanentlyDenied = false;
      });

      // Wait briefly for the system permission dialog to close and surface to attach.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!mounted || !widget.isActive) return;

      if (!ctrl.value.isRunning) {
        await ctrl.start();
      }
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      final details = e.errorDetails?.message;
      setState(() {
        _cameraError =
            'Erreur caméra (${e.errorCode.name})${details != null && details.isNotEmpty ? ' : $details' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Impossible de démarrer la caméra : $e';
      });
    } finally {
      _startingCamera = false;
    }
  }

  Future<void> _retryCamera() async {
    await _stopCamera();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _initAndStartCamera();
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
          if (_useCamera && _permissionGranted && _cameraError == null)
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

  Widget _buildCameraErrorPanel({
    required String message,
    bool showSettings = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: AppTheme.matteCardDecoration(),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                LucideIcons.cameraOff,
                color: AppColors.error,
                size: 40,
              ),
              const SizedBox(height: 14),
              const Text(
                'Caméra indisponible',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _retryCamera,
                icon: const Icon(LucideIcons.refreshCw, size: 17),
                label: const Text('Réessayer'),
              ),
              if (showSettings) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await openAppSettings();
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  icon: const Icon(LucideIcons.settings, size: 17),
                  label: const Text('Ouvrir les paramètres'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (_cameraError != null) {
      return _buildCameraErrorPanel(
        message: _cameraError!,
        showSettings: _permanentlyDenied,
      );
    }

    if (!_permissionGranted) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.calories),
            SizedBox(height: 14),
            Text(
              'Initialisation de la caméra...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          errorBuilder: (context, error, _) {
            final details = error.errorDetails?.message;
            final isDenied =
                error.errorCode == MobileScannerErrorCode.permissionDenied;
            return _buildCameraErrorPanel(
              message:
                  'Erreur scanner (${error.errorCode.name})${details != null && details.isNotEmpty ? ' : $details' : ''}',
              showSettings: isDenied || _permanentlyDenied,
            );
          },
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
                  ElevatedButton(
                    onPressed: _isSearching
                        ? null
                        : () => _lookupBarcode(_manualController.text),
                    child: _isSearching
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : const Text('Rechercher'),
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
