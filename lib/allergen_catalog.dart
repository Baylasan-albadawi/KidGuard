/// Bitmask catalog aligned with the KidGuard canteen POS (HTML menu) allergen names.
///
/// Same label order must be preserved so stored `allergenMask` values stay stable across
/// the Flutter parent app and the POS website.
library;

/// Index i → bit (1 << i). Used for Realtime Database fields `allergenMask`.
/// Covers all 14 major allergens under EU Regulation 1169/2011.
const List<String> kAllergenCanonicalOrder = [
  'Peanuts',
  'Tree Nuts',
  'Milk',
  'Eggs',
  'Wheat',
  'Soy',
  'Fish',
  'Shellfish',
  'Sesame',
  'Celery',
  'Mustard',
  'Lupin',
  'Mollusks',
  'Sulphites',
];

String _normKey(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Map common aliases / variants to canonical names (after normalization).
final Map<String, String> _aliasToCanonical = {
  for (final a in kAllergenCanonicalOrder) _normKey(a): a,
  'peanut': 'Peanuts',
  'tree nut': 'Tree Nuts',
  'nuts': 'Tree Nuts',
  'dairy': 'Milk',
  'egg': 'Eggs',
  'gluten': 'Wheat',
  'soya': 'Soy',
  'crustacean': 'Shellfish',
  'crustaceans': 'Shellfish',
  'mollusc': 'Mollusks',
  'molluscs': 'Mollusks',
  'sulfites': 'Sulphites',
  'sulfite': 'Sulphites',
  'celeric': 'Celery',
  'lupine': 'Lupin',
};

String? _canonicalizeLabel(String raw) {
  final n = _normKey(raw);
  if (n.isEmpty) return null;
  if (_aliasToCanonical.containsKey(n)) return _aliasToCanonical[n];
  for (final c in kAllergenCanonicalOrder) {
    if (_normKey(c) == n) return c;
  }
  // Title Case fallback for unknown new allergens (bit not assigned)
  return null;
}

class AllergenCatalog {
  AllergenCatalog._();

  /// OR together bits for each recognized allergen label.
  static int maskFromLabels(Iterable<String> labels) {
    var m = 0;
    for (final raw in labels) {
      final c = _canonicalizeLabel(raw);
      if (c == null) continue;
      final idx = kAllergenCanonicalOrder.indexOf(c);
      if (idx < 0) continue;
      m |= 1 << idx;
    }
    return m;
  }

  static List<String> labelsFromMask(int mask) {
    final out = <String>[];
    for (var i = 0; i < kAllergenCanonicalOrder.length; i++) {
      if ((mask & (1 << i)) != 0) {
        out.add(kAllergenCanonicalOrder[i]);
      }
    }
    return out;
  }

  /// True if student and food share any allergenic component (same as HTML intersection logic).
  static bool intersectsLists(
      List<String> childAllergens, List<String> foodAllergens) {
    final ca = childAllergens.map(_normKey).where((s) => s.isNotEmpty).toSet();
    final fa = foodAllergens.map(_normKey).where((s) => s.isNotEmpty).toSet();
    return ca.intersection(fa).isNotEmpty;
  }

  static bool bitmaskConflicts({
    required int childMask,
    required int productMask,
  }) =>
      childMask != 0 && productMask != 0 && (childMask & productMask) != 0;

  /// Labels that matched between child allergens and known product labels (human-readable blocking line).
  static List<String> matchingLabels(
      List<String> childAllergens, List<String> foodAllergens) {
    final matches = <String>[];
    for (final pa in foodAllergens) {
      final c = _canonicalizeLabel(pa) ?? pa;
      for (final cb in childAllergens) {
        final cc = _canonicalizeLabel(cb) ?? cb;
        if (_normKey(c) == _normKey(cc)) {
          matches.add(c);
          break;
        }
      }
    }
    return matches;
  }
}
