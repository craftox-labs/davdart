import 'package:flutter/widgets.dart';

import 'overflow_tip.dart';
import 'theme.dart';

/// The desktop page header row under the tab strip: the page's title on the
/// left, an optional page-level switcher beside it and the page's actions on
/// the right. Home names its Space here; a project page its project.
///
/// The switcher slot is unused for now (the project's view switcher stays
/// below this row until its move is decided).
class PageHeaderRow extends StatelessWidget {
  const PageHeaderRow({
    super.key,
    required this.title,
    this.textKey,
    this.switcher,
    this.actions = const [],
  });

  final String title;

  /// Key for the title text (tests).
  final Key? textKey;

  /// A page-level switcher shown beside the title, when a page has one.
  final Widget? switcher;

  /// Page actions, right-aligned: reload, menus, view toggles.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      key: const Key('page-header'),
      height: t.sizes.paneHeader,
      padding: EdgeInsets.symmetric(horizontal: t.space.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.divider, width: t.borders.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OverflowTip(
              title,
              textKey: textKey,
              style: t.type.titleStyle,
            ),
          ),
          ?switcher,
          ...actions,
        ],
      ),
    );
  }
}
