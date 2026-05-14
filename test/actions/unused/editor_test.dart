import 'package:flutter_test/flutter_test.dart';

import '../../../bin/actions/unused/editor/translation_document.dart';

// ---------------------------------------------------------------------------
// JSON
// ---------------------------------------------------------------------------

void _jsonTests() {
  group('JsonDocument', () {
    test('parses and serializes', () {
      const src = '{"a": "1", "b": {"c": "2"}}';
      final doc = TranslationDocument.parse(src, 'json');
      final out = doc.serialize().trim();
      expect(out, '{\n  "a": "1",\n  "b": {\n    "c": "2"\n  }\n}');
    });

    test('parses empty object', () {
      final doc = TranslationDocument.parse('{}', 'json');
      expect(doc.serialize().trim(), '{}');
    });

    test('removes flat key', () {
      final doc = TranslationDocument.parse(
          '{"keep": "x", "drop": "y"}', 'json');
      expect(doc.remove(['drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('keep'), isTrue);
      expect(out.contains('drop'), isFalse);
    });

    test('removes nested key', () {
      final doc = TranslationDocument.parse(
          '{"a": {"b": "v1", "c": "v2"}}', 'json');
      expect(doc.remove(['a', 'b']), isTrue);
      final out = doc.serialize();
      expect(out.contains('"b"'), isFalse);
      expect(out.contains('"c"'), isTrue);
    });

    test('removes empty parent recursively', () {
      final doc = TranslationDocument.parse(
          '{"x": {"y": {"z": "leaf"}}}', 'json');
      expect(doc.remove(['x', 'y', 'z']), isTrue);
      final out = doc.serialize();
      expect(out.contains('"x"'), isFalse);
      expect(out.contains('"y"'), isFalse);
      expect(out.contains('"z"'), isFalse);
    });

    test('keeps parent when sibling remains', () {
      final doc = TranslationDocument.parse(
          '{"x": {"a": "1", "b": "2"}}', 'json');
      expect(doc.remove(['x', 'a']), isTrue);
      final out = doc.serialize();
      expect(out.contains('"x"'), isTrue);
      expect(out.contains('"b"'), isTrue);
      expect(out.contains('"a"'), isFalse);
    });

    test('returns false for non-existent path', () {
      final doc = TranslationDocument.parse('{"a": "1"}', 'json');
      expect(doc.remove(['b']), isFalse);
      expect(doc.remove(['a', 'b']), isFalse);
    });

    test('handles integer-segment keys', () {
      final doc = TranslationDocument.parse(
          '{"errors": {"404": {"title": "Not found"}}}', 'json');
      expect(doc.remove(['errors', '404', 'title']), isTrue);
      final out = doc.serialize();
      expect(out.contains('404'), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// YAML
// ---------------------------------------------------------------------------

void _yamlTests() {
  group('YamlDocument', () {
    test('parses and serializes preserving comments', () {
      const src = 'key: value\n# a comment\nother: x\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      final out = doc.serialize();
      expect(out.contains('# a comment'), isTrue);
      expect(out.contains('key: value'), isTrue);
    });

    test('parses empty', () {
      final doc = TranslationDocument.parse('', 'yaml');
      expect(doc.serialize().trim(), isEmpty);
    });

    test('removes flat key', () {
      const src = 'keep: "x"\ndrop: "y"\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      expect(doc.remove(['drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('keep'), isTrue);
      expect(out.contains('drop'), isFalse);
    });

    test('removes nested key', () {
      const src = 'a:\n  b: v1\n  c: v2\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      expect(doc.remove(['a', 'b']), isTrue);
      final out = doc.serialize();
      expect(out.contains('b'), isFalse);
      expect(out.contains('c'), isTrue);
    });

    test('removes empty parent recursively', () {
      const src = 'x:\n  y:\n    z: leaf\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      expect(doc.remove(['x', 'y', 'z']), isTrue);
      final out = doc.serialize();
      expect(out.contains('x'), isFalse);
      expect(out.contains('y'), isFalse);
      expect(out.contains('z'), isFalse);
    });

    test('keeps parent when sibling remains', () {
      const src = 'x:\n  a: "1"\n  b: "2"\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      expect(doc.remove(['x', 'a']), isTrue);
      final out = doc.serialize();
      expect(out.contains('x'), isTrue);
      expect(out.contains('b'), isTrue);
      expect(out.contains('a'), isFalse);
    });

    test('returns false for non-existent path', () {
      const src = 'a: "1"\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      expect(doc.remove(['b']), isFalse);
    });

    test('preserves standalone comment when unrelated key is removed', () {
      const src = '# my comment\nkeep: x\ndrop: y\n';
      final doc = TranslationDocument.parse(src, 'yaml');
      expect(doc.remove(['drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('# my comment'), isTrue);
      expect(out.contains('keep: x'), isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// TOML
// ---------------------------------------------------------------------------

void _tomlTests() {
  group('TomlDocument', () {
    test('parses and serializes', () {
      const src = '[section]\nkey = "value"\n';
      final doc = TranslationDocument.parse(src, 'toml');
      final out = doc.serialize();
      expect(out.contains('[section]'), isTrue);
      expect(out.contains('key'), isTrue);
    });

    test('parses empty', () {
      final doc = TranslationDocument.parse('', 'toml');
      expect(doc.serialize().trim(), '');
    });

    test('removes flat key under section', () {
      const src = '[a]\nkeep = "x"\ndrop = "y"\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('keep'), isTrue);
      expect(out.contains('drop'), isFalse);
    });

    test('removes nested key from inline table', () {
      const src = '[a]\ndata = { save = "s", discard = "d" }\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'data', 'save']), isTrue);
      final out = doc.serialize();
      expect(out.contains('discard'), isTrue);
      expect(out.contains('save'), isFalse);
    });

    test('removes inline-table line when all sub-keys gone', () {
      const src = '[a]\ndata = { only = "x" }\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'data', 'only']), isTrue);
      final out = doc.serialize();
      expect(out.contains('data'), isFalse);
      expect(out.contains('only'), isFalse);
    });

    test('removes quoted-key inline table entry', () {
      const src = '[errors]\n"404" = { title = "Not found" }\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['errors', '404', 'title']), isTrue);
      final out = doc.serialize();
      expect(out.contains('404'), isFalse);
    });

    test('keeps section header when sibling remains', () {
      const src = '[a]\nkeep = "x"\ndrop = "y"\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('[a]'), isTrue);
      expect(out.contains('keep'), isTrue);
    });

    test('preserves standalone comment after unrelated key removal', () {
      const src = '[a]\n# my comment\nkeep = "x"\ndrop = "y"\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('# my comment'), isTrue);
      expect(out.contains('keep'), isTrue);
      expect(out.contains('drop'), isFalse);
    });

    test('removes end-of-line comment with its key', () {
      const src = '[a]\ndrop = "y" # remove me\nkeep = "x"\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('remove me'), isFalse);
    });

    test('returns false for non-existent path', () {
      const src = '[a]\nkey = "v"\n';
      final doc = TranslationDocument.parse(src, 'toml');
      expect(doc.remove(['a', 'nope']), isFalse);
      expect(doc.remove(['b', 'key']), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// XML
// ---------------------------------------------------------------------------

void _xmlTests() {
  group('XmlDocument', () {
    test('parses and serializes nested elements', () {
      const src = '<root><a><b>val</b></a></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      final out = doc.serialize().replaceAll('\n', '');
      expect(out.contains('<a>'), isTrue);
      expect(out.contains('<b>'), isTrue);
    });

    test('parses declaration', () {
      const src = '<?xml version="1.0"?>\n<root><a>v</a></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.serialize().contains('<?xml'), isTrue);
    });

    test('removes single-line element', () {
      const src = '<root><keep>k</keep><drop>d</drop></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['drop']), isTrue);
      final out = doc.serialize().replaceAll('\n', '');
      expect(out.contains('<keep>'), isTrue);
      expect(out.contains('drop'), isFalse);
    });

    test('removes nested element', () {
      const src = '<root><a><keep>k</keep><drop>d</drop></a></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['a', 'drop']), isTrue);
      final out = doc.serialize().replaceAll('\n', '');
      expect(out.contains('<keep>'), isTrue);
      expect(out.contains('drop'), isFalse);
    });

    test('removes empty parent recursively', () {
      const src = '<root><x><y><z>leaf</z></y></x></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['x', 'y', 'z']), isTrue);
      final out = doc.serialize().replaceAll('\n', '');
      expect(out.contains('<x>'), isFalse);
      expect(out.contains('<y>'), isFalse);
      expect(out.contains('leaf'), isFalse);
    });

    test('keeps parent when sibling remains', () {
      const src = '<root><a><keep>k</keep><drop>d</drop></a></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['a', 'drop']), isTrue);
      final out = doc.serialize().replaceAll('\n', '');
      expect(out.contains('<a>'), isTrue);
      expect(out.contains('<keep>'), isTrue);
    });

    test('removes multi-line element with line range', () {
      const src = '<root>\n  <drop>\n    <child>v</child>\n  </drop>\n  <keep>k</keep>\n</root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['drop']), isTrue);
      final out = doc.serialize();
      expect(out.contains('drop'), isFalse);
      expect(out.contains('child'), isFalse);
      expect(out.contains('keep'), isTrue);
    });

    test('returns false for non-existent path', () {
      const src = '<root><a>v</a></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['b']), isFalse);
      expect(doc.remove(['a', 'b']), isFalse);
    });

    test('matches path under root element name', () {
      const src = '<root><a><b>v</b></a></root>';
      final doc = TranslationDocument.parse(src, 'xml');
      expect(doc.remove(['root', 'a', 'b']), isTrue);
      final out = doc.serialize().replaceAll('\n', '');
      expect(out.contains('a'), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Entry
// ---------------------------------------------------------------------------

void main() {
  _jsonTests();
  _yamlTests();
  _tomlTests();
  _xmlTests();
}
