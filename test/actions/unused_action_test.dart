import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../bin/actions/unused_action.dart';

/// Runs [action] and waits for async work to settle, then returns the action
/// for inspection of test hooks.
Future<UnusedAction> run(UnusedAction action, final List<String> params) async {
  action.executeAction(params);
  await Future.delayed(const Duration(milliseconds: 200));
  return action;
}

const _fixture = 'test/fixtures/unused';
const _i18nDir = '$_fixture/i18n';
const _i18nNsDir = '$_fixture/i18n_ns';
const _codeDir = '$_fixture/code';

void main() {
  group('UnusedAction', () {
    // -----------------------------------------------------------------------
    // String literal key scanning
    // -----------------------------------------------------------------------
    test('finds all string-literal keys in translate / I18nText / '
        'I18nPlural / fallbackKey', () async {
      final a = await run(UnusedAction(),
          ['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);

      // Keys used in main.dart:
      expect(a.testUsedKeys, contains('title'));
      expect(a.testUsedKeys, contains('label.main'));
      expect(a.testUsedKeys, contains('label.confirmDelete'));
      expect(a.testUsedKeys, contains('button.clickMe'));
      expect(a.testUsedKeys, contains('button.label.save'));
      expect(a.testUsedKeys, contains('button.label.discard'));
      expect(a.testUsedKeys, contains('errors.404.title'));
      expect(a.testUsedKeys, contains('errors.404.description'));
      expect(a.testUsedKeys, contains('errors.500.title'));

      // Plural stems from I18nPlural + FlutterI18n.plural:
      expect(a.testUsedPluralStems, contains('clicked.times'));

      // Unused keys (in en.json but NOT in main.dart):
      expect(a.testUnusedKeys, contains('unusedKey'));
      expect(a.testUnusedKeys, contains('alsoUnused.nestedOne'));
      expect(a.testUnusedKeys, contains('alsoUnused.nestedTwo'));
    });

    test('finds single-quoted string keys', () async {
      final a = await run(UnusedAction(),
          ['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);
      // Single-quoted in main.dart: 'label.confirmDelete', 'errors.404.title',
      //   'errors.500.title'
      expect(a.testUsedKeys, contains('label.confirmDelete'));
      expect(a.testUsedKeys, contains('errors.404.title'));
      expect(a.testUsedKeys, contains('errors.500.title'));
    });

    test('handles deeply nested keys in map', () async {
      final a = await run(UnusedAction(),
          ['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);
      expect(a.testUsedKeys, contains('button.label.save'));
      expect(a.testUsedKeys, contains('button.label.discard'));
      expect(a.testUsedKeys, contains('errors.404.title'));
      expect(a.testUsedKeys, contains('errors.404.description'));
    });

    test('handles keys containing numeric segments', () async {
      final a = await run(UnusedAction(),
          ['--asset=$_i18nDir', '--code=$_codeDir/main.dart']);
      expect(a.testUsedKeys, contains('errors.404.title'));
      expect(a.testUsedKeys, contains('errors.404.description'));
      expect(a.testUsedKeys, contains('errors.500.title'));
    });

    // -----------------------------------------------------------------------
    // Namespace layout
    // -----------------------------------------------------------------------
    test('detects namespace layout and prefixes keys', () async {
      // with_alias.dart uses "common.appName"
      final a = await run(UnusedAction(), [
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_alias.dart',
      ]);
      expect(a.testUsedKeys, contains('common.appName'));
      // Not used → unused:
      expect(a.testUnusedKeys, contains('common.appVersion'));
      expect(a.testUnusedKeys, contains('common.unusedCommonKey'));
    });

    test('handles flat + namespace mixed layout', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nDir',
        '--asset=$_i18nNsDir',
        '--code=$_codeDir',
      ]);
      // from flat: title, label.main etc.
      expect(a.testUsedKeys, contains('title'));
      expect(a.testUsedKeys, contains('label.main'));
      // from namespace:
      expect(a.testUsedKeys, contains('common.appName'));
      expect(a.testUsedKeys, contains('home.welcome'));
      // unused:
      expect(a.testUnusedKeys, contains('unusedKey'));
      expect(a.testUnusedKeys, contains('common.unusedCommonKey'));
    });

    // -----------------------------------------------------------------------
    // Import variants
    // -----------------------------------------------------------------------
    test('handles aliased import', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_alias.dart',
      ]);
      // i18n.FlutterI18n.translate and i18n.I18nText
      expect(a.testUsedKeys, contains('common.appName'));
    });

    test('handles show combinator', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_show.dart',
      ]);
      expect(a.testUsedKeys, contains('common.appName'));
      expect(a.testUsedKeys, contains('common.copyright'));
    });

    test('handles hide combinator', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_hide.dart',
      ]);
      expect(a.testUsedKeys, contains('home.welcome'));
      expect(a.testUsedKeys, contains('home.greeting'));
    });

    // -----------------------------------------------------------------------
    // Const variable resolution
    // -----------------------------------------------------------------------
    test('resolves const variable declared in same file', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nNsDir',
        '--code=$_codeDir/with_const.dart',
      ]);
      // static const String welcomeKey = "home.welcome"
      // → FlutterI18n.translate(context, welcomeKey) resolves
      expect(a.testUsedKeys, contains('home.welcome'));
    });

    // -----------------------------------------------------------------------
    // Uncheckable — interpolation & variables
    // -----------------------------------------------------------------------
    test('marks string interpolation as uncheckable', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nDir',
        '--code=$_codeDir/with_interpolation.dart',
      ]);
      // "home.$section.welcome" and "${section}.label.save" can't resolve
      expect(a.testUncheckable.length, 2);
      expect(a.testUncheckable.any((r) => r.snippet.contains('section')), isTrue);
      // These should NOT end up in usedKeys
      expect(a.testUsedKeys, isNot(contains('home.profile.welcome')));
    });

    test('marks variable args as uncheckable', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        File('${tmpDir.path}/en.json')
            .writeAsStringSync(json.encode({'hello': 'Hello'}));
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
        final a = await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        // Variable not const → uncheckable
        expect(a.testUncheckable.length, 1);
        expect(a.testUncheckable.first.snippet, contains('dynamicKey'));
        // "hello" is not marked used (variable, not string literal)
        expect(a.testUsedKeys, isNot(contains('hello')));
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
        final a = await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        // Stem tracked:
        expect(a.testUsedPluralStems, contains('clicked.times'));
        // clicked.times-0/1/2 all covered → not in unused
        expect(a.testUnusedKeys, isNot(contains('clicked.times-0')));
        expect(a.testUnusedKeys, isNot(contains('clicked.times-1')));
        expect(a.testUnusedKeys, isNot(contains('clicked.times-2')));
        // otherKey is unused
        expect(a.testUnusedKeys, contains('otherKey'));
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
        File('${tmpDir.path}/en.json')
            .writeAsStringSync(json.encode({'defined': 'ok'}));
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "missingKey"));
}
''');
        final a = await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(a.testMissingKeys, contains('missingKey'));
        expect(a.testUsedKeys, contains('missingKey'));
        // defined is not used → unused
        expect(a.testUnusedKeys, contains('defined'));
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
        File('${tmpDir.path}/en.json')
            .writeAsStringSync(json.encode({'hello': 'Hello'}));
        File('${tmpDir.path}/unrelated.dart')
            .writeAsStringSync('String greet() => "hello";');
        final a = await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        // No flutter_i18n import → no keys found in code
        expect(a.testUsedKeys, isEmpty);
        // en.json key is unused
        expect(a.testUnusedKeys, contains('hello'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    // -----------------------------------------------------------------------
    // Auto-clear — JSON
    // -----------------------------------------------------------------------
    test('auto-clear removes unused keys from JSON (flat)', () async {
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
        await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
          '--auto-clear',
        ]);
        final result = json.decode(i18nFile.readAsStringSync());
        expect(result.containsKey('used'), isTrue);
        expect(result.containsKey('unused'), isFalse);
        // nested parent stays as empty {} after leaf-key deletion
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
        await run(UnusedAction(), [
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
    // Auto-clear — YAML
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
        await run(UnusedAction(), [
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
    // Auto-clear — TOML
    // -----------------------------------------------------------------------
    test('auto-clear removes unused keys from TOML', () async {
      final tmpDir = Directory.systemTemp.createTempSync('flutter_i18n_test_');
      try {
        final i18nFile = File('${tmpDir.path}/en.toml');
        i18nFile.writeAsStringSync(
            'used = "used"\nunused = "unused"\n');
        File('${tmpDir.path}/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
class Foo extends StatelessWidget {
  Widget build(BuildContext c) => Text(FlutterI18n.translate(c, "used"));
}
''');
        await run(UnusedAction(), [
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
    // Auto-clear — XML
    // -----------------------------------------------------------------------
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
        await run(UnusedAction(), [
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
        final a = await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        expect(a.testUsedKeys, contains('used'));
        expect(a.testUnusedKeys, isEmpty);
        expect(a.testMissingKeys, isEmpty);
        expect(a.testUncheckable, isEmpty);
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
        final a = await run(UnusedAction(), [
          '--asset=${tmpDir.path}',
          '--code=${tmpDir.path}',
        ]);
        // key is used but not defined → missing
        expect(a.testMissingKeys, contains('key'));
        // No keys defined → unused is empty
        expect(a.testUnusedKeys, isEmpty);
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });

    test('all well-defined keys match with multi-file code', () async {
      final a = await run(UnusedAction(), [
        '--asset=$_i18nDir',
        '--asset=$_i18nNsDir',
        '--code=$_codeDir',
      ]);
      // All fixtures combined — no surprise failures
      expect(a.testUsedKeys, isNotEmpty);
      expect(a.testUnusedKeys, isNotEmpty);
      expect(a.testUsedPluralStems, isNotEmpty);
    });
  });
}
