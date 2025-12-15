import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/utils/message_printer.dart';

import 'flutter_i18n.dart';

/// Translation delegate that manage the new locale received from the framework
class FlutterI18nDelegate extends LocalizationsDelegate<FlutterI18n> {
  static FlutterI18n? _translationObject;
  Locale? currentLocale;

  FlutterI18nDelegate(
      {TranslationLoader? translationLoader,
      MissingTranslationHandler? missingTranslationHandler,
      String keySeparator = "."}) {
    _translationObject = FlutterI18n(
      translationLoader,
      keySeparator,
      missingTranslationHandler: missingTranslationHandler,
    );
  }

  @override
  bool isSupported(final Locale locale) {
    return true;
  }

  @override
  Future<FlutterI18n> load(final Locale locale) async {
    MessagePrinter.info("New locale: $locale");
    final TranslationLoader translationLoader =
        _translationObject!.translationLoader!;
    
    // Set the locale passed in by system (if it is forcedLocale，getter will return forcedLocale)
    translationLoader.locale = locale;
    
    // Obtain the actual effective locale (consider forcedLocale).
    final Locale effectiveLocale = translationLoader.locale!;
    
    // Check whether it need to load：
    // 1. The data is empty
    // 2. The actual locale is different from the last one
    final bool needsLoad = _translationObject!.decodedMap == null ||
        _translationObject!.decodedMap!.isEmpty ||
        translationLoader.loadedLocale != effectiveLocale;
    
    if (needsLoad) {
      await _translationObject!.load();
      translationLoader.markAsLoaded();
    }
    
    currentLocale = effectiveLocale;
    return _translationObject!;
  }

  @override
  bool shouldReload(final FlutterI18nDelegate old) {
    return currentLocale == null ||
        currentLocale != old.currentLocale;
  }
}
