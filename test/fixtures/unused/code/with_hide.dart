// import with 'hide' — I18nPlural is hidden
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart' hide I18nPlural;

class HideScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(FlutterI18n.translate(context, "home.welcome")),
        I18nText("home.greeting", child: Text("")),
      ],
    );
  }
}