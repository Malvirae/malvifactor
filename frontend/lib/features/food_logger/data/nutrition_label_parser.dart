class ParsedNutritionLabel {
  const ParsedNutritionLabel({
    this.kcalPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.carbsPer100g,
    this.fiberPer100g,
  });

  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? carbsPer100g;
  final double? fiberPer100g;
}

class NutritionLabelParser {
  const NutritionLabelParser._();

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('û', 'u')
        .replaceAll('ç', 'c');
  }

  static double? _parseNumber(String raw) {
    var cleaned = raw.trim().replaceAll(',', '.').replaceAll(' ', '');
    if (cleaned.startsWith('<')) {
      final upper = double.tryParse(cleaned.substring(1));
      return upper != null ? (upper / 2.0) : null;
    }
    return double.tryParse(cleaned);
  }

  static double? _extractKcalFromText(String text) {
    final kcalMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*kcal',
      caseSensitive: false,
    ).firstMatch(text);
    if (kcalMatch != null) {
      return _parseNumber(kcalMatch.group(1)!);
    }
    return null;
  }

  static double? _extractGramsFromText(String text) {
    final gramMatch = RegExp(
      r'(<?\s*\d+(?:[.,]\d+)?)\s*g\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (gramMatch != null) {
      return _parseNumber(gramMatch.group(1)!);
    }
    final fallbackNum = RegExp(r'(<?\s*\d+(?:[.,]\d+)?)').firstMatch(text);
    if (fallbackNum != null) {
      return _parseNumber(fallbackNum.group(1)!);
    }
    return null;
  }

  static ParsedNutritionLabel parse(String rawText) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    double? kcal;
    double? fat;
    double? carbs;
    double? fiber;
    double? protein;

    for (var i = 0; i < lines.length; i++) {
      final line = _normalize(lines[i]);
      final nextLine = i + 1 < lines.length ? _normalize(lines[i + 1]) : '';
      final combined = '$line $nextLine';

      if (kcal == null &&
          (line.contains('energie') ||
              line.contains('energy') ||
              line.contains('kcal'))) {
        kcal = _extractKcalFromText(line) ?? _extractKcalFromText(combined);
      }

      if (fat == null &&
          (line.contains('matieres grasses') ||
              line.contains('lipides') ||
              RegExp(r'\bfat\b').hasMatch(line)) &&
          !line.contains('sat') &&
          !line.contains('dont')) {
        fat = _extractGramsFromText(line) ?? _extractGramsFromText(nextLine);
      }

      if (carbs == null &&
          (line.contains('glucides') ||
              line.contains('carbohydrate') ||
              RegExp(r'\bcarbs?\b').hasMatch(line)) &&
          !line.contains('sucres') &&
          !line.contains('sugar') &&
          !line.contains('dont')) {
        carbs = _extractGramsFromText(line) ?? _extractGramsFromText(nextLine);
      }

      if (fiber == null &&
          (line.contains('fibre') || line.contains('fiber'))) {
        fiber = _extractGramsFromText(line) ?? _extractGramsFromText(nextLine);
      }

      if (protein == null && line.contains('protein')) {
        protein =
            _extractGramsFromText(line) ?? _extractGramsFromText(nextLine);
      }
    }

    // Fallback global search for kcal if the label line was split
    kcal ??= _extractKcalFromText(_normalize(rawText));

    return ParsedNutritionLabel(
      kcalPer100g: kcal,
      proteinPer100g: protein,
      fatPer100g: fat,
      carbsPer100g: carbs,
      fiberPer100g: fiber,
    );
  }
}
