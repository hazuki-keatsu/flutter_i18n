import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/loaders/decoders/base_decode_strategy.dart';
import 'package:flutter_i18n/loaders/decoders/json_decode_strategy.dart';
import 'package:flutter_i18n/loaders/decoders/toml_decode_strategy.dart';
import 'package:flutter_i18n/loaders/decoders/xml_decode_strategy.dart';
import 'package:flutter_i18n/loaders/decoders/yaml_decode_strategy.dart';
import 'package:flutter_i18n/loaders/file_content.dart';
import 'package:flutter_i18n/loaders/translation_loader.dart';

import '../utils/message_printer.dart';

/// Loads translation files from JSON, YAML or XML format.
///
/// File candidates are tried in order from most to least specific:
///   1. `lang_Script_Country` (e.g. `zh_Hans_CN`)
///   2. `lang_Country`        (e.g. `de_DE`)
///   3. `lang_Script`         (e.g. `zh_Hans`)
///   4. `lang`                (e.g. `de`)
///   5. [fallbackFile]        (e.g. `en`)
class FileTranslationLoader extends TranslationLoader implements IFileContent {
  final String? fallbackFile;
  final String basePath;
  final String separator;
  AssetBundle assetBundle = rootBundle;

  Map<dynamic, dynamic> _decodedMap = {};
  late List<BaseDecodeStrategy> _decodeStrategies;

  set decodeStrategies(List<BaseDecodeStrategy>? decodeStrategies) =>
      _decodeStrategies = decodeStrategies ??
          [
            JsonDecodeStrategy(),
            YamlDecodeStrategy(),
            XmlDecodeStrategy(),
            TomlDecodeStrategy()
          ];

  FileTranslationLoader(
      {this.fallbackFile = "en",
      this.basePath = "assets/flutter_i18n",
      this.separator = "_",
      Locale? forcedLocale,
      List<BaseDecodeStrategy>? decodeStrategies}) {
    this.forcedLocale = forcedLocale;
    this.decodeStrategies = decodeStrategies;
  }

  /// Return the translation Map
  @override
  Future<Map> load() async {
    _decodedMap = {};
    await _defineLocale();

    final candidateFiles = generateLocaleCandidates();
    Map<dynamic, dynamic> loadedMap = {};

    for (final candidateFile in candidateFiles) {
      final translationMap = await _loadTranslation(candidateFile, false);
      if (translationMap.isNotEmpty) {
        loadedMap = deepMergeMaps(translationMap, loadedMap);
        MessagePrinter.debug('Loaded translation file: $candidateFile');
      }
    }

    if (fallbackFile != null && !candidateFiles.contains(fallbackFile)) {
      final Map fallbackMap = await _loadTranslation(fallbackFile!, true);
      loadedMap = deepMergeMaps(fallbackMap, loadedMap);
      MessagePrinter.debug('Fallback maps have been merged');
    }
    return loadedMap;
  }

  /// Load the file using the AssetBundle rootBundle
  @override
  Future<String> loadString(final String fileName, final String extension) {
    return assetBundle.loadString('$basePath/$fileName.$extension',
        cache: !kDebugMode);
  }

  Future<Map<dynamic, dynamic>> _loadTranslation(
      String fileName, bool isFallback) async {
    try {
      return await loadFile(fileName);
    } catch (e) {
      if (isFallback) {
        MessagePrinter.debug('Error loading fallback translation $fileName: $e');
      } else {
        MessagePrinter.debug(
            'Translation file $fileName not found, trying next candidate');
      }
    }
    return {};
  }

  Future _defineLocale() async {
    locale = locale ?? await findDeviceLocale();
    MessagePrinter.info("The current locale is $locale");
  }

  @protected
  Map<K, V> deepMergeMaps<K, V>(
    Map<K, V> map1,
    Map<K, V> map2,
  ) {
    var result = Map<K, V>.of(map1);

    map2.forEach((key, mapValue) {
      var p1 = result[key] as V;
      var p2 = mapValue;

      V mapResult;
      if (result.containsKey(key)) {
        if (p1 is Map && p2 is Map) {
          Map map1 = p1;
          Map map2 = p2;
          mapResult = deepMergeMaps(map1, map2) as V;
        } else {
          mapResult = p2;
        }
      } else {
        mapResult = mapValue;
      }

      result[key] = mapResult;
    });
    return result;
  }

  /// Load the fileName using one of the strategies provided
  @protected
  Future<Map> loadFile(final String fileName) async {
    final List<Future<Map?>> strategiesFutures = _executeStrategies(fileName);
    final Stream<Map?> strategiesStream = Stream.fromFutures(strategiesFutures);
    return await strategiesStream.firstWhere((map) => map != null,
            orElse: null) ??
        {};
  }

  List<Future<Map?>> _executeStrategies(final String fileName) {
    return _decodeStrategies
        .map((decodeStrategy) => decodeStrategy.decode(fileName, this))
        .toList();
  }

  /// Returns locale file name candidates from most to least specific.
  @protected
  List<String> generateLocaleCandidates() {
    final lang = locale!.languageCode;
    final script = locale!.scriptCode;
    final country = locale!.countryCode;

    final candidates = <String>[];
    if (script != null && country != null) {
      candidates.add('$lang$separator$script$separator$country');
    }
    if (country != null) {
      candidates.add('$lang$separator$country');
    }
    if (script != null) {
      candidates.add('$lang$separator$script');
    }
    candidates.add(lang);
    return candidates;
  }
}
