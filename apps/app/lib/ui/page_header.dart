import 'package:flutter/widgets.dart';

import 'overflow_tip.dart';
import 'theme.dart';

/// The desktop page header row under the tab strip: the page's title on the
/// left, then the page's own [switcher] pill right-aligned beside the page's
/// actions, so every page gives the pill the same place and the content below
/// starts straight away. The title gives up width first when the row is
/// tight (it truncates; the pill and the actions do not shrink).
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

  /// A page-level switcher (Home's views, a project's tabs), right-aligned
  /// beside the actions when a page has one. It is built with [compact] set
  /// when the row is too narrow for a full pill (the labels go into the
  /// tooltips), so the title never has to give up its place to fit it.
  final Widget Function(bool compact)? switcher;

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
      child: LayoutBuilder(
        builder: (context, c) {
          // A full pill needs roughly this much beside the actions; below it
          // the pill goes icon-only.
          final compact = c.maxWidth < t.sizes.headerPill;
          return Row(
            children: [
              Expanded(
                child: OverflowTip(
                  title,
                  textKey: textKey,
                  style: t.type.titleStyle.copyWith(color: t.paneTitleColor),
                ),
              ),
              if (switcher != null) ...[
                SizedBox(width: t.space.md),
                switcher!(compact),
                SizedBox(width: t.space.md),
              ],
              ...actions,
            ],
          );
        },
      ),
    );
  }
}
