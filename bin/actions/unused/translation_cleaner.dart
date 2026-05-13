import 'dart:convert';
import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

/// Deletes unused keys from translation files, preserving formatting.
///
/// Strategies vary by format:
/// - JSON: parse → delete from map → pretty-print  (safe round-trip)
/// - YAML / XML / TOML: line-based deletion  (preserves comments / formatting,
///   warns on empty parent keys)
class TranslationCleaner {
  /// Remove [keys] from [file]. Returns the number of keys removed.
  Future<int> clear(final File file, final Set<String> keys) async {
    final ext = file.path.split('.').last.toLowerCase();
    switch (ext) {
      case 'json':
        return _clearJson(file, keys);
      case 'yaml':
        return _clearYaml(file, keys);
      case 'xml':
        return _clearXml(file, keys);
      case 'toml':
        return _clearToml(file, keys);
      default:
        return 0;
    }
  }

  // -----------------------------------------------------------------------
  // JSON — safe round-trip
  // -----------------------------------------------------------------------

  Future<int> _clearJson(final File file, final Set<String> keys) async {
    final content = await file.readAsString();
    final map = json.decode(content) as Map<String, dynamic>;
    for (final key in keys) {
      _removeKey(map, key.split('.'));
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(map)}\n');
    return keys.length;
  }

  void _removeKey(final Map<dynamic, dynamic> map, final List<String> path) {
    if (path.isEmpty) return;
    var current = map;
    for (var i = 0; i < path.length - 1; i++) {
      final next = current[path[i]];
      if (next is Map) {
        current = next;
      } else {
        return;
      }
    }
    current.remove(path.last);
  }

  // -----------------------------------------------------------------------
  // YAML — line-based
  // -----------------------------------------------------------------------

  Future<int> _clearYaml(final File file, final Set<String> keys) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    for (final key in keys) {
      _findYamlLine(lines, key.split('.'), toRemove);
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!toRemove.contains(i)) remaining.add(lines[i]);
    }
    await file.writeAsString('${remaining.join('\n')}\n');
    _warnEmptyParents(lines, toRemove, file.path);
    return toRemove.length;
  }

  void _findYamlLine(final List<String> lines, final List<String> keyParts,
      final Set<int> toRemove) {
    if (keyParts.isEmpty) return;
    var depth = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().isEmpty || line.trimLeft().startsWith('#')) continue;

      final indent = line.length - line.trimLeft().length;
      final trimmed = line.trimLeft();
      if (depth > keyParts.length) return;

      if (depth < keyParts.length && trimmed.startsWith('${keyParts[depth]}:')) {
        depth++;
        if (depth == keyParts.length) {
          toRemove.add(i);
          return;
        }
        continue;
      }

      final expectedMinIndent = depth * 2;
      if (indent < expectedMinIndent && depth > 0) return;
    }
  }

  void _warnEmptyParents(final List<String> originalLines,
      final Set<int> removed, final String filePath) {
    for (final idx in removed) {
      final keyName = originalLines[idx].trimLeft().split(':')[0];
      MessagePrinter.debug(
          '$filePath: removed key "$keyName", verify parent keys manually');
    }
  }

  // -----------------------------------------------------------------------
  // XML — regex-based element removal
  // -----------------------------------------------------------------------

  Future<int> _clearXml(final File file, final Set<String> keys) async {
    var content = await file.readAsString();
    var count = 0;

    for (final key in keys) {
      final leafKey = key.split('.').last;
      final previous = content;

      // Self-closing: <leafKey ... />
      content = content.replaceAll(
          RegExp('<${RegExp.escape(leafKey)}[^>]*/>'), '');
      // Open + close + content: <leafKey ...>...</leafKey>
      content = content.replaceAll(
          RegExp(
              '<${RegExp.escape(leafKey)}[^>]*>[^<]*</${RegExp.escape(leafKey)}>'),
          '');
      if (content != previous) count++;
    }

    await file.writeAsString(content);
    return count;
  }

  // -----------------------------------------------------------------------
  // TOML — line-based
  // -----------------------------------------------------------------------

  Future<int> _clearToml(final File file, final Set<String> keys) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    for (final key in keys) {
      final leafKey = key.split('.').last;
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('$leafKey ') || trimmed.startsWith('$leafKey=')) {
          toRemove.add(i);
        }
      }
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!toRemove.contains(i)) remaining.add(lines[i]);
    }
    await file.writeAsString('${remaining.join('\n')}\n');
    return toRemove.length;
  }
}
