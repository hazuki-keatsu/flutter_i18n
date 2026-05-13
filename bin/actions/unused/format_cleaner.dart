import 'dart:io';

/// Contract for a per-format unused-key remover.
abstract class FormatCleaner {
  /// Remove [keys] from [file]. Returns the number of keys removed.
  Future<int> clear(File file, Set<String> keys);

  /// Collects paths of all empty Maps in [map] into [out].
  static void collectEmptyPaths(
      Map<dynamic, dynamic> map, String prefix, Set<String> out) {
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = entry.value;
      if (value is Map) {
        if (value.isEmpty) {
          out.add(path);
        } else {
          collectEmptyPaths(value, path, out);
        }
      }
    }
  }
}
