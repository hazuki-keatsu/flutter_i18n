// import with 'show' — only FlutterI18n is imported, not I18nText/I18nPlural
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart' show FlutterI18n;

class ShowScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(FlutterI18n.translate(context, "common.appName")),
        Text(FlutterI18n.translate(context, "common.copyright")),
        // common.appVersion is deliberately NOT used here — should be unused
      ],
    );
  }
}