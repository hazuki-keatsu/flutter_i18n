import 'dart:convert';

import 'translation_document.dart';

class JsonDocument implements TranslationDocument {
  Map<dynamic, dynamic> _map;

  JsonDocument._(this._map);

  factory JsonDocument.parse(String content) {
    final map = json.decode(content) as Map<String, dynamic>;
    return JsonDocument._(map);
  }

  @override
  bool remove(List<String> path) {
    if (path.isEmpty) return false;
    return _removeLeaf(path) != null;
  }

  /// Remove leaf at [path], return the removed value or null if not found.
  /// Walks up to delete any parent maps that become empty.
  dynamic _removeLeaf(List<String> path) {
    // Find the parent of the leaf
    var current = _map;
    for (var i = 0; i < path.length - 1; i++) {
      final next = _resolveKey(current, path[i]);
      if (next is Map) {
        current = next;
      } else {
        return null;
      }
    }
    final removed = current.remove(_resolveKeyForRemoval(current, path.last));
    if (removed == null) return null;

    // Walk up to delete empty parent maps
    for (var i = path.length - 2; i >= 0; i--) {
      final parentPath = path.sublist(0, i + 1);
      final parent = _navigateTo(parentPath);
      if (parent is Map && parent.isEmpty) {
        _removeLeaf(parentPath);
      }
    }
    return removed;
  }

  dynamic _navigateTo(List<String> path) {
    dynamic current = _map;
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

  @override
  String serialize() {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(_map)}\n';
  }
}
