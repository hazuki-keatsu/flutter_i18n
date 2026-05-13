import 'dart:convert';
import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';
import 'package:toml/toml.dart';
import 'package:yaml/yaml.dart';

/// Deletes unused keys from translation files, preserving formatting.
///
/// Strategies vary by format:
/// - JSON: parse → delete from map → pretty-print + upward cleanup
/// - YAML / XML / TOML: line-based deletion + upward empty-parent cleanup
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
  // JSON — safe round-trip with upward empty-parent cleanup
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

  /// Remove leaf key at [path] and walk up to delete any parent maps that
  /// become empty as a result.
  void _removeKey(final Map<dynamic, dynamic> map, final List<String> path) {
    if (path.isEmpty) return;
    _removeLeaf(map, path);
    for (var i = path.length - 2; i >= 0; i--) {
      final parentPath = path.sublist(0, i + 1);
      final parent = _navigateTo(map, parentPath);
      if (parent is Map && parent.isEmpty) {
        _removeLeaf(map, parentPath);
      }
    }
  }

  void _removeLeaf(final Map<dynamic, dynamic> map, final List<String> path) {
    var current = map;
    for (var i = 0; i < path.length - 1; i++) {
      final next = _resolveKey(current, path[i]);
      if (next is Map) {
        current = next;
      } else {
        return;
      }
    }
    current.remove(_resolveKeyForRemoval(current, path.last));
  }

  dynamic _navigateTo(final Map<dynamic, dynamic> map, final List<String> path) {
    dynamic current = map;
    for (final segment in path) {
      if (current is Map) {
        current = _resolveKey(current, segment);
      } else {
        return current;
      }
    }
    return current;
  }

  /// Resolve [key] in [map], trying string first then int.
  dynamic _resolveKey(final Map<dynamic, dynamic> map, final String key) {
    if (map.containsKey(key)) return map[key];
    final intKey = int.tryParse(key);
    if (intKey != null && map.containsKey(intKey)) return map[intKey];
    return null;
  }

  /// Find the actual key (string or int) in [map] for removal.
  dynamic _resolveKeyForRemoval(
      final Map<dynamic, dynamic> map, final String key) {
    if (map.containsKey(key)) return key;
    final intKey = int.tryParse(key);
    if (intKey != null && map.containsKey(intKey)) return intKey;
    return key;
  }

  // -----------------------------------------------------------------------
  // YAML — line-based with upward empty-parent cleanup
  // -----------------------------------------------------------------------

  Future<int> _clearYaml(final File file, final Set<String> keys) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    // Phase 1: Delete leaf keys
    for (final key in keys) {
      _findYamlLine(lines, key.split('.'), toRemove);
    }

    // Phase 2: Iteratively delete empty parent keys
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < lines.length; i++) {
        if (toRemove.contains(i)) continue;
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        if (!trimmed.endsWith(':')) continue;

        final indent = line.length - trimmed.length;
        if (_scopeHasContent(lines, i, indent, toRemove)) continue;

        toRemove.add(i);
        _markScope(lines, i, indent, toRemove);
        changed = true;
      }
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!toRemove.contains(i)) remaining.add(lines[i]);
    }
    await file.writeAsString('${remaining.join('\n')}\n');
    return toRemove.length;
  }

  bool _scopeHasContent(final List<String> lines, final int start,
      final int indent, final Set<int> toRemove) {
    for (var j = start + 1; j < lines.length; j++) {
      final childIndent = lines[j].length - lines[j].trimLeft().length;
      if (childIndent <= indent) return false;
      final childTrimmed = lines[j].trimLeft();
      if (childTrimmed.isEmpty || childTrimmed.startsWith('#') ||
          toRemove.contains(j)) {
        continue;
      }
      return true;
    }
    return false;
  }

  void _markScope(final List<String> lines, final int start, final int indent,
      final Set<int> toRemove) {
    for (var j = start + 1; j < lines.length; j++) {
      if (lines[j].length - lines[j].trimLeft().length <= indent) break;
      toRemove.add(j);
    }
  }

  void _findYamlLine(final List<String> lines, final List<String> keyParts,
      final Set<int> toRemove) {
    final lineNum = _findYamlKeyLineNumber(lines, keyParts);
    if (lineNum >= 0) toRemove.add(lineNum);
  }

  int _findYamlKeyLineNumber(
      final List<String> lines, final List<String> keyParts) {
    if (keyParts.isEmpty) return -1;
    var depth = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().isEmpty || line.trimLeft().startsWith('#')) continue;

      final indent = line.length - line.trimLeft().length;
      final trimmed = line.trimLeft();
      if (depth > keyParts.length) return -1;

      if (depth < keyParts.length &&
          trimmed.startsWith('${keyParts[depth]}:')) {
        depth++;
        if (depth == keyParts.length) return i;
        continue;
      }

      final expectedMinIndent = depth * 2;
      if (indent < expectedMinIndent && depth > 0) return -1;
    }
    return -1;
  }

  // -----------------------------------------------------------------------
  // XML — regex-based element removal with upward cleanup
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

    // Upward cleanup: iteratively remove empty parent elements
    var changed = true;
    while (changed) {
      changed = false;
      final previous = content;
      content = content.replaceAll(RegExp(r'<(\w+)>\s*</\1>'), '');
      if (content != previous) {
        changed = true;
        count++;
      }
    }

    await file.writeAsString(content);
    return count;
  }

  // -----------------------------------------------------------------------
  // TOML — line-based with upward empty-parent cleanup
  // -----------------------------------------------------------------------

  Future<int> _clearToml(final File file, final Set<String> keys) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    // Phase 1: Delete leaf keys
    for (final key in keys) {
      final leafKey = key.split('.').last;
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('$leafKey ') || trimmed.startsWith('$leafKey=')) {
          toRemove.add(i);
        }
      }
    }

    // Phase 2: Iteratively delete empty sections
    var changed = true;
    while (changed) {
      changed = false;
      // Rebuild remaining lines to parse
      final remainingForParse = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (!toRemove.contains(i)) remainingForParse.add(lines[i]);
      }
      final tomlContent = remainingForParse.join('\n');
      if (tomlContent.trim().isEmpty) break;

      try {
        final parsed = TomlDocument.parse(tomlContent).toMap();
        final emptyPaths = <String>{};
        _collectEmptyPaths(parsed, '', emptyPaths);
        if (emptyPaths.isNotEmpty) {
          for (final path in emptyPaths) {
            if (_markTomlSection(lines, path, toRemove)) {
              changed = true;
            }
          }
        }
      } on FormatException {
        break;
      }
    }

    final remaining = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!toRemove.contains(i)) remaining.add(lines[i]);
    }
    await file.writeAsString('${remaining.join('\n')}\n');
    return toRemove.length;
  }

  bool _markTomlSection(
      final List<String> lines, final String path, final Set<int> toRemove) {
    final sectionName = path;
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed == '[$sectionName]') {
        if (!toRemove.add(i)) return false; // already marked
        // Mark all lines until next section header
        for (var j = i + 1; j < lines.length; j++) {
          if (lines[j].trim().startsWith('[')) break;
          toRemove.add(j);
        }
        return true;
      }
    }
    return false;
  }

  // -----------------------------------------------------------------------
  // Shared helpers
  // -----------------------------------------------------------------------

  /// Collects paths of all empty Maps in [map] into [out].
  void _collectEmptyPaths(final Map<dynamic, dynamic> map, final String prefix,
      final Set<String> out) {
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = entry.value;
      if (value is Map) {
        if (value.isEmpty) {
          out.add(path);
        } else {
          _collectEmptyPaths(value, path, out);
        }
      }
    }
  }
}
