import 'json_document.dart';
import 'toml_document.dart';
import 'xml_document.dart';
import 'yaml_document.dart';

/// The form a comment takes in source.
enum CommentType { line, endOfLine }

/// A comment found in a translation file, with its position.
class SourceComment {
  final CommentType type;
  final String text; // without # or <!-- --> delimiters
  final int sourceLine; // 0-based line index in source
  const SourceComment(this.type, this.text, this.sourceLine);
}

/// Round-trip editable translation document.
///
/// Each format adapter parses a source string into an internal model that
/// tracks key paths and comment positions. Keys can be removed by path and
/// the document serialized back to a string, preserving comments on
/// surviving keys.
abstract class TranslationDocument {
  factory TranslationDocument.parse(String content, String format) {
    switch (format) {
      case 'json':
        return JsonDocument.parse(content);
      case 'yaml':
        return YamlDocument.parse(content);
      case 'toml':
        return TomlDocument.parse(content);
      case 'xml':
        return XmlDocument.parse(content);
      default:
        throw ArgumentError('Unsupported format: $format');
    }
  }

  /// Remove the key at [path] and any ancestors that become empty.
  /// Returns true if the key was found and removed.
  bool remove(List<String> path);

  /// Serialize the document back to a string.
  String serialize();
}
