import 'package:flutter/material.dart';

import 'package:malvifactor/core/theme/app_theme.dart';

class FoodCategoryStyle {
  const FoodCategoryStyle({
    this.emoji,
    required this.tintColor,
  });

  final String? emoji;
  final Color tintColor;
}

class FoodCategoryResolver {
  const FoodCategoryResolver._();

  static final Map<String, FoodCategoryStyle> _cache =
      <String, FoodCategoryStyle>{};
  static const int _maxCacheEntries = 1000;

  static String normalize(String input) {
    final lower = input.toLowerCase();
    final buf = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final ch = lower[i];
      switch (ch) {
        case 'à':
        case 'á':
        case 'â':
        case 'ä':
        case 'ã':
        case 'å':
          buf.write('a');
        case 'é':
        case 'è':
        case 'ê':
        case 'ë':
          buf.write('e');
        case 'ì':
        case 'í':
        case 'î':
        case 'ï':
          buf.write('i');
        case 'ò':
        case 'ó':
        case 'ô':
        case 'ö':
        case 'õ':
          buf.write('o');
        case 'ù':
        case 'ú':
        case 'û':
        case 'ü':
          buf.write('u');
        case 'ç':
          buf.write('c');
        case 'ñ':
          buf.write('n');
        case 'œ':
          buf.write('oe');
        case 'æ':
          buf.write('ae');
        default:
          final code = ch.codeUnitAt(0);
          final isAlphaNum =
              (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
          buf.write(isAlphaNum ? ch : ' ');
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Matches any whole word or prefix safely (avoids substring false positives
  /// like 'eau' inside 'gateau' or 'riz' inside 'chorizo').
  static bool _hasWord(String norm, List<String> words) {
    for (final w in words) {
      final escaped = RegExp.escape(w);
      if (RegExp('(?:^|\\s)$escaped(?:s|x)?(?:\\s|\$)').hasMatch(norm)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasPrefix(String norm, List<String> prefixes) {
    for (final p in prefixes) {
      final escaped = RegExp.escape(p);
      if (RegExp('(?:^|\\s)$escaped').hasMatch(norm)) {
        return true;
      }
    }
    return false;
  }

  static FoodCategoryStyle resolve({
    required String name,
    String? source,
    String? category,
  }) {
    final cacheKey = '${source ?? ''}|$name|${category ?? ''}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final resolved = _resolveUncached(
      name: name,
      source: source,
      category: category,
    );
    if (_cache.length >= _maxCacheEntries) {
      _cache.clear();
    }
    _cache[cacheKey] = resolved;
    return resolved;
  }

  static FoodCategoryStyle _resolveUncached({
    required String name,
    String? source,
    String? category,
  }) {
    final normName = normalize(name);
    final combined = normalize('$name ${category ?? ''}');

    // 1. Recipe (default 🍲 cyan unless the recipe name explicitly targets pizza/burger/cake/etc.)
    if (source == 'recipe') {
      if (_hasPrefix(normName, ['pizza'])) {
        return const FoodCategoryStyle(emoji: '🍕', tintColor: Color(0xFFF59E0B));
      }
      if (_hasPrefix(normName, ['burger', 'hamburger'])) {
        return const FoodCategoryStyle(emoji: '🍔', tintColor: Color(0xFFF59E0B));
      }
      if (_hasPrefix(normName, ['gateau', 'brownie', 'muffin', 'cake', 'fondant', 'tarte'])) {
        return const FoodCategoryStyle(emoji: '🧁', tintColor: Color(0xFFEC4899));
      }
      if (_hasPrefix(normName, ['salade'])) {
        return const FoodCategoryStyle(emoji: '🥗', tintColor: Color(0xFF4ADE80));
      }
      if (_hasPrefix(normName, ['pancake', 'crepe', 'gaufre', 'wrap', 'tortilla'])) {
        return const FoodCategoryStyle(emoji: '🫓', tintColor: Color(0xFFD97706));
      }
      return const FoodCategoryStyle(emoji: '🍲', tintColor: Color(0xFF22D3EE));
    }

    // Special disambiguations that must precede generic butter/condiment/fruit rules
    if (_hasPrefix(combined, ['beurre de cacahuete', 'beurre d amande', 'beurre de noisette', 'puree d amande', 'puree de cacahuete'])) {
      return const FoodCategoryStyle(emoji: '🥜', tintColor: Color(0xFFB45309));
    }
    if (_hasPrefix(combined, ['pate a tartiner', 'nutella'])) {
      return const FoodCategoryStyle(emoji: '🍫', tintColor: Color(0xFFEC4899));
    }
    if (_hasWord(combined, ['chip', 'chips'])) {
      return const FoodCategoryStyle(emoji: '🥔', tintColor: Color(0xFFF59E0B));
    }

    // 2. Whey / Protein powder / Shaker / Protein bars
    if (_hasPrefix(combined, [
      'whey',
      'clear whey',
      'isolate',
      'caseine',
      'shaker',
      'barre prot',
      'protein bar',
      'barre proteinee',
      'proteine en poudre',
      'poudre proteinee',
    ]) || _hasWord(combined, ['proteine', 'proteines'])) {
      final isPowderMilk = _hasPrefix(combined, ['caseine', 'shaker']);
      return FoodCategoryStyle(
        emoji: isPowderMilk ? '🥛' : '🥤',
        tintColor: const Color(0xFFA78BFA),
      );
    }

    // 3. Caramel & Oils/Fats (evaluated before condiments so 'caramel au beurre sale' / 'beurre demi-sel' match cleanly)
    if (_hasPrefix(combined, ['caramel'])) {
      return const FoodCategoryStyle(emoji: '🍬', tintColor: Color(0xFFEC4899));
    }
    if (_hasPrefix(combined, ['huile', 'colza', 'tournesol']) ||
        _hasWord(combined, ['olive', 'olives'])) {
      return const FoodCategoryStyle(emoji: '🫒', tintColor: Color(0xFFEAB308));
    }
    if (_hasPrefix(combined, [
      'beurre',
      'margarine',
      'ghee',
      'creme fraiche',
      'creme liquide',
      'creme entiere',
      'creme legere',
    ])) {
      return const FoodCategoryStyle(emoji: '🧈', tintColor: Color(0xFFEAB308));
    }

    // 4. Sauces & Dressings (pure salt/pepper/spices are evaluated after all food categories)
    if (_hasPrefix(combined, [
          'sauce',
          'ketchup',
          'mayo',
          'mayonnaise',
          'moutarde',
          'barbecue',
          'vinaigrette',
          'vinaigre',
          'pesto',
          'harissa',
          'sriracha',
          'bouillon',
          'tabasco',
        ]) ||
        _hasWord(combined, ['bbq', 'soja'])) {
      return const FoodCategoryStyle(emoji: '🥫', tintColor: Color(0xFFF97316));
    }

    // 5. Fries & Potatoes
    if (_hasPrefix(combined, ['frite', 'potatoes'])) {
      return const FoodCategoryStyle(emoji: '🍟', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['pomme de terre', 'puree', 'gnocchi', 'patate']) ||
        _hasWord(combined, ['chip', 'chips'])) {
      return const FoodCategoryStyle(emoji: '🥔', tintColor: Color(0xFFF59E0B));
    }

    // 6. Poultry
    if (_hasPrefix(combined, [
      'poulet',
      'dinde',
      'volaille',
      'canard',
      'milanaise',
      'nugget',
      'cordon bleu',
      'escalope',
      'blanc de poulet',
      'aiguillette',
      'pintade',
    ])) {
      return const FoodCategoryStyle(emoji: '🍗', tintColor: Color(0xFFFB923C));
    }

    // 7. Meats & Charcuterie
    if (_hasPrefix(combined, ['bacon', 'lardon', 'jambon', 'pancetta'])) {
      return const FoodCategoryStyle(emoji: '🥓', tintColor: Color(0xFFEF4444));
    }
    if (_hasPrefix(combined, [
      'boeuf',
      'steak',
      'hache',
      'porc',
      'saucisse',
      'chorizo',
      'veau',
      'agneau',
      'viande',
      'bavette',
      'entrecote',
      'roti',
      'merguez',
      'chipolata',
      'salami',
      'rosette',
      'coppa',
      'bresaola',
      'filet mignon',
    ]) || _hasWord(combined, ['cote', 'cotes'])) {
      return const FoodCategoryStyle(emoji: '🥩', tintColor: Color(0xFFEF4444));
    }

    // 8. Fish & Seafood
    if (_hasPrefix(combined, ['crevette', 'gambas', 'langoustine'])) {
      return const FoodCategoryStyle(emoji: '🍤', tintColor: Color(0xFF38BDF8));
    }
    if (_hasPrefix(combined, [
      'saumon',
      'thon',
      'cabillaud',
      'colin',
      'poisson',
      'truite',
      'sardine',
      'maquereau',
      'calamar',
      'moule',
      'surimi',
      'crabe',
      'huitre',
      'merlu',
      'dorade',
      'hareng',
      'lieu noir',
    ])) {
      return const FoodCategoryStyle(emoji: '🐟', tintColor: Color(0xFF38BDF8));
    }

    // 9. Eggs
    if (_hasPrefix(combined, ['oeuf', 'omelette', 'blanc d oeuf'])) {
      return const FoodCategoryStyle(emoji: '🥚', tintColor: Color(0xFFFDE047));
    }

    // 10. Dairy & Skyr (before generic cheese so 'fromage blanc' hits dairy)
    if (_hasPrefix(combined, [
      'skyr',
      'yaourt',
      'yogourt',
      'fromage blanc',
      'petit suisse',
      'creme dessert',
      'danette',
      'pudding',
      'flan',
      'faisselle',
    ])) {
      return const FoodCategoryStyle(emoji: '🥣', tintColor: Color(0xFF60A5FA));
    }
    if (_hasPrefix(combined, ['kefir']) || _hasWord(combined, ['lait'])) {
      return const FoodCategoryStyle(emoji: '🥛', tintColor: Color(0xFF60A5FA));
    }

    // 11. Cheese
    if (_hasPrefix(combined, [
      'fromage',
      'reblochon',
      'comte',
      'emmental',
      'gruyere',
      'mozzarella',
      'parmesan',
      'cheddar',
      'feta',
      'camembert',
      'chevre',
      'raclette',
      'roquefort',
      'mascarpone',
      'ricotta',
      'cantal',
      'kiri',
      'vache qui rit',
      'st moret',
      'saint moret',
      'boursin',
      'philadelphia',
      'burrata',
      'mimolette',
      'beaufort',
      'tomme',
    ]) || _hasWord(combined, ['brie', 'tome'])) {
      return const FoodCategoryStyle(emoji: '🧀', tintColor: Color(0xFFFACC15));
    }

    // 12. Pasta, Crozets & Noodles
    if (_hasPrefix(combined, [
      'spaghetti',
      'penne',
      'coquillette',
      'tagliatelle',
      'fusilli',
      'macaroni',
      'crozet',
      'nouille',
      'ramen',
      'udon',
      'lasagne',
      'ravioli',
      'tortellini',
      'semoule',
      'couscous',
      'boulgour',
      'quinoa',
      'farfalle',
      'rigatoni',
      'linguine',
    ]) || _hasWord(combined, ['pate', 'pates'])) {
      return const FoodCategoryStyle(emoji: '🍝', tintColor: Color(0xFFF59E0B));
    }

    // 13. Rice & Oats
    if (_hasPrefix(combined, ['basmati', 'jasmin', 'risotto']) ||
        _hasWord(combined, ['riz'])) {
      return const FoodCategoryStyle(emoji: '🍚', tintColor: Color(0xFFFBBF24));
    }
    if (_hasPrefix(combined, [
      'avoine',
      'flocon',
      'muesli',
      'granola',
      'cereale',
      'corn flakes',
      'porridge',
    ])) {
      return const FoodCategoryStyle(emoji: '🥣', tintColor: Color(0xFFFBBF24));
    }

    // 14. Bread, Wraps & Bakery
    if (_hasPrefix(combined, ['croissant', 'pain au chocolat', 'brioche', 'viennoiserie'])) {
      return const FoodCategoryStyle(emoji: '🥐', tintColor: Color(0xFFD97706));
    }
    if (_hasPrefix(combined, ['wrap', 'tortilla', 'galette', 'crepe', 'pancake', 'gaufre'])) {
      return const FoodCategoryStyle(emoji: '🫓', tintColor: Color(0xFFD97706));
    }
    if (_hasPrefix(combined, [
      'baguette',
      'biscotte',
      'pain de mie',
      'toast',
      'bagel',
      'focaccia',
      'wasa',
      'cracotte',
    ]) || _hasWord(combined, ['pain', 'pains'])) {
      return const FoodCategoryStyle(emoji: '🍞', tintColor: Color(0xFFD97706));
    }

    // 15. Fast food / Prepared meals
    if (_hasPrefix(combined, ['pizza'])) {
      return const FoodCategoryStyle(emoji: '🍕', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['burger', 'hamburger'])) {
      return const FoodCategoryStyle(emoji: '🍔', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['sandwich', 'panini', 'tacos', 'kebab', 'croque'])) {
      return const FoodCategoryStyle(emoji: '🥪', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['sushi', 'maki', 'california'])) {
      return const FoodCategoryStyle(emoji: '🍣', tintColor: Color(0xFF38BDF8));
    }
    if (_hasPrefix(combined, ['rouleau de printemps', 'gyoza', 'dumpling', 'samoussa']) ||
        _hasWord(combined, ['nem', 'nems'])) {
      return const FoodCategoryStyle(emoji: '🥟', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['quiche', 'tarte salee'])) {
      return const FoodCategoryStyle(emoji: '🥧', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['salade composee'])) {
      return const FoodCategoryStyle(emoji: '🥗', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['soupe', 'veloute', 'potage'])) {
      return const FoodCategoryStyle(emoji: '🍲', tintColor: Color(0xFF4ADE80));
    }

    // Drinks (checked before generic fruits so 'jus d'orange', 'thé pêche', 'ice tea' match drink icons)
    if (_hasPrefix(combined, [
      'cafe',
      'espresso',
      'cappuccino',
      'latte',
      'infusion',
      'matcha',
      'tisane',
    ]) || _hasWord(combined, ['the', 'thes'])) {
      return const FoodCategoryStyle(emoji: '☕', tintColor: Color(0xFF92400E));
    }
    if (_hasPrefix(combined, ['biere', 'cidre']) || _hasWord(combined, ['ipa'])) {
      return const FoodCategoryStyle(emoji: '🍺', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, [
      'cocktail',
      'alcool',
      'genepi',
      'rhum',
      'whisky',
      'champagne',
      'vodka',
      'aperol',
      'spritz',
    ]) || _hasWord(combined, ['vin', 'vins', 'gin'])) {
      return const FoodCategoryStyle(emoji: '🍷', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, [
      'perrier',
      'soda',
      'cola',
      'pepsi',
      'coca',
      'ice tea',
      'fuze tea',
      'smoothie',
      'boisson',
      'live fit',
      'energy',
      'monster',
      'red bull',
      'sirop a l eau',
      'limonade',
      'orangina',
      'schweppes',
    ]) || _hasWord(combined, ['eau', 'eaux', 'jus'])) {
      return const FoodCategoryStyle(emoji: '🥤', tintColor: Color(0xFF06B6D4));
    }

    // 16. Vegetables & Legumes
    if (_hasPrefix(combined, ['tomate'])) {
      return const FoodCategoryStyle(emoji: '🍅', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['avocat'])) {
      return const FoodCategoryStyle(emoji: '🥑', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['carotte'])) {
      return const FoodCategoryStyle(emoji: '🥕', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['salade', 'laitue', 'roquette', 'mache'])) {
      return const FoodCategoryStyle(emoji: '🥗', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['champignon'])) {
      return const FoodCategoryStyle(emoji: '🍄', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['concombre', 'cornichon'])) {
      return const FoodCategoryStyle(emoji: '🥒', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['aubergine'])) {
      return const FoodCategoryStyle(emoji: '🍆', tintColor: Color(0xFF4ADE80));
    }
    if (_hasWord(combined, ['mais'])) {
      return const FoodCategoryStyle(emoji: '🌽', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, [
      'legume',
      'brocoli',
      'haricot',
      'courgette',
      'oignon',
      'poivron',
      'epinard',
      'chou',
      'poireau',
      'petit pois',
      'lentille',
      'pois chiche',
      'radis',
      'betterave',
      'courge',
      'potiron',
      'asperge',
      'celeri',
      'endive',
      'fenouil',
    ])) {
      return const FoodCategoryStyle(emoji: '🥦', tintColor: Color(0xFF4ADE80));
    }

    // 17. Fruits & Compotes
    if (_hasPrefix(combined, ['banane'])) {
      return const FoodCategoryStyle(emoji: '🍌', tintColor: Color(0xFFFACC15));
    }
    if (_hasPrefix(combined, ['fraise', 'framboise', 'myrtille', 'mure'])) {
      return const FoodCategoryStyle(emoji: '🍓', tintColor: Color(0xFFF43F5E));
    }
    if (_hasPrefix(combined, ['kiwi'])) {
      return const FoodCategoryStyle(emoji: '🥝', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['orange', 'clementine', 'mandarine', 'citron', 'pamplemousse'])) {
      return const FoodCategoryStyle(emoji: '🍊', tintColor: Color(0xFFFB923C));
    }
    if (_hasPrefix(combined, ['raisin'])) {
      return const FoodCategoryStyle(emoji: '🍇', tintColor: Color(0xFFA78BFA));
    }
    if (_hasPrefix(combined, ['mangue'])) {
      return const FoodCategoryStyle(emoji: '🥭', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['ananas'])) {
      return const FoodCategoryStyle(emoji: '🍍', tintColor: Color(0xFFFACC15));
    }
    if (_hasPrefix(combined, ['peche', 'abricot', 'nectarine'])) {
      return const FoodCategoryStyle(emoji: '🍑', tintColor: Color(0xFFFB923C));
    }
    if (_hasPrefix(combined, ['cerise'])) {
      return const FoodCategoryStyle(emoji: '🍒', tintColor: Color(0xFFF43F5E));
    }
    if (_hasPrefix(combined, ['poire'])) {
      return const FoodCategoryStyle(emoji: '🍐', tintColor: Color(0xFF4ADE80));
    }
    if (_hasPrefix(combined, ['melon', 'pasteque'])) {
      return const FoodCategoryStyle(emoji: '🍉', tintColor: Color(0xFFF43F5E));
    }
    if (_hasPrefix(combined, ['pomme', 'compote', 'fruit'])) {
      return const FoodCategoryStyle(emoji: '🍎', tintColor: Color(0xFFF43F5E));
    }

    // 18. Chocolate, Biscuits & Sweets
    if (_hasPrefix(combined, ['chocolat', 'cacao'])) {
      return const FoodCategoryStyle(emoji: '🍫', tintColor: Color(0xFFEC4899));
    }
    if (_hasPrefix(combined, [
      'cookie',
      'biscuit',
      'figolu',
      'oreo',
      'speculoos',
      'petit beurre',
      'sable',
    ]) || _hasWord(combined, ['bn'])) {
      return const FoodCategoryStyle(emoji: '🍪', tintColor: Color(0xFFEC4899));
    }
    if (_hasPrefix(combined, [
      'gateau',
      'brownie',
      'muffin',
      'madeleine',
      'financier',
      'fondant',
      'cake',
      'tarte',
      'eclair',
    ])) {
      return const FoodCategoryStyle(emoji: '🧁', tintColor: Color(0xFFEC4899));
    }
    if (_hasPrefix(combined, ['glace', 'sorbet', 'magnum'])) {
      return const FoodCategoryStyle(emoji: '🍨', tintColor: Color(0xFFEC4899));
    }
    if (_hasPrefix(combined, ['miel', 'confiture', 'sirop'])) {
      return const FoodCategoryStyle(emoji: '🍯', tintColor: Color(0xFFF59E0B));
    }
    if (_hasPrefix(combined, ['bonbon', 'confiserie', 'sucre', 'caramel'])) {
      return const FoodCategoryStyle(emoji: '🍬', tintColor: Color(0xFFEC4899));
    }

    // 19. Nuts & Seeds
    if (_hasPrefix(combined, [
      'amande',
      'noisette',
      'cacahuete',
      'pistache',
      'cajou',
      'graine',
      'chia',
      'sesame',
      'pecan',
      'macadamia',
    ]) || _hasWord(combined, ['noix', 'lin'])) {
      return const FoodCategoryStyle(emoji: '🥜', tintColor: Color(0xFFB45309));
    }

    // 20. Pure salt, pepper & spices (evaluated after all food categories so
    // 'chocolat pointe de sel', 'beurre demi-sel', or 'steak au poivre' never match)
    final isPureSaltOrPepper = normName == 'sel' ||
        normName.startsWith('sel ') ||
        normName.startsWith('fleur de sel') ||
        normName.startsWith('gros sel') ||
        normName == 'poivre' ||
        normName.startsWith('poivre ');
    if (isPureSaltOrPepper ||
        _hasPrefix(combined, ['epice', 'curry', 'paprika', 'cumin'])) {
      return const FoodCategoryStyle(emoji: '🥫', tintColor: Color(0xFFF97316));
    }

    // 21. Fallback
    return const FoodCategoryStyle(
      emoji: null,
      tintColor: AppColors.calories,
    );
  }
}

class FoodCategoryAvatar extends StatelessWidget {
  const FoodCategoryAvatar({
    super.key,
    required this.name,
    this.source,
    this.category,
    this.size = 38,
    this.borderRadius = 10,
  });

  final String name;
  final String? source;
  final String? category;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final style = FoodCategoryResolver.resolve(
      name: name,
      source: source,
      category: category,
    );

    final hasEmoji = style.emoji != null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasEmoji
            ? style.tintColor.withValues(alpha: 0.14)
            : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(borderRadius),
        border: hasEmoji
            ? Border.all(
                color: style.tintColor.withValues(alpha: 0.25),
                width: 0.8,
              )
            : null,
      ),
      child: hasEmoji
          ? Text(
              style.emoji!,
              style: TextStyle(
                fontSize: size * 0.52,
                height: 1.0,
              ),
            )
          : Icon(
              Icons.restaurant,
              size: size * 0.46,
              color: AppColors.calories,
            ),
    );
  }
}

/// Formats the discrete brand / store / source meta subtitle shown under food names
/// in the daily Journal and its edit sheet, deduplicating brand if already in [name].
String? buildJournalFoodMetaSubtitle({
  required String name,
  String? brand,
  String? stores,
  String? source,
  String? recipePortionHint,
}) {
  if (source == 'recipe') {
    if (recipePortionHint != null && recipePortionHint.isNotEmpty) {
      return 'Recette · $recipePortionHint';
    }
    return 'Recette';
  }

  final parts = <String>[];
  final normName = FoodCategoryResolver.normalize(name);

  if (brand != null && brand.trim().isNotEmpty) {
    final cleanBrand = brand.trim();
    final normBrand = FoodCategoryResolver.normalize(cleanBrand);
    if (normBrand.isNotEmpty && !normName.contains(normBrand)) {
      parts.add(cleanBrand);
    }
  }

  if (stores != null && stores.trim().isNotEmpty) {
    final storeList = stores
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (storeList.isNotEmpty) {
      final limited = storeList.take(2).join(', ');
      final normStore = FoodCategoryResolver.normalize(limited);
      final alreadyIncluded = parts.any(
        (p) => FoodCategoryResolver.normalize(p) == normStore,
      );
      if (!alreadyIncluded && !normName.contains(normStore)) {
        parts.add(limited);
      }
    }
  }

  if (parts.isNotEmpty) {
    return parts.join(' · ');
  }

  if (source == 'ciqual') {
    return 'Ciqual';
  }

  return null;
}
