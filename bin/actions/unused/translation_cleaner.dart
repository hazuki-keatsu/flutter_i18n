import 'dart:io';

import 'package:flutter_i18n/utils/message_printer.dart';

import 'editor/translation_document.dart';

/// Dispatches to a per-format [TranslationDocument] adapter based on file
/// extension, preserving comments and formatting during key removal.
class TranslationCleaner {
  static const _supported = {'json', 'yaml', 'yml', 'xml', 'toml'};

  /// Remove [keys] from [file]. Returns the number of keys removed.
  Future<int> clear(File file, Set<String> keys) async {
    final ext = file.path.split('.').last.toLowerCase();
    final format = ext == 'yml' ? 'yaml' : ext;
    if (!_supported.contains(ext)) return 0;

    try {
      final content = await file.readAsString();
      final doc = TranslationDocument.parse(content, format);

      var removed = 0;
      for (final key in keys) {
        if (doc.remove(key.split('.'))) {
          removed++;
        }
      }

      if (removed > 0) {
        await file.writeAsString(doc.serialize());
      }

      return removed;
    } catch (e) {
      MessagePrinter.error('Failed to clean ${file.path}: $e');
      return 0;
    }
  }
}
