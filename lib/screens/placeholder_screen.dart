import 'package:flutter/material.dart';

import '../core/layout.dart';
import '../core/strings.dart';
import '../widgets/ui.dart';

/// Holds a tab until its screen arrives in the next part of this phase. [first] and [second] are text keys.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.first, required this.second});

  final String first;
  final String second;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: Layout.page(context, top: 24, gutter: 20), children: [DisplayTitle(context.t(first), second: context.t(second))]);
  }
}
