import 'dart:io';

import 'format_cleaner.dart';

class YamlCleaner extends FormatCleaner {
  @override
  Future<int> clear(File file, Set<String> keys) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    // Phase 1: Delete leaf keys
    for (final key in keys) {
      _markKeyLine(lines, key.split('.'), toRemove);
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

  bool _scopeHasContent(
      List<String> lines, int start, int indent, Set<int> toRemove) {
    for (var j = start + 1; j < lines.length; j++) {
      final childIndent = lines[j].length - lines[j].trimLeft().length;
      if (childIndent <= indent) return false;
      final childTrimmed = lines[j].trimLeft();
      if (childTrimmed.isEmpty ||
          childTrimmed.startsWith('#') ||
          toRemove.contains(j)) {
        continue;
      }
      return true;
    }
    return false;
  }

  void _markScope(
      List<String> lines, int start, int indent, Set<int> toRemove) {
    for (var j = start + 1; j < lines.length; j++) {
      if (lines[j].length - lines[j].trimLeft().length <= indent) break;
      toRemove.add(j);
    }
  }

  void _markKeyLine(
      List<String> lines, List<String> keyParts, Set<int> toRemove) {
    final lineNum = _findKeyLineNumber(lines, keyParts);
    if (lineNum >= 0) toRemove.add(lineNum);
  }

  int _findKeyLineNumber(List<String> lines, List<String> keyParts) {
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
}
