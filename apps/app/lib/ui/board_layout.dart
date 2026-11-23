import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'chips.dart';
import 'collapsible_section.dart';
import 'content_grid.dart';
import 'key_nav_ui.dart';
import 'theme.dart';

/// The status whose accordion section starts open: doing, else the first
/// status with items.
String boardDefaultOpen<T>(List<(String, List<T>)> cols) =>
    cols.any((c) => c.$1 == 'doing' && c.$2.isNotEmpty)
    ? 'doing'
    : cols.firstWhere((c) => c.$2.isNotEmpty, orElse: () => cols.first).$1;

/// The shared layout of the note board and the task board, so the two stay
/// identical: equal columns across a wide screen (fixed-width columns that
/// scroll sideways when they would be narrower than [Tokens.sizes]
/// `boardColumn`), and on a phone one column with a collapsible section per
/// status and title-only cards.
///
/// [itemBuilder] builds one card; [compact] is true in the phone sections.
/// [wrap] lets a board make a column or section a drop target or give it a
/// menu. [openMap] remembers which phone sections the user opened or closed.
/// [onAccordion] is told whether the phone layout is showing (the keyboard
/// grid needs to know). [embedded] sizes the phone layout to its content so a
/// parent scroll view carries it.
class BoardLayout<T> extends StatelessWidget {
  const BoardLayout({
    super.key,
    required this.cols,
    required this.itemBuilder,
    required this.openMap,
    this.wrap,
    this.dot,
    this.onAccordion,
    this.embedded = false,
  });

  final List<(String, List<T>)> cols;
  final Widget Function(String column, T item, bool compact) itemBuilder;
  final Map<String, bool> openMap;
  final Widget Function(String column, Widget child)? wrap;

  /// The status shown by a column's dot (null for none); the column name by
  /// default.
  final String? Function(String column)? dot;
  final void Function(bool accordion)? onAccordion;
  final bool embedded;

  Widget _wrap(String name, Widget child) =>
      wrap == null ? child : wrap!(name, child);

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final gap = t.space.lg;
    String? dotOf(String n) => dot == null ? n : dot!(n);
    Widget column(String name, List<T> items) => _wrap(
      name,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.space.xs,
              t.space.xs,
              t.space.xs,
              t.space.md,
            ),
            child: Row(
              children: [
                StatusDot(dotOf(name)),
                SizedBox(width: t.space.md),
                Text(
                  name.toUpperCase(),
                  style: t.type.labelStyle.copyWith(
                    fontSize: t.type.caption,
                    color: t.muted,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Text(
                  '${items.length}',
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: fabInset(context)),
              scrollCacheExtent: navCacheExtent,
              children: [for (final i in items) itemBuilder(name, i, false)],
            ),
          ),
        ],
      ),
    );
    onAccordion?.call(false);
    if (MediaQuery.sizeOf(context).width < Tokens.stackBreakpoint) {
      final open = boardDefaultOpen(cols);
      onAccordion?.call(true);
      return ListView(
        key: const Key('board-accordion'),
        shrinkWrap: embedded,
        physics: embedded ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.all(gap)
            .copyWith(bottom: gap + (embedded ? 0 : fabInset(context))),
        children: [
          for (final (name, items) in cols)
            _wrap(
              name,
              CollapsibleSection(
                key: ValueKey('board-acc-$name'),
                id: 'board-acc-$name',
                title: name,
                count: items.length,
                initiallyCollapsed: !(openMap[name] ?? name == open),
                onChanged: (collapsed) => openMap[name] = !collapsed,
                leading: StatusDot(dotOf(name)),
                headerPadding: EdgeInsets.only(bottom: t.space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final i in items) itemBuilder(name, i, true)],
                ),
              ),
            ),
        ],
      );
    }
    return ContentCap(
      child: LayoutBuilder(
        builder: (context, c) {
          final avail = c.maxWidth - 2 * gap;
          final each = (avail - (cols.length - 1) * gap) / cols.length;
          final fits = each >= t.sizes.boardColumn;
          if (fits) {
            // Equal columns share the full width; gutters sit between them.
            return Padding(
              padding: EdgeInsets.all(gap),
              child: Row(
                children: [
                  for (var i = 0; i < cols.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(child: column(cols[i].$1, cols[i].$2)),
                  ],
                ],
              ),
            );
          }
          // Too narrow for the minimum: fixed-width columns that scroll.
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(gap),
            children: [
              for (var i = 0; i < cols.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(
                  width: t.sizes.boardColumn,
                  child: column(cols[i].$1, cols[i].$2),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
