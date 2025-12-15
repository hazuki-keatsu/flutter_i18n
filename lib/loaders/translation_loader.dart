import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/utils/message_printer.dart';

/// Contains the common loading logic
abstract class TranslationLoader {
  /// Load method to implement
  Future<Map> load();

  Locale? _forcedLocale, _locale;
  
  /// Tracks the locale that was actually loaded (used to avoid redundant loads)
  Locale? _loadedLocale;

  /// Used to force the locale to load
  set forcedLocale(Locale? forcedLocale) => _forcedLocale = forcedLocale;
  
  /// Check if forcedLocale is set
  bool get hasForcedLocale => _forcedLocale != null;

  /// Currently locale used by the library
  Locale? get locale => _forcedLocale ?? _locale;

  /// New locale to load, due to system language change
  set locale(Locale? locale) => _locale = locale;
  
  /// The locale that was actually loaded last time
  Locale? get loadedLocale => _loadedLocale;
  
  /// Mark the current effective locale as loaded
  void markAsLoaded() => _loadedLocale = locale;

  /// Return the device current locale
  Future<Locale> findDeviceLocale() async {
    final systemLocale = PlatformDispatcher.instance.locale;
    MessagePrinter.info("The system locale is $systemLocale");
    return Future.value(systemLocale);
  }
}
