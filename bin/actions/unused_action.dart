import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

import 'action_interface.dart';
import '../utils/local_loader.dart';
import 'unused/analysis_result.dart';
import 'unused/translation_cleaner.dart';

/// Scans translation assets and Dart source files to find unused / missing keys.
class UnusedAction extends AbstractAction {
  @override
  List<String> get acceptedExtensions => ['.json', '.yaml', '.xml', '.toml'];

  bool _autoClear = false;
  bool _verbose = false;
  final _assetPaths = <String>[];
  final _codePaths = <String>[];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// CLI entry point (fire-and-forget, matches [AbstractAction] contract).
  @override
  void executeAction(final List<String> params) {
    analyze(params); // microtask-driven; process won't exit until it completes
  }

  /// Returns a structured result for programmatic use (tests, tooling).
  Future<AnalysisResult> analyze(final List<String> params) async {
    _parseArgs(params);

    final assetsContent = await _resolveAssetPaths();
    if (assetsContent.isEmpty) {
      MessagePrinter.error('No translation files found.');
      return AnalysisResult(
          definedKeys: const {},
          usedKeys: const {},
          usedPluralStems: const {},
          uncheckable: const []);
    }
    MessagePrinter.info('Found ${assetsContent.length} translation file(s).');

    final definedKeys = await _collectDefinedKeys(assetsContent);

    final dartFiles = _resolveCodePaths();
    MessagePrinter.info('Scanning ${dartFiles.length} Dart file(s).');

    final scanResult = await _scanAll(dartFiles);
    final result = AnalysisResult(
      definedKeys: definedKeys,
      usedKeys: scanResult.usedKeys,
      usedPluralStems: scanResult.pluralStems,
      uncheckable: scanResult.uncheckable,
    );

    _report(result);

    if (_autoClear && result.unusedKeys.isNotEmpty) {
      await _clear(assetsContent, definedKeys, result.unusedKeys);
    }

    return result;
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
  // Path resolution
  // ---------------------------------------------------------------------------

  Future<List<FileSystemEntity>> _resolveAssetPaths() async {
    if (_assetPaths.isNotEmpty) {
      return _assetPaths.expand(_collectAssetFiles).toList();
    }
    final pubspecAssets = await retrieveAssetsFolders();
    return pubspecAssets.expand(_collectAssetFiles).toList();
  }

  List<File> _resolveCodePaths() {
    if (_codePaths.isNotEmpty) {
      return _codePaths.expand(_collectCodeFiles).toList();
    }
    return _collectDartFiles();
  }

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
          .where((f) => acceptedExtensions.any((ext) => f.path.endsWith(ext)))
          .toList();
    }
    MessagePrinter.error('Asset path not found: $path');
    return [];
  }

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

  List<File> _collectDartFiles() {
    final libDir = Directory('lib');
    if (!libDir.existsSync()) return [];
    return libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Phase 1 — collect defined keys
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
      final keys = <String>{};
      _flattenMap(map, namespace, '', keys);

      if (_verbose) {
        MessagePrinter.info('${file.path} → ${keys.length} key(s)');
      }
      result[file.path] = keys;
    }

    return result;
  }

  String? _detectNamespace(final String filePath) {
    final parentDirName =
        File(filePath).parent.path.split(RegExp(r'[/\\]')).last;
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
  // Pre-compiled regex patterns
  // ---------------------------------------------------------------------------

  static final _importRe = RegExp(
      r"""import\s+['"]package:flutter_i18n/flutter_i18n\.dart['"]"""
      r'(?:\s+as\s+(\w+))?'
      r'(?:\s+(?:show|hide)\s+([^;]+?))?'
      r'\s*;');

  static final _constRe = RegExp(
      "(?:static\\s+)?(?:const|final)\\s+String\\s+(\\w+)\\s*=\\s*['\"]([^'\"]+)['\"]");

  static final _fallbackKeyRe = RegExp(
      "fallbackKey:\\s*'([^']+)'|fallbackKey:\\s*\"([^\"]+)\"");

  static final _singleQuoteRe = RegExp(r"^'([^'\\]*(?:\\.[^'\\]*)*)'");
  static final _doubleQuoteRe = RegExp(r'^"([^"\\\$]*(?:\\.[^"\\]*)*)"');
  static final _identRe = RegExp(r'^(\w+)');
  static final _prefixedIdentRe = RegExp(r'^(\w+)\.(\w+)');
  static final _interpolationCheckRe = RegExp(r'\$');

  // ---------------------------------------------------------------------------
  // Phase 2 — scan Dart source files
  // ---------------------------------------------------------------------------

  Future<_ScanResult> _scanAll(final List<File> files) async {
    final usedKeys = <String, Set<String>>{};
    final pluralStems = <String>{};
    final uncheckable = <UnresolvedRef>[];

    for (final file in files) {
      final content = await file.readAsString();

      final importInfo = _parseImport(content);
      if (importInfo == null) {
        if (_verbose) {
          MessagePrinter
              .debug('${file.path} — no flutter_i18n import, skipped');
        }
        continue;
      }

      // Per-file const map — no cross-file leakage
      final constMap = _collectConstDeclarations(content);

      final path = file.path;
      final alias = importInfo.alias;

      // translate → 2nd arg → usedKeys
      _matchCall(content, alias != null ? '$alias.FlutterI18n.translate' : 'FlutterI18n.translate',
          path, skipFirst: true, usedKeys: usedKeys, uncheckable: uncheckable, constMap: constMap);
      // plural → 2nd arg → pluralStems
      _matchCall(content, alias != null ? '$alias.FlutterI18n.plural' : 'FlutterI18n.plural',
          path, skipFirst: true, pluralStems: pluralStems, uncheckable: uncheckable, constMap: constMap);
      // I18nText → 1st arg → usedKeys
      _matchCall(content, alias != null ? '$alias.I18nText' : 'I18nText',
          path, skipFirst: false, usedKeys: usedKeys, uncheckable: uncheckable, constMap: constMap);
      // I18nPlural → 1st arg → pluralStems
      _matchCall(content, alias != null ? '$alias.I18nPlural' : 'I18nPlural',
          path, skipFirst: false, pluralStems: pluralStems, uncheckable: uncheckable, constMap: constMap);

      _matchFallbackKey(content, path, usedKeys);
    }

    return _ScanResult(usedKeys, pluralStems, uncheckable);
  }

  // ---------------------------------------------------------------------------
  // Import parsing
  // ---------------------------------------------------------------------------

  _ImportInfo? _parseImport(final String content) {
    final match = _importRe.firstMatch(content);
    if (match == null) return null;

    final alias = match.group(1);
    final shownRaw = match.group(2);
    final shown = shownRaw != null
        ? shownRaw.split(',').map((s) => s.trim()).toSet()
        : <String>{};

    return _ImportInfo(alias: alias, shownNames: shown);
  }

  Map<String, String> _collectConstDeclarations(final String content) {
    final map = <String, String>{};
    for (final match in _constRe.allMatches(content)) {
      map[match.group(1)!] = match.group(2)!;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Unified call-site matcher
  // ---------------------------------------------------------------------------

  /// Matches calls like `{target}(arg0, arg1, ...)` in [content].
  /// When [skipFirst] is true, the key is the second positional arg; otherwise
  /// the first. Results go to [usedKeys], [pluralStems], or [uncheckable].
  void _matchCall(
      final String content,
      final String target,
      final String filePath, {
      required final bool skipFirst,
      Map<String, Set<String>>? usedKeys,
      Set<String>? pluralStems,
      required final List<UnresolvedRef> uncheckable,
      required final Map<String, String> constMap,
      }) {
    final pattern = skipFirst
        ? '$target\\s*\\(\\s*[^,]+,\\s*'
        : '$target\\s*\\(\\s*';
    final re = RegExp(pattern);
    for (final match in re.allMatches(content)) {
      final start = match.end;
      final arg = _extractStringArg(content, start, constMap);
      if (arg != null) {
        if (usedKeys != null) {
          _addUsed(arg, filePath, usedKeys);
        } else if (pluralStems != null) {
          pluralStems.add(arg);
          if (_verbose) {
            MessagePrinter.info('[plural stem] $arg  ← $filePath');
          }
        }
      } else {
        _addUncheckable(content, start, filePath, uncheckable);
      }
    }
  }

  void _matchFallbackKey(final String content, final String filePath,
      final Map<String, Set<String>> usedKeys) {
    for (final match in _fallbackKeyRe.allMatches(content)) {
      final key = match.group(1) ?? match.group(2)!;
      _addUsed(key, filePath, usedKeys);
    }
  }

  // ---------------------------------------------------------------------------
  // Argument extraction
  // ---------------------------------------------------------------------------

  String? _extractStringArg(final String content, final int pos,
      final Map<String, String> constMap) {
    final remaining = content.substring(pos);

    // Single-quoted string
    var m = _singleQuoteRe.firstMatch(remaining);
    if (m != null) return m.group(1)!;

    // Double-quoted string — rejects interpolation
    m = _doubleQuoteRe.firstMatch(remaining);
    if (m != null) {
      final raw = m.group(1)!;
      if (_interpolationCheckRe.hasMatch(raw)) return null;
      return raw;
    }

    // Identifier — try const map
    m = _identRe.firstMatch(remaining);
    if (m != null) {
      final varName = m.group(1)!;
      final resolved = constMap[varName];
      if (resolved != null) return resolved;

      final prefixedM = _prefixedIdentRe.firstMatch(remaining);
      if (prefixedM != null) {
        final fullName = '${prefixedM.group(1)}.${prefixedM.group(2)}';
        return constMap[fullName] ?? constMap[prefixedM.group(2)!];
      }
    }

    return null;
  }

  void _addUsed(final String key, final String filePath,
      final Map<String, Set<String>> usedKeys) {
    usedKeys.putIfAbsent(key, () => <String>{}).add(filePath);
    if (_verbose) {
      MessagePrinter.info('[used] $key  ← $filePath');
    }
  }

  void _addUncheckable(final String content, final int pos,
      final String filePath, final List<UnresolvedRef> uncheckable) {
    final line = '\n'.allMatches(content.substring(0, pos)).length + 1;
    final snippet = _extractArgSnippet(content, pos);
    uncheckable.add(UnresolvedRef(filePath, line, snippet));
    if (_verbose) {
      MessagePrinter.info('[uncheckable] $filePath:$line — $snippet');
    }
  }

  /// Extract just the argument expression at [pos], for clean reporting.
  String _extractArgSnippet(final String content, final int pos) {
    final remaining = content.substring(pos);

    var m = RegExp(r'^"([^"]*)"').firstMatch(remaining);
    if (m != null) return '"${m.group(1)}"';

    m = RegExp(r"^'([^']*)'").firstMatch(remaining);
    if (m != null) return "'${m.group(1)}'";

    m = RegExp(r'^(\w+(?:\.\w+)*)').firstMatch(remaining);
    if (m != null) return m.group(1)!;

    final end = (pos + 30).clamp(0, content.length);
    return content.substring(pos, end).replaceAll('\n', ' ').trim();
  }

  // ---------------------------------------------------------------------------
  // Report
  // ---------------------------------------------------------------------------

  void _report(final AnalysisResult r) {
    if (r.unusedKeys.isEmpty && r.missingKeys.isEmpty && r.uncheckable.isEmpty) {
      MessagePrinter
          .info('All ${r.totalDefined} key(s) are used. No unused keys found.');
      return;
    }

    if (r.missingKeys.isNotEmpty) {
      MessagePrinter
          .info('\n--- Missing Translation Keys (${r.missingKeys.length}) ---');
      for (final entry in r.missingKeys.entries) {
        for (final file in entry.value) {
          MessagePrinter.info('  ${entry.key}  ← $file');
        }
      }
    }

    if (r.unusedKeys.isNotEmpty) {
      final unusedByFile = <String, Set<String>>{};
      for (final entry in r.definedKeys.entries) {
        final fileUnused = entry.value.intersection(r.unusedKeys);
        if (fileUnused.isNotEmpty) unusedByFile[entry.key] = fileUnused;
      }

      MessagePrinter
          .info('\n--- Unused Translation Keys (${r.unusedKeys.length}) ---');
      for (final entry in unusedByFile.entries) {
        for (final key in entry.value) {
          MessagePrinter.info('  $key  ← ${entry.key}');
        }
      }
    }

    if (r.uncheckable.isNotEmpty) {
      MessagePrinter.info(
          '\n--- Unresolvable References (${r.uncheckable.length}) ---');
      for (final ref in r.uncheckable) {
        MessagePrinter.info('  ${ref.filePath}:${ref.line}  ${ref.snippet}');
      }
    }

    MessagePrinter.info('\n--- Summary ---');
    MessagePrinter.info('  Defined:     ${r.totalDefined}');
    MessagePrinter.info('  Used:        ${r.totalUsed}');
    MessagePrinter.info('  Unused:      ${r.unusedKeys.length}');
    MessagePrinter.info('  Missing:     ${r.missingKeys.length}');
    MessagePrinter.info('  Uncheckable: ${r.uncheckable.length}');
  }

  // ---------------------------------------------------------------------------
  // Phase 4 — auto-clear
  // ---------------------------------------------------------------------------

  Future<void> _clear(final List<FileSystemEntity> assetsContent,
      final Map<String, Set<String>> definedKeys,
      final Set<String> unusedKeys) async {
    MessagePrinter.info('\nAuto-clearing unused keys...');
    final cleaner = TranslationCleaner();

    for (final entity in assetsContent) {
      final file = entity is File ? entity : File(entity.path);
      final fileDefined = definedKeys[file.path] ?? {};
      final toDelete = fileDefined.intersection(unusedKeys);
      if (toDelete.isEmpty) continue;

      final removed = await cleaner.clear(file, toDelete);
      final parentCount = removed - toDelete.length;
      if (parentCount > 0) {
        MessagePrinter.info(
            '  ${file.path}: removing ${toDelete.length} leaf key(s), $parentCount empty parent(s)');
      } else {
        MessagePrinter
            .info('  ${file.path}: removing ${toDelete.length} key(s)');
      }
    }
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
// Internal types
// ---------------------------------------------------------------------------

class _ImportInfo {
  final String? alias;
  final Set<String> shownNames;
  _ImportInfo({this.alias, this.shownNames = const {}});
}

class _ScanResult {
  final Map<String, Set<String>> usedKeys;
  final Set<String> pluralStems;
  final List<UnresolvedRef> uncheckable;
  _ScanResult(this.usedKeys, this.pluralStems, this.uncheckable);
}
