import 'dart:io';

import 'cleaner_json.dart';
import 'cleaner_toml.dart';
import 'cleaner_xml.dart';
import 'cleaner_yaml.dart';
import 'format_cleaner.dart';

/// Dispatches to a per-format [FormatCleaner] adapter based on file extension.
class TranslationCleaner {
  static final _cleaners = <String, FormatCleaner>{
    'json': JsonCleaner(),
    'yaml': YamlCleaner(),
    'xml': XmlCleaner(),
    'toml': TomlCleaner(),
  };

  /// Remove [keys] from [file]. Returns the number of keys removed.
  Future<int> clear(File file, Set<String> keys) async {
    final ext = file.path.split('.').last.toLowerCase();
    final cleaner = _cleaners[ext];
    if (cleaner == null) return 0;
    return cleaner.clear(file, keys);
  }
}
