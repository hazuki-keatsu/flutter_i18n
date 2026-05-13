// String interpolation — these should be flagged as uncheckable
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';

class InterpolationScreen extends StatelessWidget {
  final String section = "button";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Dynamic key: can't be statically analyzed
        Text(FlutterI18n.translate(context, "home.$section.welcome")),
        Text(FlutterI18n.translate(context, "${section}.label.save")),
      ],
    );
  }
}