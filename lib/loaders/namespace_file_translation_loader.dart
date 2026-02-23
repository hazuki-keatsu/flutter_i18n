import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/loaders/decoders/base_decode_strategy.dart';
import 'package:flutter_i18n/loaders/file_translation_loader.dart';
import 'package:flutter_i18n/utils/message_printer.dart';

/// Loads translations from separate namespace files per locale directory.
/// Uses the same fallback hierarchy as [FileTranslationLoader]:
/// most-specific locale first, then less specific, then [fallbackDir].
class NamespaceFileTranslationLoader extends FileTranslationLoader {
  final String fallbackDir;
  final List<String>? namespaces;

  final Map<dynamic, dynamic> _decodedMap = {};

  NamespaceFileTranslationLoader(
      {required this.namespaces,
      this.fallbackDir = "en",
      String basePath = "assets/flutter_i18n",
      String separator = "_",
      Locale? forcedLocale,
      List<BaseDecodeStrategy>? decodeStrategies})
      : super(
            basePath: basePath,
            separator: separator,
            forcedLocale: forcedLocale,
            decodeStrategies: decodeStrategies) {
    assert(namespaces != null);
    assert(namespaces!.isNotEmpty);
  }

  /// Return the translation Map for the namespace
  @override
  Future<Map> load() async {
    locale = locale ?? await findDeviceLocale();
    MessagePrinter.info("The current locale is $locale");

    await Future.wait(
        namespaces!.map((namespace) => _loadTranslation(namespace)));

    return _decodedMap;
  }

  Future<void> _loadTranslation(String namespace) async {
    Map<dynamic, dynamic> loadedMap = {};

    for (final candidate in generateLocaleCandidates()) {
      try {
        final translationMap = await loadFile("$candidate/$namespace");
        if (translationMap.isNotEmpty) {
          loadedMap = deepMergeMaps(translationMap, loadedMap);
          MessagePrinter.debug('Loaded namespace $namespace from $candidate');
        }
      } catch (e) {
        MessagePrinter.debug('Namespace $candidate/$namespace not found, trying next candidate');
      }
    }

    if (!generateLocaleCandidates().contains(fallbackDir)) {
      try {
        final fallbackMap = await loadFile("$fallbackDir/$namespace");
        loadedMap = deepMergeMaps(fallbackMap, loadedMap);
        MessagePrinter.debug('Loaded namespace $namespace fallback from $fallbackDir');
      } catch (e) {
        MessagePrinter.debug('Error loading fallback $fallbackDir/$namespace: $e');
      }
    }

    _decodedMap[namespace] = loadedMap;
  }
}
