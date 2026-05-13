import 'dart:io';

import 'package:logging/logging.dart';

import 'actions/action_interface.dart';
import 'actions/diff_action.dart';
import 'actions/unused_action.dart';
import 'actions/validate_action.dart';

void main(final List<String> args) async {
  Logger.root.onRecord.listen((record) {
    final level = record.level.name.toUpperCase();
    stdout.writeln('[flutter_i18n $level]: ${record.message}');
  });
  Logger.root.level = Level.ALL;

  validateLength(args);
  final AbstractAction actionInterface = retrieveAction(args[0]);
  actionInterface.executeAction(args.sublist(1));
}

void validateLength(final List<String> args) {
  if (args.isEmpty) {
    throw Exception("Empty list of args");
  }
}

AbstractAction retrieveAction(final String action) {
  switch (action) {
    case 'validate':
      return ValidateAction();
    case 'diff':
      return DiffAction();
    case 'unused':
      return UnusedAction();
    default:
      throw Exception("Unrecognized arg: $action");
  }
}
