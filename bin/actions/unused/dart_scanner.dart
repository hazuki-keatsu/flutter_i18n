import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

import 'analysis_result.dart';

/// Scans Dart source files for flutter_i18n translation key references.
///
/// Returns a [ScanResult] containing resolved string-literal keys, plural stems,
/// and unresolved references.
class DartScanner {
  final bool _verbose;

  DartScanner({bool verbose = false}) : _verbose = verbose;

  /// Scan [files] and return the resolved and unresolved keys found.
  Future<ScanResult> scan(final List<File> files) async {
    final usedKeys = <String, Set<String>>{};
    final pluralStems = <String>{};
    final uncheckable = <UnresolvedRef>[];

    for (final file in files) {
      final content = await file.readAsString();

      final importInfo = _parseImport(content);
      if (importInfo == null) {
        if (_verbose) {
          MessagePrinter.debug('${file.path} — no flutter_i18n import, skipped');
        }
        continue;
      }

      final constMap = _collectConstDeclarations(content);
      final path = file.path;
      final info = importInfo;
      final alias = info.alias;

      // translate → 2nd arg → usedKeys
      if (info.isApiAvailable('FlutterI18n')) {
        _matchCall(
            content,
            alias != null ? '$alias.FlutterI18n.translate' : 'FlutterI18n.translate',
            path,
            skipFirst: true,
            usedKeys: usedKeys,
            uncheckable: uncheckable,
            constMap: constMap);
        // plural → 2nd arg → pluralStems
        _matchCall(
            content,
            alias != null ? '$alias.FlutterI18n.plural' : 'FlutterI18n.plural',
            path,
            skipFirst: true,
            pluralStems: pluralStems,
            uncheckable: uncheckable,
            constMap: constMap);
      }
      // I18nText → 1st arg → usedKeys
      if (info.isApiAvailable('I18nText')) {
        _matchCall(content, alias != null ? '$alias.I18nText' : 'I18nText', path,
            skipFirst: false,
            usedKeys: usedKeys,
            uncheckable: uncheckable,
            constMap: constMap);
      }
      // I18nPlural → 1st arg → pluralStems
      if (info.isApiAvailable('I18nPlural')) {
        _matchCall(
            content, alias != null ? '$alias.I18nPlural' : 'I18nPlural', path,
            skipFirst: false,
            pluralStems: pluralStems,
            uncheckable: uncheckable,
            constMap: constMap);
      }

      _matchFallbackKey(content, path, usedKeys);
    }

    return ScanResult(usedKeys, pluralStems, uncheckable);
  }

  // ---------------------------------------------------------------------------
  // Pre-compiled regex patterns
  // ---------------------------------------------------------------------------

  static final _importRe =
      RegExp(r"""import\s+['"]package:flutter_i18n/flutter_i18n\.dart['"]"""
          r'(?:\s+as\s+(\w+))?'
          r'(?:\s+(show|hide)\s+([^;]+?))?'
          r'\s*;');

  static final _constRe = RegExp(
      "(?:static\\s+)?(?:const|final)\\s+String\\s+(\\w+)\\s*=\\s*['\"]([^'\"]+)['\"]");

  static final _fallbackKeyRe =
      RegExp("fallbackKey:\\s*'([^']+)'|fallbackKey:\\s*\"([^\"]+)\"");

  static final _singleQuoteRe = RegExp(r"^'([^'\\]*(?:\\.[^'\\]*)*)'");
  static final _doubleQuoteRe = RegExp(r'^"([^"\\\$]*(?:\\.[^"\\]*)*)"');
  static final _identRe = RegExp(r'^(\w+)');
  static final _prefixedIdentRe = RegExp(r'^(\w+)\.(\w+)');
  static final _interpolationCheckRe = RegExp(r'\$');

  // ---------------------------------------------------------------------------
  // Import parsing
  // ---------------------------------------------------------------------------

  _ImportInfo? _parseImport(final String content) {
    final match = _importRe.firstMatch(content);
    if (match == null) return null;

    final alias = match.group(1);
    final keyword = match.group(2); // 'show' or 'hide'
    final namesRaw = match.group(3);
    final isShow = keyword == null || keyword == 'show';
    final names = namesRaw != null
        ? namesRaw.split(',').map((s) => s.trim()).toSet()
        : <String>{};

    return _ImportInfo(alias: alias, isShow: isShow, names: names);
  }

  Map<String, String> _collectConstDeclarations(final String content) {
    final map = <String, String>{};
    for (final match in _constRe.allMatches(content)) {
      map[match.group(1)!] = match.group(2)!;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Unified call-site matcher
  // ---------------------------------------------------------------------------

  void _matchCall(
    final String content,
    final String target,
    final String filePath, {
    required final bool skipFirst,
    Map<String, Set<String>>? usedKeys,
    Set<String>? pluralStems,
    required final List<UnresolvedRef> uncheckable,
    required final Map<String, String> constMap,
  }) {
    final pattern =
        skipFirst ? '$target\\s*\\(\\s*[^,]+,\\s*' : '$target\\s*\\(\\s*';
    final re = RegExp(pattern);
    for (final match in re.allMatches(content)) {
      final start = match.end;
      final arg = _extractStringArg(content, start, constMap);
      if (arg != null) {
        if (usedKeys != null) {
          _addUsed(arg, filePath, usedKeys);
        } else if (pluralStems != null) {
          pluralStems.add(arg);
          if (_verbose) {
            MessagePrinter.info('[plural stem] $arg  ← $filePath');
          }
        }
      } else {
        _addUncheckable(content, start, filePath, uncheckable);
      }
    }
  }

  void _matchFallbackKey(final String content, final String filePath,
      final Map<String, Set<String>> usedKeys) {
    for (final match in _fallbackKeyRe.allMatches(content)) {
      final key = match.group(1) ?? match.group(2)!;
      _addUsed(key, filePath, usedKeys);
    }
  }

  // ---------------------------------------------------------------------------
  // Argument extraction
  // ---------------------------------------------------------------------------

  String? _extractStringArg(
      final String content, final int pos, final Map<String, String> constMap) {
    final remaining = content.substring(pos);

    // Single-quoted string
    var m = _singleQuoteRe.firstMatch(remaining);
    if (m != null) return m.group(1)!;

    // Double-quoted string — rejects interpolation
    m = _doubleQuoteRe.firstMatch(remaining);
    if (m != null) {
      final raw = m.group(1)!;
      if (_interpolationCheckRe.hasMatch(raw)) return null;
      return raw;
    }

    // Identifier — try const map
    m = _identRe.firstMatch(remaining);
    if (m != null) {
      final varName = m.group(1)!;
      final resolved = constMap[varName];
      if (resolved != null) return resolved;

      final prefixedM = _prefixedIdentRe.firstMatch(remaining);
      if (prefixedM != null) {
        final fullName = '${prefixedM.group(1)}.${prefixedM.group(2)}';
        return constMap[fullName] ?? constMap[prefixedM.group(2)!];
      }
    }

    return null;
  }

  void _addUsed(final String key, final String filePath,
      final Map<String, Set<String>> usedKeys) {
    usedKeys.putIfAbsent(key, () => <String>{}).add(filePath);
    if (_verbose) {
      MessagePrinter.info('[used] $key  ← $filePath');
    }
  }

  void _addUncheckable(final String content, final int pos,
      final String filePath, final List<UnresolvedRef> uncheckable) {
    final line = '\n'.allMatches(content.substring(0, pos)).length + 1;
    final snippet = _extractArgSnippet(content, pos);
    uncheckable.add(UnresolvedRef(filePath, line, snippet));
    if (_verbose) {
      MessagePrinter.info('[uncheckable] $filePath:$line — $snippet');
    }
  }

  String _extractArgSnippet(final String content, final int pos) {
    final remaining = content.substring(pos);

    var m = RegExp(r'^"([^"]*)"').firstMatch(remaining);
    if (m != null) return '"${m.group(1)}"';

    m = RegExp(r"^'([^']*)'").firstMatch(remaining);
    if (m != null) return "'${m.group(1)}'";

    m = RegExp(r'^(\w+(?:\.\w+)*)').firstMatch(remaining);
    if (m != null) return m.group(1)!;

    final end = (pos + 30).clamp(0, content.length);
    return content.substring(pos, end).replaceAll('\n', ' ').trim();
  }
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _ImportInfo {
  final String? alias;
  final bool isShow;
  final Set<String> names;
  _ImportInfo({this.alias, this.isShow = true, this.names = const {}});

  bool isApiAvailable(String symbol) {
    if (names.isEmpty) return true;
    if (isShow) return names.contains(symbol);
    return !names.contains(symbol);
  }
}

/// Result of scanning Dart source files for translation key usage.
class ScanResult {
  final Map<String, Set<String>> usedKeys;
  final Set<String> pluralStems;
  final List<UnresolvedRef> uncheckable;

  ScanResult(this.usedKeys, this.pluralStems, this.uncheckable);
}
