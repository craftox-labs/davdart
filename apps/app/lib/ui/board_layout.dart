import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

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
/// How many cards the done column or section shows before "Show all".
const boardDoneCap = 10;

/// The [openMap] key that remembers the done column was expanded.
const boardDoneAllKey = 'done#all';

/// The column shown for [name]: done is ordered newest first by [modified]
/// and cut to [boardDoneCap] unless [showAll]. Other columns pass through.
List<T> boardCapped<T>(
  String name,
  List<T> items,
  DateTime? Function(T item) modified, {
  bool showAll = false,
}) {
  if (name != 'done') return items;
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final sorted = [...items]
    ..sort((a, b) => (modified(b) ?? epoch).compareTo(modified(a) ?? epoch));
  return showAll || sorted.length <= boardDoneCap
      ? sorted
      : sorted.sublist(0, boardDoneCap);
}

class BoardLayout<T> extends StatefulWidget {
  const BoardLayout({
    super.key,
    required this.cols,
    required this.itemBuilder,
    required this.openMap,
    required this.modified,
    this.wrap,
    this.dot,
    this.onAccordion,
    this.onShowAll,
    this.embedded = false,
  });

  final List<(String, List<T>)> cols;
  final Widget Function(String column, T item, bool compact) itemBuilder;
  final Map<String, bool> openMap;

  /// Last-modified time of an item; orders the done column.
  final DateTime? Function(T item) modified;
  final Widget Function(String column, Widget child)? wrap;

  /// The status shown by a column's dot (null for none); the column name by
  /// default.
  final String? Function(String column)? dot;
  final void Function(bool accordion)? onAccordion;
  final bool embedded;

  /// Called after "Show all" or "Show fewer" changed what the done column
  /// lists (the keyboard grid republishes its rows).
  final VoidCallback? onShowAll;

  @override
  State<BoardLayout<T>> createState() => _BoardLayoutState<T>();
}

class _BoardLayoutState<T> extends State<BoardLayout<T>> {
  Widget _wrap(String name, Widget child) =>
      widget.wrap == null ? child : widget.wrap!(name, child);

  bool get _all => widget.openMap[boardDoneAllKey] ?? false;

  void _setAll(bool v) {
    setState(() {
      if (v) {
        widget.openMap[boardDoneAllKey] = true;
      } else {
        widget.openMap.remove(boardDoneAllKey);
      }
    });
    widget.onShowAll?.call();
  }

  /// The "Show all (X)" / "Show fewer" control under a capped done column.
  Widget _more(String name, int total) {
    final t = tokensOf(context);
    if (name != 'done' || total <= boardDoneCap) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: FButton(
        key: Key(_all ? 'board-done-show-fewer' : 'board-done-show-all'),
        variant: FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        onPress: () => _setAll(!_all),
        child: Text(_all ? 'Show fewer' : 'Show all ($total)'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final onAccordion = widget.onAccordion;
    final embedded = widget.embedded;
    final openMap = widget.openMap;
    final itemBuilder = widget.itemBuilder;
    final dot = widget.dot;
    // Empty Backlog stays hidden by the callers; done is capped here. A done
    // column back at the cap or under it forgets "Show all".
    if (_all &&
        widget.cols.every(
          (c) => c.$1 != 'done' || c.$2.length <= boardDoneCap,
        )) {
      widget.openMap.remove(boardDoneAllKey);
    }
    final full = widget.cols;
    final cols = [
      for (final (n, items) in full)
        (n, boardCapped(n, items, widget.modified, showAll: _all)),
    ];
    final totals = {for (final (n, items) in full) n: items.length};
    final gap = t.space.lg;
    String? dotOf(String n) => dot == null ? n : dot(n);
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
                  '${totals[name]}',
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: fabInset(context)),
              scrollCacheExtent: navCacheExtent,
              children: [
                for (final i in items) itemBuilder(name, i, false),
                _more(name, totals[name] ?? 0),
              ],
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
                count: totals[name],
                initiallyCollapsed: !(openMap[name] ?? name == open),
                onChanged: (collapsed) => openMap[name] = !collapsed,
                leading: StatusDot(dotOf(name)),
                headerPadding: EdgeInsets.only(bottom: t.space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final i in items) itemBuilder(name, i, true),
                    _more(name, totals[name] ?? 0),
                  ],
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
