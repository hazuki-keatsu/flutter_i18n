// Aliased import, uses prefixed identifiers
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart' as i18n;

class SettingsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(i18n.FlutterI18n.translate(context, "common.appName")),
        i18n.I18nText("common.appName", child: Text("")),
      ],
    );
  }
}