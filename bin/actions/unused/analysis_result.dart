import 'file_keys.dart';

/// Structured result of an unused-key analysis.
class AnalysisResult {
  /// Keys found in translation files, grouped by file path.
  final Map<String, FileKeys> definedKeys;

  /// Keys referenced in code, with the files that reference them.
  final Map<String, Set<String>> usedKeys;

  /// Plural stems referenced in code (e.g. "clicked.times").
  final Set<String> usedPluralStems;

  /// References that could not be resolved statically.
  final List<UnresolvedRef> uncheckable;

  /// definedKeys − usedKeys (accounting for plural stem coverage).
  final Set<String> unusedKeys;

  /// usedKeys − definedKeys.
  final Map<String, Set<String>> missingKeys;

  final int totalDefined;
  final int totalUsed;

  AnalysisResult({
    required this.definedKeys,
    required this.usedKeys,
    required this.usedPluralStems,
    required this.uncheckable,
  })  : unusedKeys = _computeUnused(definedKeys, usedKeys, usedPluralStems),
        missingKeys = _computeMissing(definedKeys, usedKeys, usedPluralStems),
        totalDefined = definedKeys.values.expand((fk) => fk.fullKeys).length,
        totalUsed = usedKeys.length;

  static Set<String> _computeUnused(
      final Map<String, FileKeys> definedKeys,
      final Map<String, Set<String>> usedKeys,
      final Set<String> usedPluralStems) {
    final allDefined = definedKeys.values.expand((fk) => fk.fullKeys).toSet();
    final unused = <String>{};

    for (final key in allDefined) {
      if (usedKeys.containsKey(key)) continue;
      if (_coveredByPluralStem(key, usedPluralStems)) continue;
      unused.add(key);
    }
    return unused;
  }

  static Map<String, Set<String>> _computeMissing(
      final Map<String, FileKeys> definedKeys,
      final Map<String, Set<String>> usedKeys,
      final Set<String> usedPluralStems) {
    final allDefined = definedKeys.values.expand((fk) => fk.fullKeys).toSet();
    final missing = <String, Set<String>>{};

    for (final entry in usedKeys.entries) {
      final key = entry.key;
      if (!allDefined.contains(key) && !_coveredByPluralStem(key, usedPluralStems)) {
        missing[key] = entry.value;
      }
    }
    return missing;
  }

  static bool _coveredByPluralStem(final String key, final Set<String> stems) {
    for (final stem in stems) {
      if (key == stem) return true;
      if (key.startsWith('$stem-')) {
        final suffix = key.substring(stem.length + 1);
        if (int.tryParse(suffix) != null) return true;
      }
    }
    return false;
  }
}

/// A reference to a translation key that could not be resolved statically.
class UnresolvedRef {
  final String filePath;
  final int line;
  final String snippet;
  const UnresolvedRef(this.filePath, this.line, this.snippet);
}
