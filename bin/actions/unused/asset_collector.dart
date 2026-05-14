import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

import '../../utils/local_loader.dart';
import 'file_keys.dart';

/// Discovers translation files and extracts defined keys.
class AssetCollector {
  final bool verbose;
  final List<String> acceptedExtensions;

  const AssetCollector({
    this.verbose = false,
    this.acceptedExtensions = const ['.json', '.yaml', '.xml', '.toml'],
  });

  // ---------------------------------------------------------------------------
  // File discovery
  // ---------------------------------------------------------------------------

  /// Collect translation files from [paths] (files or directories).
  List<FileSystemEntity> collectFiles(final List<String> paths) {
    return paths.expand(_collect).toList();
  }

  List<FileSystemEntity> _collect(final String path) {
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

  // ---------------------------------------------------------------------------
  // Key extraction
  // ---------------------------------------------------------------------------

  /// Parse [files] and return defined keys keyed by file path.
  Future<Map<String, FileKeys>> collectKeys(
      final List<FileSystemEntity> files) async {
    final result = <String, FileKeys>{};

    for (final entity in files) {
      final file = entity is File ? entity : File(entity.path);
      Map<dynamic, dynamic>? map;
      try {
        map = await LocalLoader(file).loadContent();
      } catch (e) {
        MessagePrinter.error('Failed to decode ${file.path}: $e');
        continue;
      }
      if (map == null || map.isEmpty) {
        if (verbose) {
          MessagePrinter.error('Empty content in ${file.path}');
        }
        continue;
      }

      final namespace = detectNamespace(file.path);
      final keys = <String>{};
      flattenMap(map, namespace, '', keys);

      if (verbose) {
        MessagePrinter.info('${file.path} → ${keys.length} key(s)');
      }
      result[file.path] = FileKeys(file.path, namespace, keys);
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Map flattening
  // ---------------------------------------------------------------------------

  /// Walk a nested [map] and collect dot-separated key paths whose leaf
  /// values are [String]s.  [namespace] is prepended to every key when set.
  static void flattenMap(final Map<dynamic, dynamic> map,
      final String? namespace, final String prefix, final Set<String> out) {
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final fullKey = prefix.isEmpty ? key : '$prefix.$key';
      final value = entry.value;
      if (value is Map) {
        flattenMap(value, namespace, fullKey, out);
      } else if (value is String) {
        out.add(namespace != null ? '$namespace.$fullKey' : fullKey);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Namespace detection
  // ---------------------------------------------------------------------------

  /// Returns the namespace (filename without extension) if the parent
  /// directory looks like a language-code container, or `null` otherwise.
  static String? detectNamespace(final String filePath) {
    final parentDirName =
        File(filePath).parent.path.split(RegExp(r'[/\\]')).last;
    if (_isLanguageCode(parentDirName)) {
      final name = filePath.split(RegExp(r'[/\\]')).last;
      final dot = name.lastIndexOf('.');
      return dot > 0 ? name.substring(0, dot) : name;
    }
    return null;
  }

  /// Check [name] against known ISO 639-1 codes, with optional `_`-separated
  /// script and country suffixes (e.g. `en`, `zh_Hans`, `pt_BR`).
  static bool _isLanguageCode(final String name) {
    final parts = name.split('_');
    if (parts.isEmpty || !_knownLanguageCodes.contains(parts.first)) {
      return false;
    }
    for (var i = 1; i < parts.length; i++) {
      if (!RegExp(r'^[A-Z][a-z]{3}$').hasMatch(parts[i]) &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(parts[i])) {
        return false;
      }
    }
    return true;
  }

  static const _knownLanguageCodes = {
    'aa', 'ab', 'ae', 'af', 'ak', 'am', 'an', 'ar', 'as', 'av', 'ay', 'az',
    'ba', 'be', 'bg', 'bh', 'bi', 'bm', 'bn', 'bo', 'br', 'bs',
    'ca', 'ce', 'ch', 'co', 'cr', 'cs', 'cu', 'cv', 'cy',
    'da', 'de', 'dv', 'dz',
    'ee', 'el', 'en', 'eo', 'es', 'et', 'eu',
    'fa', 'ff', 'fi', 'fj', 'fo', 'fr', 'fy',
    'ga', 'gd', 'gl', 'gn', 'gu', 'gv',
    'ha', 'he', 'hi', 'ho', 'hr', 'ht', 'hu', 'hy', 'hz',
    'ia', 'id', 'ie', 'ig', 'ii', 'ik', 'io', 'is', 'it', 'iu',
    'ja', 'jv',
    'ka', 'kg', 'ki', 'kj', 'kk', 'kl', 'km', 'kn', 'ko', 'kr', 'ks', 'ku',
        'kv', 'kw', 'ky',
    'la', 'lb', 'lg', 'li', 'ln', 'lo', 'lt', 'lu', 'lv',
    'mg', 'mh', 'mi', 'mk', 'ml', 'mn', 'mr', 'ms', 'mt', 'my',
    'na', 'nb', 'nd', 'ne', 'ng', 'nl', 'nn', 'no', 'nr', 'nv', 'ny',
    'oc', 'oj', 'om', 'or', 'os',
    'pa', 'pi', 'pl', 'ps', 'pt',
    'qu',
    'rm', 'rn', 'ro', 'ru', 'rw',
    'sa', 'sc', 'sd', 'se', 'sg', 'si', 'sk', 'sl', 'sm', 'sn', 'so', 'sq',
        'sr', 'ss', 'st', 'su', 'sv', 'sw',
    'ta', 'te', 'tg', 'th', 'ti', 'tk', 'tl', 'tn', 'to', 'tr', 'ts', 'tt',
        'tw', 'ty',
    'ug', 'uk', 'ur', 'uz',
    've', 'vi', 'vo',
    'wa', 'wo',
    'xh',
    'yi', 'yo',
    'za', 'zh', 'zu',
  };
}
