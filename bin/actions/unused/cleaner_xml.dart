import 'dart:io';

import 'format_cleaner.dart';

class XmlCleaner extends FormatCleaner {
  @override
  Future<int> clear(File file, Set<String> keys) async {
    var content = await file.readAsString();
    var count = 0;

    for (final key in keys) {
      final leafKey = key.split('.').last;
      final previous = content;

      content = content.replaceAll(
          RegExp('<${RegExp.escape(leafKey)}[^>]*/>'), '');
      content = content.replaceAll(
          RegExp(
              '<${RegExp.escape(leafKey)}[^>]*>[^<]*</${RegExp.escape(leafKey)}>'),
          '');
      if (content != previous) count++;
    }

    // Upward cleanup: iteratively remove empty parent elements
    var changed = true;
    while (changed) {
      changed = false;
      final previous = content;
      content = content.replaceAll(RegExp(r'<(\w+)>\s*</\1>'), '');
      if (content != previous) {
        changed = true;
        count++;
      }
    }

    await file.writeAsString(content);
    return count;
  }
}
