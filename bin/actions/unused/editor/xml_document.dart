import 'package:xml/xml.dart' as xml;

import 'translation_document.dart';

/// Source position span for an element's tags.
class _SourceSpan {
  final int startLine, startCol, endLine, endCol;
  const _SourceSpan(this.startLine, this.startCol, this.endLine, this.endCol);
}

/// A pending character-range edit to a line: remove [startCol, endCol).
class _LineEdit {
  final int startCol, endCol;
  const _LineEdit(this.startCol, this.endCol);
}

/// Tag info used during source ↔ DOM correlation.
class _Tag {
  final String name;
  final int startLine, startCol;
  int endLine = -1, endCol = -1; // set when closing tag matched
  _Tag(this.name, this.startLine, this.startCol);
}

/// Round-trip XML editor using [package:xml](https://pub.dev/packages/xml)
/// for DOM structure and source-level scanning for positions and comments.
class XmlDocument implements TranslationDocument {
  List<String> _lines = [];
  late final xml.XmlDocument _dom;
  // full path → xml.XmlElement
  final Map<String, xml.XmlElement> _domIndex = {};
  // xml.XmlElement identity → source position
  final Map<xml.XmlElement, _SourceSpan> _positions = {};
  // line → character edits
  final _lineEdits = <int, List<_LineEdit>>{};
  // line indices marked for full-line removal
  final _removedLines = <int>{};
  // element paths → attached comment lines
  final _commentLinesForPath = <String, List<int>>{};

  XmlDocument._();

  factory XmlDocument.parse(String content) {
    final doc = XmlDocument._();
    doc._lines = content.split('\n');
    doc._dom = xml.XmlDocument.parse(content);
    doc._buildDomIndex(doc._dom.rootElement, <String>[]);
    doc._correlate();
    return doc;
  }

  // ---------------------------------------------------------------------------
  // DOM index
  // ---------------------------------------------------------------------------

  void _buildDomIndex(xml.XmlElement elem, List<String> path) {
    final currentPath = [...path, elem.name.qualified];
    _domIndex[currentPath.join('.')] = elem;
    for (final child in elem.childElements) {
      _buildDomIndex(child, currentPath);
    }
  }

  // ---------------------------------------------------------------------------
  // Source ↔ DOM correlation + comment collection
  // ---------------------------------------------------------------------------

  void _correlate() {
    final tags = <_Tag>[];
    final pendingComments = <int>[];
    final pendingCommentTags = <_Tag, List<int>>{};
    final openRe = RegExp(r'<([_a-zA-Z][\w\-]*)>');
    final closeRe = RegExp(r'</([_a-zA-Z][\w\-]*)>');
    final selfCloseRe = RegExp(r'<([_a-zA-Z][\w\-]*)/>');
    final commentRe = RegExp(r'<!--(.*?)-->', dotAll: true);

    // 1) Scan source for tags and comments
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      final trimmed = line.trimLeft();
      final stripped = trimmed.trimRight();

      if (stripped.isEmpty) {
        pendingComments.clear();
        continue;
      }

      if (stripped.startsWith('<?xml')) continue;

      // Standalone comment
      final commentM = commentRe.matchAsPrefix(stripped);
      if (commentM != null) {
        pendingComments.add(i);
        continue;
      }

      // Scan the line for tags
      var pos = 0;
      var foundTag = false;
      while (pos < line.length) {
        final remaining = line.substring(pos);

        final scM = selfCloseRe.matchAsPrefix(remaining);
        if (scM != null) {
          final t = _Tag(scM.group(1)!, i, pos);
          t.endLine = i;
          t.endCol = pos + scM.end;
          tags.add(t);
          foundTag = true;
          pos += scM.end;
          continue;
        }

        final openM = openRe.matchAsPrefix(remaining);
        if (openM != null) {
          tags.add(_Tag(openM.group(1)!, i, pos));
          foundTag = true;
          pos += openM.end;
          continue;
        }

        final closeM = closeRe.matchAsPrefix(remaining);
        if (closeM != null) {
          for (var j = tags.length - 1; j >= 0; j--) {
            if (tags[j].name == closeM.group(1) && tags[j].endLine == -1) {
              tags[j].endLine = i;
              tags[j].endCol = pos + closeM.end;
              break;
            }
          }
          pos += closeM.end;
          continue;
        }

        final lt = remaining.indexOf('<');
        if (lt < 0) break;
        pos += lt;
      }

      // Attach pending comments to this line's tag (deferred — _positions
      // won't be populated until walkAssign in step 2).
      if (foundTag && pendingComments.isNotEmpty) {
        for (var j = tags.length - 1; j >= 0; j--) {
          if (tags[j].startLine == i) {
            pendingCommentTags[tags[j]] = List.of(pendingComments);
            break;
          }
        }
        pendingComments.clear();
      }
    }

    // 2) Walk DOM and assign source positions by matching document order
    final unmatched = tags.where((t) => t.name.isNotEmpty).toList();
    var idx = 0;

    void walkAssign(xml.XmlElement elem) {
      if (idx >= unmatched.length) return;
      final tag = unmatched[idx];
      if (tag.name == elem.name.qualified && tag.endLine >= 0) {
        _positions[elem] =
            _SourceSpan(tag.startLine, tag.startCol, tag.endLine, tag.endCol);
        idx++;
      }
      for (final child in elem.childElements) {
        walkAssign(child);
      }
    }

    walkAssign(_dom.rootElement);

    // 3) Resolve deferred comment attachments now that _positions is populated
    for (final tag in pendingCommentTags.keys) {
      for (final entry in _domIndex.entries) {
        final span = _positions[entry.value];
        if (span != null &&
            span.startLine == tag.startLine &&
            span.startCol == tag.startCol) {
          _commentLinesForPath[entry.key] = pendingCommentTags[tag]!;
          break;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Remove
  // ---------------------------------------------------------------------------

  @override
  bool remove(List<String> path) {
    final fullPath = path.join('.');
    var elem = _domIndex[fullPath];
    elem ??= _domIndex['${_dom.rootElement.name.qualified}.$fullPath'];
    if (elem == null) return false;

    _markRemoved(elem);
    return true;
  }

  void _markRemoved(xml.XmlElement elem) {
    final elemPath = _findPath(elem);
    final span = _positions.remove(elem);
    if (span == null) return;

    if (span.startLine == span.endLine) {
      _lineEdits.putIfAbsent(span.startLine, () => <_LineEdit>[])
          .add(_LineEdit(span.startCol, span.endCol));
    } else {
      for (var i = span.startLine; i <= span.endLine && i < _lines.length; i++) {
        _removedLines.add(i);
      }
    }

    // Remove attached comment lines
    if (elemPath != null) {
      final comments = _commentLinesForPath.remove(elemPath);
      if (comments != null) _removedLines.addAll(comments);
    }

    // Check empty parent
    final parent = elem.parentElement;
    if (parent != null && parent != _dom.rootElement) {
      _checkEmptyParent(parent);
    }
  }

  void _checkEmptyParent(xml.XmlElement parent) {
    if (!_positions.containsKey(parent)) return;
    for (final child in parent.childElements) {
      if (_positions.containsKey(child)) return;
    }
    _markRemoved(parent);
  }

  String? _findPath(xml.XmlElement elem) {
    for (final entry in _domIndex.entries) {
      if (entry.value == elem) return entry.key;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Serialize
  // ---------------------------------------------------------------------------

  @override
  String serialize() {
    for (final entry in _lineEdits.entries) {
      final lineNum = entry.key;
      if (_removedLines.contains(lineNum)) continue;
      final edits = entry.value.toList()
        ..sort((a, b) => a.startCol.compareTo(b.startCol));
      final orig = _lines[lineNum];
      final buf = StringBuffer();
      var pos = 0;
      for (final edit in edits) {
        if (edit.startCol > pos) {
          buf.write(orig.substring(pos, edit.startCol));
        }
        if (edit.endCol > pos) pos = edit.endCol;
      }
      if (pos < orig.length) buf.write(orig.substring(pos));
      _lines[lineNum] = buf.toString();
    }

    final out = StringBuffer();
    for (var i = 0; i < _lines.length; i++) {
      if (_removedLines.contains(i)) continue;
      final line = _lines[i];
      if (line.trim().isEmpty && _lineEdits.containsKey(i)) continue;
      out.writeln(line);
    }
    var result = out.toString();
    while (result.endsWith('\n\n')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
