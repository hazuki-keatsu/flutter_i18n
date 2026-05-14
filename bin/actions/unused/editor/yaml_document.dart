import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'translation_document.dart';

class YamlDocument implements TranslationDocument {
  final YamlEditor _editor;

  YamlDocument._(this._editor);

  factory YamlDocument.parse(String content) {
    return YamlDocument._(YamlEditor(content));
  }

  @override
  bool remove(List<String> path) {
    if (path.isEmpty) return false;
    try {
      _editor.remove(path);
    } on ArgumentError {
      return false;
    }

    // Walk up removing empty parents
    for (var i = path.length - 1; i > 0; i--) {
      final parentPath = path.sublist(0, i);
      try {
        final node = _editor.parseAt(parentPath);
        if (node is YamlMap && node.nodes.isEmpty) {
          _editor.remove(parentPath);
        }
      } on ArgumentError {
        // parent already gone
      }
    }

    return true;
  }

  @override
  String serialize() => _editor.toString();
}
