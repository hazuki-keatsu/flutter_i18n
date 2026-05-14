import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

import 'action_interface.dart';
import '../utils/local_loader.dart';
import 'unused/analysis_result.dart';
import 'unused/dart_scanner.dart';
import 'unused/file_keys.dart';
import 'unused/translation_cleaner.dart';

/// Scans translation assets and Dart source files to find unused / missing keys.
class UnusedAction extends AbstractAction {
  @override
  List<String> get acceptedExtensions => ['.json', '.yaml', '.xml', '.toml'];

  bool _autoClear = false;
  bool _verbose = false;

  /// If there are any unresolvable keys, AutoClear will be rejected, unless --force is added.
  bool _force = false;
  final _assetPaths = <String>[];
  final _codePaths = <String>[];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// CLI entry point (fire-and-forget, matches [AbstractAction] contract).
  @override
  void executeAction(final List<String> params) {
    analyze(params);
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

    final scanner = DartScanner(verbose: _verbose);
    final scanResult = await scanner.scan(dartFiles);
    final result = AnalysisResult(
      definedKeys: definedKeys,
      usedKeys: scanResult.usedKeys,
      usedPluralStems: scanResult.pluralStems,
      uncheckable: scanResult.uncheckable,
    );

    _report(result);

    if (_autoClear && result.unusedKeys.isNotEmpty) {
      if (result.uncheckable.isNotEmpty && !_force) {
        MessagePrinter.info(
            '\n${result.uncheckable.length} unresolvable reference(s) detected.'
            ' Use --force to auto-clear anyway, then verify deleted keys'
            ' against the unresolvable list manually.');
      } else {
        await _clear(assetsContent, definedKeys, result.unusedKeys);
        if (result.uncheckable.isNotEmpty && _force) {
          _printForceChecklist(assetsContent, definedKeys, result);
        }
      }
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
        final value = arg.substring('--asset='.length);
        if (value.isNotEmpty) _assetPaths.add(value);
      } else if (arg.startsWith('--code=')) {
        final value = arg.substring('--code='.length);
        if (value.isNotEmpty) _codePaths.add(value);
      } else if (arg == '--force') {
        _force = true;
      } else if (arg == '--help') {
        _displayHelpMessage();
        exit(0);
      }
    }
  }

  void _displayHelpMessage() {
    MessagePrinter.info(''
        'Usage: dart run flutter_i18n unused [options]\n'
        '\n'
        'Options:\n'
        '  --auto-clear    Delete unused keys from translation files\n'
        '  --force         Force delete even with unresolvable references\n'
        '  --verbose       Show per-key check status\n'
        '  --asset=<path>  Path to translation assets (repeatable)\n'
        '  --code=<path>   Path to Dart source code (repeatable)\n'
        '  --help          Show this help message'
        '\n'
        'Tips:\n'
        '  --auto-clear    may damage the format of the translation files\n'
        '  --force         is not recommended for using, unless the project under version controller and\n'
        '                  you can ensure all the FlutterI18n call can be with non-variable value');
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

  Future<Map<String, FileKeys>> _collectDefinedKeys(
      final List<FileSystemEntity> assetsContent) async {
    final result = <String, FileKeys>{};

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
      result[file.path] = FileKeys(file.path, namespace, keys);
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
  // Report
  // ---------------------------------------------------------------------------

  void _report(final AnalysisResult r) {
    if (r.unusedKeys.isEmpty &&
        r.missingKeys.isEmpty &&
        r.uncheckable.isEmpty) {
      MessagePrinter.info(
          'All ${r.totalDefined} key(s) are used. No unused keys found.');
      return;
    }

    if (r.missingKeys.isNotEmpty) {
      MessagePrinter.info(
          '\n--- Missing Translation Keys (${r.missingKeys.length}) ---');
      for (final entry in r.missingKeys.entries) {
        for (final file in entry.value) {
          MessagePrinter.info('  ${entry.key}  ← $file');
        }
      }
    }

    if (r.unusedKeys.isNotEmpty) {
      final unusedByFile = <String, Set<String>>{};
      for (final entry in r.definedKeys.entries) {
        final fileUnused = entry.value.fullKeys.intersection(r.unusedKeys);
        if (fileUnused.isNotEmpty) unusedByFile[entry.key] = fileUnused;
      }

      MessagePrinter.info(
          '\n--- Unused Translation Keys (${r.unusedKeys.length}) ---');
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

  Future<void> _clear(
      final List<FileSystemEntity> assetsContent,
      final Map<String, FileKeys> definedKeys,
      final Set<String> unusedKeys) async {
    MessagePrinter.info('\nAuto-clearing unused keys...');
    final cleaner = TranslationCleaner();

    for (final entity in assetsContent) {
      final file = entity is File ? entity : File(entity.path);
      final fileKeys = definedKeys[file.path];
      if (fileKeys == null) continue;

      final toDeleteFull = fileKeys.fullKeys.intersection(unusedKeys);
      if (toDeleteFull.isEmpty) continue;

      final ns = fileKeys.namespace;
      final toDelete = ns != null
          ? toDeleteFull
              .map((k) => k.startsWith('$ns.') ? k.substring(ns.length + 1) : k)
              .toSet()
          : toDeleteFull;

      final removed = await cleaner.clear(file, toDelete);
      final parentCount = removed - toDelete.length;
      if (parentCount > 0) {
        MessagePrinter.info(
            '  ${file.path}: removing ${toDelete.length} leaf key(s), $parentCount empty parent(s)');
      } else {
        MessagePrinter.info(
            '  ${file.path}: removing ${toDelete.length} key(s)');
      }
    }
  }

  void _printForceChecklist(final List<FileSystemEntity> assetsContent,
      final Map<String, FileKeys> definedKeys, final AnalysisResult result) {
    MessagePrinter.info('\n--- Deleted Keys (${result.unusedKeys.length}) ---');
    final unusedByFile = <String, Set<String>>{};
    for (final entry in definedKeys.entries) {
      final fileUnused = entry.value.fullKeys.intersection(result.unusedKeys);
      if (fileUnused.isNotEmpty) unusedByFile[entry.key] = fileUnused;
    }
    for (final entry in unusedByFile.entries) {
      for (final key in entry.value) {
        MessagePrinter.info('  $key  ← ${entry.key}');
      }
    }

    MessagePrinter.info(
        '\n--- Unresolvable References (${result.uncheckable.length})'
        ' — verify none of the above keys were used here ---');
    for (final ref in result.uncheckable) {
      MessagePrinter.info('  ${ref.filePath}:${ref.line}  ${ref.snippet}');
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
