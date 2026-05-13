import 'dart:convert';
import 'dart:io';

import 'format_cleaner.dart';

class JsonCleaner extends FormatCleaner {
  @override
  Future<int> clear(File file, Set<String> keys) async {
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
  void _removeKey(Map<dynamic, dynamic> map, List<String> path) {
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

  void _removeLeaf(Map<dynamic, dynamic> map, List<String> path) {
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

  dynamic _navigateTo(Map<dynamic, dynamic> map, List<String> path) {
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

  dynamic _resolveKey(Map<dynamic, dynamic> map, String key) {
    if (map.containsKey(key)) return map[key];
    final intKey = int.tryParse(key);
    if (intKey != null && map.containsKey(intKey)) return map[intKey];
    return null;
  }

  dynamic _resolveKeyForRemoval(Map<dynamic, dynamic> map, String key) {
    if (map.containsKey(key)) return key;
    final intKey = int.tryParse(key);
    if (intKey != null && map.containsKey(intKey)) return intKey;
    return key;
  }
}
