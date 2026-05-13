import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/actions/unused_action.dart';

const _fixture = 'test/fixtures/unused';
const _i18nDir = '$_fixture/i18n';
const _i18nNsDir = '$_fixture/i18n_ns';
const _codeDir = '$_fixture/code';

void main() {
  group('UnusedAction', () {
    // -----------------------------------------------------------------------
    // String literal key scanning
    // -----------------------------------------------------------------------
    test('finds all string-literal keys', () async {
      final r = await UnusedAction()
          .analyze(['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);

      expect(r.usedKeys.keys, containsAll([
            'title', 'label.main', 'label.confirmDelete', 'button.clickMe',
            'button.label.save', 'button.label.discard', 'errors.404.title',
            'errors.404.description', 'errors.500.title',
          ]));
      expect(r.usedPluralStems, contains('clicked.times'));
      expect(r.unusedKeys, containsAll([
            'unusedKey', 'alsoUnused.nestedOne', 'alsoUnused.nestedTwo',
          ]));
    });

    test('finds single-quoted string keys', () async {
      final r = await UnusedAction()
          .analyze(['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);
      expect(r.usedKeys.keys, contains('label.confirmDelete'));
      expect(r.usedKeys.keys, contains('errors.404.title'));
    });

    test('handles deeply nested keys', () async {
      final r = await UnusedAction()
          .analyze(['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);
      expect(r.usedKeys.keys, contains('button.label.save'));
      expect(r.usedKeys.keys, contains('errors.404.description'));
    });

    test('handles keys containing numeric segments', () async {
      final r = await UnusedAction()
          .analyze(['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);
      expect(r.usedKeys.keys, contains('errors.404.title'));
      expect(r.usedKeys.keys, contains('errors.500.title'));
    });

    // -----------------------------------------------------------------------
    // Namespace layout
    // -----------------------------------------------------------------------
    test('detects namespace layout and prefixes keys', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_alias.dart',
      ]);
      expect(r.usedKeys.keys, contains('common.appName'));
      expect(r.unusedKeys, contains('common.appVersion'));
      expect(r.unusedKeys, contains('common.unusedCommonKey'));
    });

    // -----------------------------------------------------------------------
    // Import variants
    // -----------------------------------------------------------------------
    test('handles aliased import', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_alias.dart',
      ]);
      expect(r.usedKeys.keys, contains('common.appName'));
    });

    test('handles show combinator', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_show.dart',
      ]);
      expect(r.usedKeys.keys, containsAll(['common.appName', 'common.copyright']));
    });

    test('handles hide combinator', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_hide.dart',
      ]);
      expect(r.usedKeys.keys, containsAll(['home.welcome', 'home.greeting']));
    });

    // -----------------------------------------------------------------------
    // Const variable resolution
    // -----------------------------------------------------------------------
    test('resolves const variable declared in same file', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_const.dart',
      ]);
      expect(r.usedKeys.keys, contains('home.welcome'));
    });

    // -----------------------------------------------------------------------
    // Uncheckable
    // -----------------------------------------------------------------------
    test('marks string interpolation as uncheckable', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nDir',
        '--code=$_codeDir/with_interpolation.dart',
      ]);
      expect(r.uncheckable.length, 2);
      expect(r.uncheckable.any((x) => x.snippet.contains('section')), isTrue);
      expect(r.usedKeys.keys, isNot(contains('home.profile.welcome')));
    });

    test('marks variable args as uncheckable', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json').writeAsStringSync(
            json.encode({'hello': 'Hello'}));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) {
    var dynamicKey = "hello";
    return Text(FlutterI18n.translate(c, dynamicKey));
  }
}
''');
        final r = await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(r.uncheckable.length, 1);
        expect(r.uncheckable.first.snippet, contains('dynamicKey'));
        expect(r.usedKeys.keys, isNot(contains('hello')));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Plural stem matching
    // -----------------------------------------------------------------------
    test('plural stem covers all -N suffixed keys', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json').writeAsStringSync(json.encode({
          'clicked': {'times-0': 'zero', 'times-1': 'one', 'times-2': 'two'},
          'otherKey': 'unused',
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) {
    return Column(children: [
      I18nPlural("clicked.times", 1),
      Text(FlutterI18n.plural(c, "clicked.times", 2)),
    ]);
  }
}
''');
        final r = await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(r.usedPluralStems, contains('clicked.times'));
        expect(r.unusedKeys, isNot(contains('clicked.times-0')));
        expect(r.unusedKeys, isNot(contains('clicked.times-1')));
        expect(r.unusedKeys, isNot(contains('clicked.times-2')));
        expect(r.unusedKeys, contains('otherKey'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Missing key detection
    // -----------------------------------------------------------------------
    test('detects keys used in code but missing from translation files',
        () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json').writeAsStringSync(
            json.encode({'defined': 'ok'}));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "missingKey"));
}
''');
        final r = await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(r.missingKeys, contains('missingKey'));
        expect(r.usedKeys.keys, contains('missingKey'));
        expect(r.unusedKeys, contains('defined'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Skip unrelated files
    // -----------------------------------------------------------------------
    test('skips files without flutter_i18n import', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json').writeAsStringSync(
            json.encode({'hello': 'Hello'}));
        File('${tmpDir.path}/unrelated.dart')
            .writeAsStringSync('String greet() => "hello";');
        final r = await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(r.usedKeys, isEmpty);
        expect(r.unusedKeys, contains('hello'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Auto-clear — JSON
    // -----------------------------------------------------------------------
    test('auto-clear removes unused keys from JSON', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'used': 'used',
          'unused': 'unused',
          'nested': {'inner': 'also unused'},
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "used"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('used'), isTrue);
        expect(result.containsKey('unused'), isFalse);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('auto-clear removes deeply nested unused keys from JSON', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'a': {'b': {'c': 'used', 'd': 'unused'}},
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "a.b.c"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result['a']['b'].containsKey('c'), isTrue);
        expect(result['a']['b'].containsKey('d'), isFalse);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Auto-clear — other formats
    // -----------------------------------------------------------------------
    test('auto-clear removes unused keys from YAML', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.yaml');
        i18nFile.writeAsStringSync(
            'used: "used value"\nunused: "unused value"\n');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "used"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('unused'), isFalse);
        expect(content.contains('used'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('auto-clear removes unused keys from TOML', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.toml');
        i18nFile.writeAsStringSync('used = "used"\nunused = "unused"\n');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "used"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('unused'), isFalse);
        expect(content.contains('used'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('auto-clear removes unused keys from XML', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.xml');
        i18nFile.writeAsStringSync(
            '<root><used>ok</used><unused>remove</unused></root>');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "used"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('unused'), isFalse);
        expect(content.contains('used'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Edge cases
    // -----------------------------------------------------------------------
    test('reports clean when all keys are used', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json')
            .writeAsStringSync(json.encode({'used': 'used'}));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "used"));
}
''');
        final r = await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(r.usedKeys.keys, contains('used'));
        expect(r.unusedKeys, isEmpty);
        expect(r.missingKeys, isEmpty);
        expect(r.uncheckable, isEmpty);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('empty translation file handled gracefully', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json').writeAsStringSync('{}');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "key"));
}
''');
        final r = await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(r.missingKeys, contains('key'));
        expect(r.unusedKeys, isEmpty);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('mixed flat + namespace layout', () async {
      final r = await UnusedAction().analyze([
        '--asset=$_i18nDir',
        '--asset=$_i18nNsDir',
        '--code=$_codeDir',
      ]);
      expect(r.usedKeys.keys, containsAll(['title', 'common.appName', 'home.welcome']));
      expect(r.unusedKeys, containsAll(['unusedKey', 'common.unusedCommonKey']));
    });

    // -----------------------------------------------------------------------
    // Upward recursive empty-parent cleanup — JSON
    // -----------------------------------------------------------------------
    test('JSON: removes empty parent after deleting only child', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'label': {'unused': 'remove me'},
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "other"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('label'), isFalse);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('JSON: recursively removes empty ancestors up to root', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'a': {
            'b': {'c': 'unused'},
          },
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "other"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('a'), isFalse);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('JSON: keeps parent when sibling is still used', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'group': {
            'keep': 'used',
            'unused': 'remove me',
          },
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "group.keep"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('group'), isTrue);
        expect(result['group'].containsKey('keep'), isTrue);
        expect(result['group'].containsKey('unused'), isFalse);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Upward recursive empty-parent cleanup — YAML
    // -----------------------------------------------------------------------
    test('YAML: removes empty parent keys recursively', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.yaml');
        i18nFile.writeAsStringSync(''
            'group:\n'
            '  subgroup:\n'
            '    unused: "remove me"\n'
            'other: "keep"\n');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "other"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('group'), isFalse);
        expect(content.contains('subgroup'), isFalse);
        expect(content.contains('unused'), isFalse);
        expect(content.contains('other'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('YAML: keeps parent when sibling remains', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.yaml');
        i18nFile.writeAsStringSync(''
            'group:\n'
            '  keep: "used"\n'
            '  unused: "remove me"\n');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "group.keep"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('group:'), isTrue);
        expect(content.contains('keep'), isTrue);
        expect(content.contains('unused'), isFalse);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Upward recursive empty-parent cleanup — XML
    // -----------------------------------------------------------------------
    test('XML: removes empty parent elements recursively', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.xml');
        i18nFile.writeAsStringSync(
            '<root><group><child>unused</child></group><keep>used</keep></root>');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "keep"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('group'), isFalse);
        expect(content.contains('child'), isFalse);
        expect(content.contains('keep'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Upward recursive empty-parent cleanup — TOML
    // -----------------------------------------------------------------------
    test('TOML: removes empty parent sections recursively', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.toml');
        i18nFile.writeAsStringSync(''
            '[group]\n'
            'unused = "remove me"\n'
            '\n'
            '[other]\n'
            'keep = "stay"\n');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "other.keep"));
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final content = i18nFile.readAsStringSync();
        expect(content.contains('[group]'), isFalse);
        expect(content.contains('unused'), isFalse);
        expect(content.contains('[other]'), isTrue);
        expect(content.contains('keep'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // --force gate when unresolvable references exist
    // -----------------------------------------------------------------------
    test('--auto-clear refuses when unresolvable exist and no --force',
        () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'used': 'ok',
          'unused': 'should stay',
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) {
    final key = "used";
    return Text(FlutterI18n.translate(c, key));
  }
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('unused'), isTrue);
        expect(result.containsKey('used'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('--auto-clear --force proceeds despite unresolvable', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.json');
        i18nFile.writeAsStringSync(json.encode({
          'keep': 'ok',
          'unused': 'remove me',
        }));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) {
    final dynamicKey = c.toString();
    return Column(children: [
      Text(FlutterI18n.translate(c, "keep")),
      Text(FlutterI18n.translate(c, dynamicKey)),
    ]);
  }
}
''');
        await UnusedAction().analyze([
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
          '--force',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('unused'), isFalse);
        expect(result.containsKey('keep'), isTrue);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });
}
