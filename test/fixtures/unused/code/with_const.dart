// Uses const variable for translation key
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

class ProfileScreen extends StatelessWidget {
  static const String welcomeKey = "home.welcome";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(FlutterI18n.translate(context, welcomeKey)),
      ],
    );
  }
}