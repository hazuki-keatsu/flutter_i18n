/// Structured result of an unused-key analysis.
class AnalysisResult {
  /// Keys found in translation files, grouped by file path.
  final Map<String, Set<String>> definedKeys;

  /// Keys referenced in code, with the files that reference them.
  final Map<String, Set<String>> usedKeys;

  /// Plural stems referenced in code (e.g. "clicked.times").
  final Set<String> usedPluralStems;

  /// References that could not be resolved statically.
  final List<UnresolvedRef> uncheckable;

  AnalysisResult({
    required this.definedKeys,
    required this.usedKeys,
    required this.usedPluralStems,
    required this.uncheckable,
  });

  /// definedKeys − usedKeys (accounting for plural stem coverage).
  Set<String> get unusedKeys {
    final allDefined = definedKeys.values.expand((s) => s).toSet();
    final unused = <String>{};

    for (final key in allDefined) {
      if (usedKeys.containsKey(key)) continue;
      if (_coveredByPluralStem(key)) continue;
      unused.add(key);
    }
    return unused;
  }

  /// usedKeys − definedKeys.
  Map<String, Set<String>> get missingKeys {
    final allDefined = definedKeys.values.expand((s) => s).toSet();
    final missing = <String, Set<String>>{};

    for (final entry in usedKeys.entries) {
      final key = entry.key;
      if (!allDefined.contains(key) && !_coveredByPluralStem(key)) {
        missing[key] = entry.value;
      }
    }
    return missing;
  }

  bool _coveredByPluralStem(final String key) {
    for (final stem in usedPluralStems) {
      if (key == stem) return true;
      if (key.startsWith('$stem-')) {
        final suffix = key.substring(stem.length + 1);
        if (int.tryParse(suffix) != null) return true;
      }
    }
    return false;
  }

  int get totalDefined => definedKeys.values.expand((s) => s).length;
  int get totalUsed => usedKeys.length;
}

/// A reference to a translation key that could not be resolved statically.
class UnresolvedRef {
  final String filePath;
  final int line;
  final String snippet;
  const UnresolvedRef(this.filePath, this.line, this.snippet);
}
