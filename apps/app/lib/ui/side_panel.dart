import 'package:flutter/widgets.dart';

import 'parts.dart';
import 'theme.dart';

/// The shared frame of a side panel section: a header row with the section's
/// own [title] and [actions] (each section supplies both; nothing here knows
/// about notes, tasks or events), then the [body] filling the rest.
class SidePanelFrame extends StatelessWidget {
  const SidePanelFrame({
    super.key,
    required this.title,
    required this.body,
    this.actions,
  });

  /// The section's heading.
  final Widget title;

  /// The section's header actions, at the end of the row.
  final Widget? actions;

  /// The panel content below the header (it brings its own scrolling).
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaneHeaderRow(
          key: const Key('side-header'),
          startPad: t.space.xl + t.space.xxs,
          endPad: t.space.lg,
          children: [
            Expanded(child: title),
            ?actions,
          ],
        ),
        SizedBox(height: t.space.md),
        Expanded(child: body),
      ],
    );
  }
}

/// A section heading in the panel header.
class SidePanelTitle extends StatelessWidget {
  const SidePanelTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: tokensOf(context).type.headingStyle);
}
