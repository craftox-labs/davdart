import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'overflow_tip.dart';
import 'theme.dart';

/// The one section label: the small uppercase muted title above a group of
/// rows, with an optional [action] at the end and an optional hairline
/// [rule] under it. Style and spacing come from [TypeTokens.sectionLabelStyle].
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.action,
    this.rule = false,
    this.padding,
    this.upper = true,
  });

  final String text;
  final Widget? action;
  final bool rule;
  final EdgeInsets? padding;

  /// Uppercases the label; off for a title that keeps its own case.
  final bool upper;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final label = OverflowTip(
      upper ? text.toUpperCase() : text,
      style: t.type.sectionLabelStyle.copyWith(color: t.muted),
    );
    Widget row = action == null
        ? label
        : Row(
            children: [
              Expanded(child: label),
              action!,
            ],
          );
    if (rule) {
      row = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          SizedBox(height: t.space.xs),
          Container(height: t.borders.hairline, color: t.divider),
        ],
      );
    }
    return padding == null ? row : Padding(padding: padding!, child: row);
  }
}
