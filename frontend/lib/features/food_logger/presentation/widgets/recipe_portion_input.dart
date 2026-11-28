import 'package:flutter/material.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

String formatFrNumber(
  double value, {
  int decimals = 1,
  bool trimTrailingZero = true,
  bool spaceThousands = false,
}) {
  if (!value.isFinite) return '0';
  final rounded = decimals <= 0
      ? value.round().toString()
      : value.toStringAsFixed(decimals);
  var parts = rounded.split('.');
  var intPart = parts[0];
  var decPart = parts.length > 1 ? parts[1] : '';

  if (spaceThousands && intPart.length > 3) {
    final buf = StringBuffer();
    final negative = intPart.startsWith('-');
    final digits = negative ? intPart.substring(1) : intPart;
    for (var i = 0; i < digits.length; i++) {
      final revIdx = digits.length - i;
      if (i > 0 && revIdx % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    intPart = negative ? '-${buf.toString()}' : buf.toString();
  }

  if (trimTrailingZero && decPart.isNotEmpty) {
    decPart = decPart.replaceFirst(RegExp(r'0+$'), '');
  }

  if (decPart.isEmpty) return intPart;
  return '$intPart,$decPart';
}

String formatGramsText(double grams) =>
    '${formatFrNumber(grams, decimals: 1, spaceThousands: true)} g';

String formatPortionsWord(double portions) =>
    portions >= 1.995 ? 'portions' : 'portion';

bool isSimpleServingMultiple(double quantityG, double servingWeightG) {
  if (quantityG <= 0 || servingWeightG <= 0) return false;
  final ratio = quantityG / servingWeightG;
  final nearestQuarter = (ratio * 4).round() / 4.0;
  if (nearestQuarter <= 0) return false;
  return (ratio - nearestQuarter).abs() <= 0.025 ||
      (quantityG - nearestQuarter * servingWeightG).abs() <= 1.0;
}

double snapPortionValue(double quantityG, double servingWeightG) {
  if (servingWeightG <= 0) return 1.0;
  final ratio = quantityG / servingWeightG;
  if (isSimpleServingMultiple(quantityG, servingWeightG)) {
    return (ratio * 4).round() / 4.0;
  }
  return ratio;
}

String formatRecipeUnitSubtitle(double quantityG, double? servingWeightG) {
  if (servingWeightG == null || servingWeightG <= 0) {
    return formatGramsText(quantityG);
  }
  final ratio = quantityG / servingWeightG;
  if (isSimpleServingMultiple(quantityG, servingWeightG)) {
    final p = snapPortionValue(quantityG, servingWeightG);
    return '${formatFrNumber(p, decimals: 2)} ${formatPortionsWord(p)} (${formatGramsText(quantityG)})';
  }
  return '${formatGramsText(quantityG)} (${formatFrNumber(ratio, decimals: 2, trimTrailingZero: false)} ${formatPortionsWord(ratio)})';
}

class ColoredMacroInlineRow extends StatelessWidget {
  const ColoredMacroInlineRow({
    super.key,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    this.prefix,
    this.suffix,
    this.fontSize = 12.5,
    this.macroDecimals = 1,
    this.trimMacroZero = true,
  });

  final double kcal;
  final double proteinG;
  final double fatG;
  final double carbsG;
  final String? prefix;
  final String? suffix;
  final double fontSize;
  final int macroDecimals;
  final bool trimMacroZero;

  @override
  Widget build(BuildContext context) {
    final safeKcal = kcal.isFinite ? kcal : 0.0;
    final safeP = proteinG.isFinite ? proteinG : 0.0;
    final safeF = fatG.isFinite ? fatG : 0.0;
    final safeC = carbsG.isFinite ? carbsG : 0.0;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: AppTheme.numericStyle(
            fontSize: fontSize,
            color: AppColors.textSecondary,
          ),
          children: [
            if (prefix != null && prefix!.isNotEmpty) TextSpan(text: prefix),
            TextSpan(
              text: '${safeKcal.round()} kcal',
              style: const TextStyle(
                color: AppColors.calories,
                fontWeight: FontWeight.w800,
              ),
            ),
            const TextSpan(text: ' • '),
            TextSpan(
              text:
                  '${formatFrNumber(safeP, decimals: macroDecimals, trimTrailingZero: trimMacroZero)}P ',
              style: const TextStyle(
                color: AppColors.protein,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text:
                  '${formatFrNumber(safeF, decimals: macroDecimals, trimTrailingZero: trimMacroZero)}L ',
              style: const TextStyle(
                color: AppColors.fat,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text:
                  '${formatFrNumber(safeC, decimals: macroDecimals, trimTrailingZero: trimMacroZero)}G',
              style: const TextStyle(
                color: AppColors.carbs,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (suffix != null && suffix!.isNotEmpty) TextSpan(text: suffix),
          ],
        ),
      ),
    );
  }
}

class PortionAwareQuantitySection extends StatefulWidget {
  const PortionAwareQuantitySection({
    super.key,
    required this.initialQuantityG,
    this.servingWeightG,
    this.totalWeightG,
    this.servingsCount,
    this.showGramQuickChips = false,
    this.autofocus = false,
    this.trailingBesideInput,
    required this.onQuantityChanged,
  });

  final double initialQuantityG;
  final double? servingWeightG;
  final double? totalWeightG;
  final double? servingsCount;
  final bool showGramQuickChips;
  final bool autofocus;
  final Widget? trailingBesideInput;
  final ValueChanged<double> onQuantityChanged;

  @override
  State<PortionAwareQuantitySection> createState() =>
      _PortionAwareQuantitySectionState();
}

class _PortionAwareQuantitySectionState
    extends State<PortionAwareQuantitySection> {
  static const List<double> _quickPortions = [0.5, 1.0, 1.5, 2.0];
  static const List<int> _quickGrams = [30, 50, 100, 150, 200, 250];

  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  late bool _isPortionsMode;
  late double _quantityG;
  double _portions = 1.0;

  bool get _supportsPortions =>
      widget.servingWeightG != null && widget.servingWeightG! > 0;

  @override
  void initState() {
    super.initState();
    _quantityG = widget.initialQuantityG > 0
        ? widget.initialQuantityG
        : (widget.servingWeightG != null && widget.servingWeightG! > 0
            ? widget.servingWeightG!
            : 100.0);

    if (_supportsPortions &&
        isSimpleServingMultiple(_quantityG, widget.servingWeightG!)) {
      _isPortionsMode = true;
      _portions = snapPortionValue(_quantityG, widget.servingWeightG!);
      _quantityG = double.parse(
        (_portions * widget.servingWeightG!).toStringAsFixed(1),
      );
      _controller = TextEditingController(text: _formatInput(_portions));
    } else {
      _isPortionsMode = false;
      _portions = _supportsPortions
          ? _quantityG / widget.servingWeightG!
          : 1.0;
      _controller = TextEditingController(text: _formatInput(_quantityG));
    }

    _focusNode.addListener(_selectAllOnFocus);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.text.isNotEmpty) {
          _focusNode.requestFocus();
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        }
      });
    }
  }

  void _selectAllOnFocus() {
    if (_focusNode.hasFocus && _controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_focusNode.hasFocus && _controller.text.isNotEmpty) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_selectAllOnFocus);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _formatInput(double val) {
    if ((val - val.round()).abs() < 0.005) {
      return val.round().toString();
    }
    return val
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _switchMode(bool toPortions) {
    if (!_supportsPortions || toPortions == _isPortionsMode) return;
    final sw = widget.servingWeightG!;
    setState(() {
      _isPortionsMode = toPortions;
      if (toPortions) {
        final rawPortions = _quantityG > 0 ? _quantityG / sw : 1.0;
        _portions = isSimpleServingMultiple(_quantityG, sw)
            ? snapPortionValue(_quantityG, sw)
            : double.parse(rawPortions.toStringAsFixed(2));
        _controller.text = _formatInput(_portions);
        _quantityG = double.parse((_portions * sw).toStringAsFixed(1));
      } else {
        _quantityG = double.parse((_portions * sw).toStringAsFixed(1));
        _controller.text = _formatInput(_quantityG);
      }
      if (_focusNode.hasFocus && _controller.text.isNotEmpty) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      }
    });
    widget.onQuantityChanged(_quantityG);
  }

  void _setPortions(double p) {
    if (!_supportsPortions) return;
    final sw = widget.servingWeightG!;
    final newGrams = double.parse((p * sw).toStringAsFixed(1));
    setState(() {
      _isPortionsMode = true;
      _portions = p;
      _quantityG = newGrams;
      _controller.text = _formatInput(p);
    });
    widget.onQuantityChanged(newGrams);
  }

  void _setGrams(double grams) {
    setState(() {
      _isPortionsMode = false;
      _quantityG = grams;
      if (_supportsPortions) {
        _portions = grams / widget.servingWeightG!;
      }
      _controller.text = _formatInput(grams);
    });
    widget.onQuantityChanged(grams);
  }

  void _onTextChanged(String raw) {
    final parsed = double.tryParse(raw.replaceAll(',', '.').trim());
    if (parsed == null || parsed < 0) {
      if (_quantityG != 0.0) {
        setState(() {
          _quantityG = 0.0;
          if (_isPortionsMode) _portions = 0.0;
        });
        widget.onQuantityChanged(0.0);
      }
      return;
    }

    if (_isPortionsMode && _supportsPortions) {
      final sw = widget.servingWeightG!;
      final newGrams = double.parse((parsed * sw).toStringAsFixed(1));
      setState(() {
        _portions = parsed;
        _quantityG = newGrams;
      });
      widget.onQuantityChanged(newGrams);
    } else {
      setState(() {
        _quantityG = parsed;
        if (_supportsPortions) {
          _portions = parsed / widget.servingWeightG!;
        }
      });
      widget.onQuantityChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = widget.servingWeightG;
    final textField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppTheme.numericStyle(fontSize: 16, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: _isPortionsMode ? 'Nombre de portions' : 'Quantité (g)',
        suffixText: _isPortionsMode ? 'part' : 'g',
      ),
      onChanged: _onTextChanged,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_supportsPortions) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ModePill(
                    label: 'Portions',
                    selected: _isPortionsMode,
                    onTap: () => _switchMode(true),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _ModePill(
                    label: 'Grammes (g)',
                    selected: !_isPortionsMode,
                    onTap: () => _switchMode(false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.trailingBesideInput != null)
          Row(
            children: [
              Expanded(flex: 3, child: textField),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: widget.trailingBesideInput!),
            ],
          )
        else
          textField,
        if (_supportsPortions && sw != null) ...[
          const SizedBox(height: 8),
          _buildEquivalenceBanner(sw),
          if (_isPortionsMode) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickPortions.map((p) {
                final selected = (_portions - p).abs() < 0.015;
                return ChoiceChip(
                  label: Text(formatFrNumber(p, decimals: 1)),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppColors.calories,
                  backgroundColor: AppColors.surfaceElevated,
                  side: BorderSide(
                    color: selected ? AppColors.calories : AppColors.border,
                  ),
                  labelStyle: AppTheme.numericStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.background
                        : AppColors.textPrimary,
                  ),
                  onSelected: (_) => _setPortions(p),
                );
              }).toList(),
            ),
          ] else if (widget.showGramQuickChips) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickGrams.map((g) {
                final selected = (_quantityG - g).abs() < 0.01;
                return ChoiceChip(
                  label: Text('${g}g'),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppColors.calories,
                  backgroundColor: AppColors.surfaceElevated,
                  side: BorderSide(
                    color: selected ? AppColors.calories : AppColors.border,
                  ),
                  labelStyle: AppTheme.numericStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.background
                        : AppColors.textPrimary,
                  ),
                  onSelected: (_) => _setGrams(g.toDouble()),
                );
              }).toList(),
            ),
          ],
        ] else if (widget.showGramQuickChips) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickGrams.map((g) {
              final selected = (_quantityG - g).abs() < 0.01;
              return ChoiceChip(
                label: Text('${g}g'),
                selected: selected,
                showCheckmark: false,
                selectedColor: AppColors.calories,
                backgroundColor: AppColors.surfaceElevated,
                side: BorderSide(
                  color: selected ? AppColors.calories : AppColors.border,
                ),
                labelStyle: AppTheme.numericStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.background
                      : AppColors.textPrimary,
                ),
                onSelected: (_) => _setGrams(g.toDouble()),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildEquivalenceBanner(double sw) {
    final cyan = const Color(0xFF22D3EE);
    if (_isPortionsMode) {
      final portionsStr = formatFrNumber(_portions, decimals: 2);
      final totalPortionsStr = widget.servingsCount != null &&
              widget.servingsCount! > 0
          ? formatFrNumber(widget.servingsCount!, decimals: 1)
          : null;
      final totalWeightStr = widget.totalWeightG != null &&
              widget.totalWeightG! > 0
          ? formatGramsText(widget.totalWeightG!)
          : null;

      final detailParts = <String>[
        if (totalPortionsStr != null) '$portionsStr / $totalPortionsStr de la recette',
        if (totalWeightStr != null) '$totalWeightStr au total',
      ];

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cyan.withValues(alpha: 0.3)),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 2,
          children: [
            Text(
              '= ${formatGramsText(_quantityG)}',
              style: AppTheme.numericStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: cyan,
              ),
            ),
            if (detailParts.isNotEmpty)
              Text(
                '(${detailParts.join(' — ')})',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      );
    }

    final equivPortions = sw > 0 ? (_quantityG / sw) : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cyan.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 2,
        children: [
          Text(
            '≈ ${formatFrNumber(equivPortions, decimals: 2, trimTrailingZero: false)} ${formatPortionsWord(equivPortions)}',
            style: AppTheme.numericStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: cyan,
            ),
          ),
          Text(
            '(1 portion = ${formatGramsText(sw)})',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF22D3EE) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.background : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
