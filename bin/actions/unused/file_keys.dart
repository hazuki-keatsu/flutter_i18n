/// Keys found in a single translation file, together with optional namespace.
///
/// Namespace-mode files (e.g. `en/common.json`) use the filename as a prefix:
/// the raw key `appName` becomes the full key `common.appName`. The [fullKeys]
/// set is what gets matched against code references; [rawKeys] is what the
/// file actually contains and what the cleaner operates on.
class FileKeys {
  final String filePath;
  final String? namespace;
  final Set<String> fullKeys;

  FileKeys(this.filePath, this.namespace, this.fullKeys);

  /// Keys as they appear in the translation file (namespace prefix stripped).
  Set<String> get rawKeys {
    if (namespace == null) return fullKeys;
    final prefix = '$namespace.';
    return fullKeys
        .map((k) => k.startsWith(prefix) ? k.substring(prefix.length) : k)
        .toSet();
  }
}
