import 'dart:io';

import 'package:toml/toml.dart';

import 'format_cleaner.dart';

class TomlCleaner extends FormatCleaner {
  @override
  Future<int> clear(File file, Set<String> keys) async {
    final lines = await file.readAsLines();
    final toRemove = <int>{};

    // Phase 1: Delete leaf keys
    for (final key in keys) {
      final leafKey = key.split('.').last;
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (RegExp('^${RegExp.escape(leafKey)}\\s*=').hasMatch(trimmed)) {
          toRemove.add(i);
        }
      }
    }

    // Phase 2: Iteratively delete empty sections
    var changed = true;
    while (changed) {
      changed = false;
      final remainingForParse = <String>[];
      for (var i = 0; i < lines.length; i++) {
        if (!toRemove.contains(i)) remainingForParse.add(lines[i]);
      }
      final tomlContent = remainingForParse.join('\n');
      if (tomlContent.trim().isEmpty) break;

      try {
        final parsed = TomlDocument.parse(tomlContent).toMap();
        final emptyPaths = <String>{};
        FormatCleaner.collectEmptyPaths(parsed, '', emptyPaths);
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
      List<String> lines, String path, Set<int> toRemove) {
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed == '[$path]') {
        if (!toRemove.add(i)) return false;
        for (var j = i + 1; j < lines.length; j++) {
          if (lines[j].trim().startsWith('[')) break;
          toRemove.add(j);
        }
        return true;
      }
    }
    return false;
  }
}
