// Direct import — covers translate, I18nText, I18nPlural, fallbackKey,
// single-quoted keys, deeply nested keys, keys with numbers
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(FlutterI18n.translate(context, "title")),                // top-level key
        I18nText("label.main", child: Text("")),                      // I18nText
        Text(FlutterI18n.translate(context, "button.clickMe",
            fallbackKey: "label.main")),                               // fallbackKey
        I18nPlural("clicked.times", 1),                                // I18nPlural stem
        Text(FlutterI18n.plural(context, "clicked.times", 2)),        // FlutterI18n.plural stem

        // Single-quoted string keys
        I18nText('label.confirmDelete', child: Text("")),
        Text(FlutterI18n.translate(context, 'errors.404.title')),
        Text(FlutterI18n.translate(context, 'errors.500.title')),

        // Deeply nested keys
        Text(FlutterI18n.translate(context, "button.label.save")),
        Text(FlutterI18n.translate(context, "button.label.discard")),

        // Key with numbers
        Text(FlutterI18n.translate(context, "errors.404.description")),
      ],
    );
  }
}