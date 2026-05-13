import 'dart:convert';
import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

import 'action_interface.dart';
import '../utils/local_loader.dart';

/// Unused Action -- Used for detecting and clearing the unused i18n assets
class UnusedAction extends AbstractAction {
  // ---------------------------------------------------------------------------
  // Test hooks — expose internal state so tests can assert results
  // ---------------------------------------------------------------------------

  Set<String> get testUsedKeys => _usedKeys.keys.toSet();
  Set<String> get testUsedPluralStems => _usedPluralStems.toSet();
  List<UnresolvedRef> get testUncheckable => List.unmodifiable(_uncheckable);
  Set<String> get testUnusedKeys => _lastUnusedKeys;
  Map<String, Set<String>> get testMissingKeys => _lastMissingKeys;

  // ---------------------------------------------------------------------------
  // Private state
  // ---------------------------------------------------------------------------
  @override
  List<String> get acceptedExtensions => ['.json', '.yaml', '.xml', '.toml'];

  bool _autoClear = false;
  bool _verbose = false;
  final _assetPaths = <String>[];
  final _codePaths = <String>[];

  // key → file paths where this key is referenced
  final _usedKeys = <String, Set<String>>{};
  final _usedPluralStems = <String>{};
  final _uncheckable = <UnresolvedRef>[];
  final _constMap = <String, String>{};
  // filePath -> {parentDir -> isNamespace}
  final _namespaceForFile = <String, String?>{};

  Set<String> _lastUnusedKeys = {};
  Map<String, Set<String>> _lastMissingKeys = {};

  @override
  void executeAction(final List<String> params) async {
    _parseArgs(params);

    // Use --asset paths if provided, otherwise scan pubspec.yaml
    final List<FileSystemEntity> assetsContent;
    if (_assetPaths.isNotEmpty) {
      assetsContent = _assetPaths.expand((p) => _collectAssetFiles(p)).toList();
    } else {
      assetsContent = await retrieveAssetsContent();
    }

    if (assetsContent.isEmpty) {
      MessagePrinter.error('No translation files found.');
      return;
    }

    MessagePrinter.info(
        'Found ${assetsContent.length} translation file(s).');

    final definedKeys = await _collectDefinedKeys(assetsContent);

    // Use --code paths if provided, otherwise scan lib/
    final List<File> dartFiles;
    if (_codePaths.isNotEmpty) {
      dartFiles = _codePaths.expand((p) => _collectCodeFiles(p)).toList();
    } else {
      dartFiles = _collectDartFiles();
    }

    MessagePrinter.info('Scanning ${dartFiles.length} Dart file(s).');

    for (final dartFile in dartFiles) {
      await _scanDartFile(dartFile);
    }

    _lastUnusedKeys = _computeUnused(definedKeys);
    _lastMissingKeys = _computeMissing(definedKeys);
    _report(_lastUnusedKeys, definedKeys);

    if (_autoClear && _lastUnusedKeys.isNotEmpty) {
      await _autoClearFiles(assetsContent, _lastUnusedKeys);
    }
  }

  // ---------------------------------------------------------------------------
  // CLI args
  // ---------------------------------------------------------------------------

  void _parseArgs(final List<String> params) {
    for (final arg in params) {
      if (arg == '--auto-clear') {
        _autoClear = true;
      } else if (arg == '--verbose') {
        _verbose = true;
      } else if (arg.startsWith('--asset=')) {
        _assetPaths.add(arg.substring('--asset='.length));
      } else if (arg.startsWith('--code=')) {
        _codePaths.add(arg.substring('--code='.length));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 1 – collect defined keys
  // ---------------------------------------------------------------------------

  Future<Map<String, Set<String>>> _collectDefinedKeys(
      final List<FileSystemEntity> assetsContent) async {
    final result = <String, Set<String>>{};

    for (final entity in assetsContent) {
      final file = entity is File ? entity : File(entity.path);
      final map = await LocalLoader(file).loadContent();
      if (map == null || map.isEmpty) {
        MessagePrinter.error('Failed to decode ${file.path}');
        continue;
      }

      final namespace = _detectNamespace(file.path);
      _namespaceForFile[file.path] = namespace;

      final keys = <String>{};
      _flattenMap(map, namespace, '', keys);

      if (_verbose) {
        MessagePrinter.info('${file.path} → ${keys.length} key(s)');
      }
      result[file.path] = keys;
    }

    return result;
  }

  /// Returns the namespace name if this file uses namespace layout, else null.
  String? _detectNamespace(final String filePath) {
    final parentDirName = File(filePath).parent.path.split(RegExp(r'[/\\]')).last;
    // Locale codes are 2-3 lowercase letters
    if (RegExp(r'^[a-z]{2,3}$').hasMatch(parentDirName)) {
      return _basenameWithoutExtension(filePath);
    }
    return null;
  }

  void _flattenMap(final Map<dynamic, dynamic> map, final String? namespace,
      final String prefix, final Set<String> out) {
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      final value = entry.value;

      if (value is Map) {
        _flattenMap(value, namespace, fullKey, out);
      } else if (value is String) {
        final finalKey = namespace != null ? '$namespace.$fullKey' : fullKey;
        out.add(finalKey);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // File collection helpers
  // ---------------------------------------------------------------------------

  /// Collect translation files from a path (directory or single file).
  List<FileSystemEntity> _collectAssetFiles(final String path) {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.file) {
      final ext = path.split('.').last;
      if (!acceptedExtensions.contains('.$ext')) {
        MessagePrinter.error('Unsupported translation file format: $path');
        return [];
      }
      return [File(path)];
    }
    if (entity == FileSystemEntityType.directory) {
      return Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => acceptedExtensions
              .any((ext) => f.path.endsWith(ext)))
          .toList();
    }
    MessagePrinter.error('Asset path not found: $path');
    return [];
  }

  /// Collect Dart source files from a path (directory or single file).
  List<File> _collectCodeFiles(final String path) {
    final entity = FileSystemEntity.typeSync(path);
    if (entity == FileSystemEntityType.file) {
      if (!path.endsWith('.dart')) {
        MessagePrinter.error('Not a Dart file: $path');
        return [];
      }
      return [File(path)];
    }
    if (entity == FileSystemEntityType.directory) {
      return Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }
    MessagePrinter.error('Code path not found: $path');
    return [];
  }

  // ---------------------------------------------------------------------------
  // Phase 2 – scan Dart source files
  // ---------------------------------------------------------------------------

  List<File> _collectDartFiles() {
    final libDir = Directory('lib');
    if (!libDir.existsSync()) return [];
    return libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  Future<void> _scanDartFile(final File file) async {
    final content = await file.readAsString();

    final importInfo = _parseImport(content, file.path);
    if (importInfo == null) {
      if (_verbose) {
        MessagePrinter.debug('${file.path} — no flutter_i18n import, skipped');
      }
      return;
    }

    // Collect local constants for same-file resolution
    _collectConstDeclarations(content);

    final alias = importInfo.alias;

    // Match translation calls
    _matchTranslate(content, alias, file.path);
    _matchPlural(content, alias, file.path);
    _matchI18nText(content, alias, file.path);
    _matchI18nPlural(content, alias, file.path);
    _matchFallbackKey(content, file.path);
  }

  // ---------------------------------------------------------------------------
  // Import parsing
  // ---------------------------------------------------------------------------

  _ImportInfo? _parseImport(final String content, final String filePath) {
    final importRe = RegExp(
        r"""import\s+['"]package:flutter_i18n/flutter_i18n\.dart['"]"""
        r'(?:\s+as\s+(\w+))?'
        r'(?:\s+(?:show|hide)\s+([^;]+?))?'
        r'\s*;');
    final match = importRe.firstMatch(content);
    if (match == null) return null;

    final alias = match.group(1);
    final shownRaw = match.group(2);
    final shown = shownRaw != null
        ? shownRaw.split(',').map((s) => s.trim()).toSet()
        : <String>{};

    return _ImportInfo(alias: alias, shownNames: shown);
  }

  // ---------------------------------------------------------------------------
  // Local constant collection
  // ---------------------------------------------------------------------------

  void _collectConstDeclarations(final String content) {
    // top-level const/final String or static const/final String inside a class
    final re = RegExp(
        "(?:static\\s+)?(?:const|final)\\s+String\\s+(\\w+)\\s*=\\s*['\"]([^'\"]+)['\"]");
    for (final match in re.allMatches(content)) {
      _constMap[match.group(1)!] = match.group(2)!;
    }
  }

  // ---------------------------------------------------------------------------
  // Match translation calls
  // ---------------------------------------------------------------------------

  void _matchTranslate(final String content, final String? alias,
      final String filePath) {
    final prefix = alias != null ? '$alias\\.' : '';
    final re = RegExp('${prefix}FlutterI18n\\.translate\\s*\\(\\s*[^,]+,\\s*');
    for (final match in re.allMatches(content)) {
      final start = match.end;
      final arg = _extractStringArg(content, start);
      if (arg != null) {
        _addUsed(arg, filePath);
      } else {
        _addUncheckable(content, start, filePath);
      }
    }
  }

  void _matchPlural(final String content, final String? alias,
      final String filePath) {
    final prefix = alias != null ? '$alias\\.' : '';
    final re = RegExp('${prefix}FlutterI18n\\.plural\\s*\\(\\s*[^,]+,\\s*');
    for (final match in re.allMatches(content)) {
      final start = match.end;
      final arg = _extractStringArg(content, start);
      if (arg != null) {
        _usedPluralStems.add(arg);
        if (_verbose) {
          MessagePrinter.info('[plural stem] $arg  ← $filePath');
        }
      } else {
        _addUncheckable(content, start, filePath);
      }
    }
  }

  void _matchI18nText(final String content, final String? alias,
      final String filePath) {
    final prefix = alias != null ? '$alias\\.' : '';
    final re = RegExp('${prefix}I18nText\\s*\\(\\s*');
    for (final match in re.allMatches(content)) {
      final start = match.end;
      final arg = _extractStringArg(content, start);
      if (arg != null) {
        _addUsed(arg, filePath);
      } else {
        _addUncheckable(content, start, filePath);
      }
    }
  }

  void _matchI18nPlural(final String content, final String? alias,
      final String filePath) {
    final prefix = alias != null ? '$alias\\.' : '';
    final re = RegExp('${prefix}I18nPlural\\s*\\(\\s*');
    for (final match in re.allMatches(content)) {
      final start = match.end;
      final arg = _extractStringArg(content, start);
      if (arg != null) {
        _usedPluralStems.add(arg);
        if (_verbose) {
          MessagePrinter.info('[plural stem] $arg  ← $filePath');
        }
      } else {
        _addUncheckable(content, start, filePath);
      }
    }
  }

  void _matchFallbackKey(final String content, final String filePath) {
    final re = RegExp(
        'fallbackKey:\\s*\'([^\']+)\'|fallbackKey:\\s*"([^"]+)"');
    for (final match in re.allMatches(content)) {
      final key = match.group(1) ?? match.group(2)!;
      _addUsed(key, filePath);
    }
  }

  // ---------------------------------------------------------------------------
  // Argument extraction
  // ---------------------------------------------------------------------------

  /// Try to extract a string literal starting at [pos] in [content].
  /// Returns the string value, or null if the arg is a variable/expression
  /// or contains Dart interpolation syntax.
  String? _extractStringArg(final String content, final int pos) {
    final remaining = content.substring(pos);

    // Try single-quoted string (no interpolation in Dart single-quoted strings)
    var m = RegExp(r"^'([^'\\]*(?:\\.[^'\\]*)*)'").firstMatch(remaining);
    if (m != null) return m.group(1)!;

    // Try double-quoted string — only pure literals, no interpolation
    m = RegExp(r'^"([^"\\\$]*(?:\\.[^"\\]*)*)"').firstMatch(remaining);
    if (m != null) {
      final raw = m.group(1)!;
      // Contains interpolation syntax like $var or ${expr} → not usable
      if (RegExp(r'\$').hasMatch(raw)) return null;
      return raw;
    }

    // Might be a variable/identifier — try to resolve via const map
    m = RegExp(r'^(\w+)').firstMatch(remaining);
    if (m != null) {
      final varName = m.group(1)!;
      final resolved = _constMap[varName];
      if (resolved != null) return resolved;

      // Check if it's a PrefixedIdentifier like ClassName.constantName
      final prefixedM = RegExp(r'^(\w+)\.(\w+)').firstMatch(remaining);
      if (prefixedM != null) {
        final fullName = '${prefixedM.group(1)}.${prefixedM.group(2)}';
        final resolved2 = _constMap[fullName] ?? _constMap[prefixedM.group(2)!];
        return resolved2;
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Tracking helpers
  // ---------------------------------------------------------------------------

  void _addUsed(final String key, final String filePath) {
    _usedKeys.putIfAbsent(key, () => <String>{}).add(filePath);
    if (_verbose) {
      MessagePrinter.info('[used] $key  ← $filePath');
    }
  }

  void _addUncheckable(final String content, final int pos,
      final String filePath) {
    final line = _lineNumber(content, pos);
    final snippet = content
        .substring(pos, (pos + 60).clamp(0, content.length))
        .replaceAll('\n', ' ')
        .trim();
    _uncheckable.add(UnresolvedRef(filePath, line, snippet));
    if (_verbose) {
      MessagePrinter.info('[uncheckable] $filePath:$line — $snippet');
    }
  }

  int _lineNumber(final String content, final int pos) {
    return '\n'.allMatches(content.substring(0, pos)).length + 1;
  }

  // ---------------------------------------------------------------------------
  // Phase 3 – diff
  // ---------------------------------------------------------------------------

  Set<String> _computeUnused(final Map<String, Set<String>> definedKeys) {
    // Start with all defined keys
    final allDefined = definedKeys.values.expand((s) => s).toSet();
    final unused = <String>{};

    for (final key in allDefined) {
      if (_usedKeys.containsKey(key)) continue;

      // Check plural stem coverage: key like "clicked.times-0" covered by stem "clicked.times"
      bool coveredByPlural = false;
      for (final stem in _usedPluralStems) {
        if (key == stem) {
          coveredByPlural = true;
          break;
        }
        if (key.startsWith('$stem-')) {
          final suffix = key.substring(stem.length + 1);
          if (int.tryParse(suffix) != null) {
            coveredByPlural = true;
            break;
          }
        }
      }
      if (!coveredByPlural) {
        unused.add(key);
      }
    }

    return unused;
  }

  /// Returns keys referenced in code but missing from translation files.
  Map<String, Set<String>> _computeMissing(
      final Map<String, Set<String>> definedKeys) {
    final allDefined = definedKeys.values.expand((s) => s).toSet();
    final missing = <String, Set<String>>{};

    for (final entry in _usedKeys.entries) {
      final key = entry.key;
      if (!allDefined.contains(key)) {
        // Also check if covered by a plural stem that exists in defined
        var covered = false;
        for (final stem in _usedPluralStems) {
          if (key == stem || key.startsWith('$stem-')) {
            if (allDefined.any((d) => d == key || d.startsWith('$stem-'))) {
              covered = true;
              break;
            }
          }
        }
        if (!covered) {
          missing[key] = entry.value;
        }
      }
    }

    return missing;
  }

  // ---------------------------------------------------------------------------
  // Report
  // ---------------------------------------------------------------------------

  void _report(final Set<String> unusedKeys,
      final Map<String, Set<String>> definedKeys) {
    final allDefined = definedKeys.values.expand((s) => s).length;
    final totalUsed = _usedKeys.length;
    final totalDefined = allDefined;

    if (unusedKeys.isEmpty && _lastMissingKeys.isEmpty && _uncheckable.isEmpty) {
      MessagePrinter.info(
          'All $totalDefined key(s) are used. No unused keys found.');
      return;
    }

    if (_lastMissingKeys.isNotEmpty) {
      final header =
          '\n--- Missing Translation Keys (${_lastMissingKeys.length}) ---';
      MessagePrinter.info(header);
      for (final entry in _lastMissingKeys.entries) {
        for (final file in entry.value) {
          MessagePrinter.info('  ${entry.key}  ← $file');
        }
      }
    }

    if (unusedKeys.isNotEmpty) {
      final unusedByFile = <String, Set<String>>{};
      for (final entry in definedKeys.entries) {
        final fileUnused = entry.value.intersection(unusedKeys);
        if (fileUnused.isNotEmpty) {
          unusedByFile[entry.key] = fileUnused;
        }
      }

      final header = '\n--- Unused Translation Keys (${unusedKeys.length}) ---';
      MessagePrinter.info(header);
      for (final entry in unusedByFile.entries) {
        for (final key in entry.value) {
          MessagePrinter.info('  $key  ← ${entry.key}');
        }
      }
    }

    if (_uncheckable.isNotEmpty) {
      MessagePrinter.info(
          '\n--- Unresolvable References (${_uncheckable.length}) ---');
      for (final ref in _uncheckable) {
        MessagePrinter.info(
            '  ${ref.filePath}:${ref.line}  ${ref.snippet}');
      }
    }

    MessagePrinter.info('\n--- Summary ---');
    MessagePrinter.info('  Defined:     $totalDefined');
    MessagePrinter.info('  Used:        $totalUsed');
    MessagePrinter.info('  Unused:      ${unusedKeys.length}');
    MessagePrinter.info('  Missing:     ${_lastMissingKeys.length}');
    MessagePrinter
        .info('  Uncheckable: ${_uncheckable.length}');
  }

  // ---------------------------------------------------------------------------
  // Phase 4 – auto-clear
  // ---------------------------------------------------------------------------

  Future<void> _autoClearFiles(final List<FileSystemEntity> assetsContent,
      final Set<String> unusedKeys) async {
    MessagePrinter.info('\nAuto-clearing unused keys...');

    for (final entity in assetsContent) {
      final file = entity is File ? entity : File(entity.path);
      // Find which unused keys belong to this file
      final keysForFile = <String>{};
      for (final key in unusedKeys) {
        // Determine if this key is from this file by checking namespace
        final namespace = _namespaceForFile[file.path];
        if (namespace != null) {
          if (key.startsWith('$namespace.')) {
            keysForFile.add(key.substring(namespace.length + 1));
          }
        } else {
          keysForFile.add(key);
        }
      }

      // More precise: check against the actual defined keys for this file
      // Re-decode to get the map
      final map = await LocalLoader(file).loadContent();
      if (map == null || map.isEmpty) continue;

      // Find which keys in this file are unused
      final namespace = _namespaceForFile[file.path];
      final definedInFile = <String>{};
      _flattenMap(map, namespace, '', definedInFile);
      final toDelete = definedInFile.intersection(unusedKeys);

      if (toDelete.isEmpty) continue;

      MessagePrinter.info('  ${file.path}: removing ${toDelete.length} key(s)');

      final ext = file.path.split('.').last.toLowerCase();
      switch (ext) {
        case 'json':
          _clearJson(file, toDelete, namespace);
          break;
        case 'yaml':
          _clearYaml(file, toDelete, namespace);
          break;
        case 'xml':
          _clearXml(file, toDelete, namespace);
          break;
        case 'toml':
          _clearToml(file, toDelete, namespace);
          break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // JSON round-trip
  // ---------------------------------------------------------------------------

  void _clearJson(final File file, final Set<String> keys,
      final String? namespace) async {
    final content = await file.readAsString();
    final map = json.decode(content) as Map<String, dynamic>;
    for (final key in keys) {
      _deleteFromMap(map, key.split('.'));
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(map)}\n');
  }

  void _deleteFromMap(final Map<dynamic, dynamic> map,
      final List<String> pathParts) {
    if (pathParts.isEmpty) return;
    var current = map;
    for (var i = 0; i < pathParts.length - 1; i++) {
      final next = current[pathParts[i]];
      if (next is Map) {
        current = next;
      } else {
        return;
      }
    }
    current.remove(pathParts.last);
  }

  // ---------------------------------------------------------------------------
  // YAML line-based deletion
  // ---------------------------------------------------------------------------

  void _clearYaml(final File file, final Set<String> keys,
      final String? namespace) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    for (final key in keys) {
      final parts = key.split('.');
      _findYamlLine(lines, parts, toRemove);
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!toRemove.contains(i)) {
        remaining.add(lines[i]);
      }
    }
    await file.writeAsString('${remaining.join('\n')}\n');

    // Warn about potentially empty parents
    _warnEmptyParentsYaml(lines, toRemove, file.path);
  }

  void _findYamlLine(final List<String> lines, final List<String> keyParts,
      final Set<int> toRemove) {
    if (keyParts.isEmpty) return;

    // Walk lines tracking indent levels to find the key path
    var depth = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().isEmpty || line.trimLeft().startsWith('#')) continue;

      final indent = line.length - line.trimLeft().length;
      final trimmed = line.trimLeft();

      if (depth > keyParts.length) return; // went too deep

      if (depth < keyParts.length && trimmed.startsWith('${keyParts[depth]}:')) {
        depth++;
        if (depth == keyParts.length) {
          toRemove.add(i);
          return;
        }
        continue;
      }

      // If indent is less than expected depth for this level, we've moved past
      // the parent without finding the key
      final expectedMinIndent = depth * 2;
      if (indent < expectedMinIndent && depth > 0) {
        return; // key not found in this section
      }
    }
  }

  void _warnEmptyParentsYaml(final List<String> originalLines,
      final Set<int> removed, final String filePath) {
    // Simple check: for each removed line, look at parent lines
    // This is a heuristic; full analysis would require YAML re-parsing
    for (final idx in removed) {
      final line = originalLines[idx].trimLeft();
      final keyName = line.split(':')[0];
      // Just note it — actual empty parent detection is best done manually
      MessagePrinter.debug(
          '$filePath: removed key "$keyName", verify parent keys manually');
    }
  }

  // ---------------------------------------------------------------------------
  // XML line-based deletion
  // ---------------------------------------------------------------------------

  void _clearXml(final File file, final Set<String> keys,
      final String? namespace) async {
    var content = await file.readAsString();

    for (final key in keys) {
      final parts = key.split('.');
      final leafKey = parts.last;
      // Remove self-closing elements: <leafKey ... />
      content = content.replaceAll(RegExp('<${RegExp.escape(leafKey)}[^>]*/>'), '');
      // Remove opening + closing + content: <leafKey ...>...</leafKey>
      content = content.replaceAll(
          RegExp('<${RegExp.escape(leafKey)}[^>]*>[^<]*</${RegExp.escape(leafKey)}>'),
          '');
    }

    await file.writeAsString(content);
  }

  // ---------------------------------------------------------------------------
  // TOML line-based deletion
  // ---------------------------------------------------------------------------

  void _clearToml(final File file, final Set<String> keys,
      final String? namespace) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    for (final key in keys) {
      final parts = key.split('.');
      final leafKey = parts.last;
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('$leafKey ') || trimmed.startsWith('$leafKey=')) {
          toRemove.add(i);
        }
      }
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!toRemove.contains(i)) {
        remaining.add(lines[i]);
      }
    }
    await file.writeAsString('${remaining.join('\n')}\n');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _basenameWithoutExtension(final String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

class _ImportInfo {
  final String? alias;
  final Set<String> shownNames;
  _ImportInfo({this.alias, this.shownNames = const {}});
}

class UnresolvedRef {
  final String filePath;
  final int line;
  final String snippet;
  UnresolvedRef(this.filePath, this.line, this.snippet);
}
