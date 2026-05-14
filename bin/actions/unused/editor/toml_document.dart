import 'package:toml/toml.dart' as toml;

import 'translation_document.dart';

class _KeyLoc {
  final int line;
  final String? subKey; // null = top-level key, non-null = inline table entry
  const _KeyLoc(this.line, this.subKey);
}

/// Round-trip TOML editor. Structure is validated by [package:toml](https://pub.dev/packages/toml);
/// source-level line scanning handles comment positions and inline-table
/// rewriting.
class TomlDocument implements TranslationDocument {
  List<String> _lines;
  final _removedLines = <int>{};
  final _inlineRemovals = <int, Set<String>>{};
  final _eolComments = <int, String>{};
  final _keyMap = <String, _KeyLoc>{};
  final _sectionHeaders = <String, int>{};
  final _standaloneCommentLines = <int, List<int>>{};
  List<int> _pendingComments = [];
  Map<String, dynamic> _parsed = {};

  TomlDocument._() : _lines = [];

  factory TomlDocument.parse(String content) {
    final doc = TomlDocument._();
    doc._lines = content.split('\n');
    doc._parsed = toml.TomlDocument.parse(content).toMap();
    doc._scanSource();
    return doc;
  }

  // ---------------------------------------------------------------------------
  // Source scanning (positions + comments)
  // ---------------------------------------------------------------------------

  void _scanSource() {
    var currentSection = '';
    _pendingComments = [];

    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final trimmed = line.trimLeft();
      final stripped = trimmed.trimRight();

      if (stripped.isEmpty) {
        _pendingComments = [];
        continue;
      }

      // Section header
      if (stripped.startsWith('[') &&
          stripped.endsWith(']') &&
          !stripped.startsWith('[[')) {
        currentSection = stripped.substring(1, stripped.length - 1);
        _sectionHeaders[currentSection] = i;
        _pendingComments = [];
        continue;
      }

      // Standalone comment line
      if (stripped.startsWith('#')) {
        _pendingComments.add(i);
        continue;
      }

      // Key-value line
      final eqIdx = _findEqIndex(line);
      if (eqIdx < 0) continue;

      final rawKey = line.substring(0, eqIdx).trim();
      final key = _normalizeKey(rawKey);
      final fullPath = currentSection.isEmpty ? key : '$currentSection.$key';

      final valuePart = line.substring(eqIdx + 1).trim();

      // End-of-line comment
      final hashIdx = _findHashInValue(valuePart);
      if (hashIdx >= 0) {
        _eolComments[i] = valuePart.substring(hashIdx + 1).trim();
      }

      // Attach pending standalone comments to this key
      if (_pendingComments.isNotEmpty) {
        _standaloneCommentLines[i] = List.of(_pendingComments);
        _pendingComments = [];
      }

      if (_isInlineTable(valuePart)) {
        for (final sk in _parseInlineTableKeys(valuePart, hashIdx)) {
          _keyMap['$fullPath.$sk'] = _KeyLoc(i, sk);
        }
      }

      _keyMap[fullPath] = _KeyLoc(i, null);
    }
  }

  // ---------------------------------------------------------------------------
  // Remove
  // ---------------------------------------------------------------------------

  @override
  bool remove(List<String> path) {
    final fullPath = path.join('.');
    // Validate path exists in parsed structure
    if (_lookupParsed(path) == null) return false;

    final loc = _keyMap[fullPath];
    if (loc == null) return false;

    if (loc.subKey != null) {
      _inlineRemovals.putIfAbsent(loc.line, () => <String>{}).add(loc.subKey!);
    } else {
      _removedLines.add(loc.line);
      final comments = _standaloneCommentLines[loc.line];
      if (comments != null) _removedLines.addAll(comments);
    }
    return true;
  }

  /// Walk [_parsed] to confirm [path] exists.
  dynamic _lookupParsed(List<String> path) {
    dynamic current = _parsed;
    for (final segment in path) {
      if (current is Map) {
        if (current.containsKey(segment)) {
          current = current[segment];
        } else {
          final intKey = int.tryParse(segment);
          if (intKey != null && current.containsKey(intKey)) {
            current = current[intKey];
          } else {
            return null;
          }
        }
      } else {
        return null;
      }
    }
    return current;
  }

  // ---------------------------------------------------------------------------
  // Serialize
  // ---------------------------------------------------------------------------

  @override
  String serialize() {
    // Rewrite inline-table lines with sub-key removals
    for (final entry in _inlineRemovals.entries) {
      final line = entry.key;
      final toRemove = entry.value;
      final original = _lines[line];
      final eqIdx = _findEqIndex(original);
      if (eqIdx < 0) continue;

      final valuePart = original.substring(eqIdx + 1).trim();
      final hashIdx = _findHashInValue(valuePart);
      final tableInner = _extractInlineTableInner(valuePart, hashIdx);
      if (tableInner == null) continue;

      final remaining = _removeInlineEntries(tableInner, toRemove);
      if (remaining.isEmpty) {
        _removedLines.add(line);
        final comments = _standaloneCommentLines[line];
        if (comments != null) _removedLines.addAll(comments);
      } else {
        final rawKey = original.substring(0, eqIdx).trim();
        final indent = original.length - original.trimLeft().length;
        final leading = ' ' * indent;
        final comment = _eolComments[line];
        final commentStr = comment != null ? ' #$comment' : '';
        _lines[line] = '$leading$rawKey = { $remaining }$commentStr';
      }
    }

    _removeEmptySections();

    final buf = StringBuffer();
    for (var i = 0; i < _lines.length; i++) {
      if (_removedLines.contains(i)) continue;
      buf.writeln(_lines[i]);
    }
    return buf.toString();
  }

  /// Walk [_parsed] to detect empty sections after removals.
  void _removeEmptySections() {
    for (final entry in _sectionHeaders.entries) {
      final sectionPath = entry.key;
      final headerLine = entry.value;
      if (_removedLines.contains(headerLine)) continue;

      if (_isSectionEmpty(sectionPath)) {
        _removedLines.add(headerLine);
        for (var j = headerLine - 1; j >= 0; j--) {
          final trimmed = _lines[j].trim();
          if (trimmed.isEmpty) break;
          if (trimmed.startsWith('#')) {
            _removedLines.add(j);
          } else {
            break;
          }
        }
      }
    }
  }

  bool _isSectionEmpty(String sectionPath) {
    final parts = sectionPath.split('.');
    dynamic section = _parsed;
    for (final part in parts) {
      if (section is Map) {
        section = section[part] ?? section[int.tryParse(part) ?? -1];
        if (section == null) return true;
      } else {
        return true;
      }
    }
    if (section is! Map) return false;

    for (final subKey in section.keys) {
      final subPath = '$sectionPath.$subKey';
      final loc = _keyMap[subPath];
      if (loc == null) return false;

      if (loc.subKey != null) {
        final removals = _inlineRemovals[loc.line];
        if (removals == null || !removals.contains(loc.subKey)) {
          if (!_removedLines.contains(loc.line)) return false;
        }
      } else if (!_removedLines.contains(loc.line)) {
        return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Line-level helpers
  // ---------------------------------------------------------------------------

  int _findEqIndex(String line) {
    var inString = false;
    var stringChar = '';
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inString) {
        if (c == '\\') {
          i++;
        } else if (c == stringChar) {
          inString = false;
        }
      } else if (c == '"' || c == "'") {
        inString = true;
        stringChar = c;
      } else if (c == '=') {
        return i;
      }
    }
    return -1;
  }

  int _findHashInValue(String valuePart) {
    var inString = false;
    var stringChar = '';
    for (var i = 0; i < valuePart.length; i++) {
      final c = valuePart[i];
      if (inString) {
        if (c == '\\') {
          i++;
        } else if (c == stringChar) {
          inString = false;
        }
      } else if (c == '"' || c == "'") {
        inString = true;
        stringChar = c;
      } else if (c == '#') {
        return i;
      }
    }
    return -1;
  }

  bool _isInlineTable(String valuePart) {
    final stripped = valuePart.trim();
    return stripped.startsWith('{') && stripped.endsWith('}');
  }

  List<String> _parseInlineTableKeys(String valuePart, int hashIdx) {
    final inner = _extractInlineTableInner(valuePart, hashIdx);
    if (inner == null || inner.isEmpty) return [];
    final keys = <String>[];
    for (final entry in _splitInlineEntries(inner)) {
      final eqIdx = _findEqIndex(entry);
      if (eqIdx >= 0) {
        keys.add(_normalizeKey(entry.substring(0, eqIdx).trim()));
      }
    }
    return keys;
  }

  String? _extractInlineTableInner(String valuePart, int hashIdx) {
    var vp = valuePart;
    if (hashIdx >= 0) vp = vp.substring(0, hashIdx).trim();
    final stripped = vp.trim();
    if (!stripped.startsWith('{') || !stripped.endsWith('}')) return null;
    return stripped.substring(1, stripped.length - 1).trim();
  }

  List<String> _splitInlineEntries(String inner) {
    final entries = <String>[];
    var depth = 0;
    var inString = false;
    var stringChar = '';
    var start = 0;
    for (var i = 0; i < inner.length; i++) {
      final c = inner[i];
      if (inString) {
        if (c == '\\') {
          i++;
        } else if (c == stringChar) {
          inString = false;
        }
      } else if (c == '"' || c == "'") {
        inString = true;
        stringChar = c;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      } else if (c == ',' && depth == 0) {
        entries.add(inner.substring(start, i).trim());
        start = i + 1;
      }
    }
    if (start < inner.length) {
      entries.add(inner.substring(start).trim());
    }
    return entries;
  }

  String _removeInlineEntries(String inner, Set<String> toRemove) {
    final entries = _splitInlineEntries(inner);
    final remaining = <String>[];
    for (final entry in entries) {
      final eqIdx = _findEqIndex(entry);
      if (eqIdx >= 0) {
        final k = _normalizeKey(entry.substring(0, eqIdx).trim());
        if (toRemove.contains(k)) continue;
      }
      remaining.add(entry);
    }
    return remaining.join(', ');
  }

  String _normalizeKey(String raw) {
    if ((raw.startsWith('"') && raw.endsWith('"')) ||
        (raw.startsWith("'") && raw.endsWith("'"))) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }
}
