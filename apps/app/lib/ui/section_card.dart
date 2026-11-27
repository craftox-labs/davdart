import 'package:flutter/widgets.dart';

import 'card_box.dart';
import 'section_label.dart';
import 'theme.dart';

/// A card with a [SectionLabel] heading (and optional [action] beside it)
/// above its [children]: the Home and project Overview blocks.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return CardBox(
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: t.space.xs,
        children: [
          SectionLabel(title, action: action),
          ...children,
        ],
      ),
    );
  }
}
