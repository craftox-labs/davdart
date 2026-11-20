import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../theme/tokens.dart';
import 'chips.dart';
import 'collapsible_section.dart';
import 'content_grid.dart';
import 'drag_drop.dart';
import 'note_menu.dart';
import 'task_parts.dart';
import 'theme.dart';
import 'overflow_tip.dart';

// A small "Today" strip on Home: Doing (notes) and Tasks (overdue, due today,
// next open). A pure view over AppState.filtered and AppState.tasks. To
// remove: delete this file, its tests and the one `HomeToday(...)` line in
// app.dart.

const _prefKey = 'davdart.home.today.collapsed.v1';
const _maxRows = 5;
const _maxTaskRows = 6;

class HomeToday extends StatefulWidget {
  const HomeToday({super.key, required this.state, this.now});
  final AppState state;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<HomeToday> createState() => _HomeTodayState();
}

class _HomeTodayState extends State<HomeToday> {
  static int _newest(Note a, Note b) {
    final x = a.lastModified, y = b.lastModified;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final all = [
          for (final n in state.filtered)
            if (!n.categories.any((c) => c.startsWith('kind-'))) n,
        ]..sort(_newest);
        final doing = [
          for (final n in all)
            if (PlanItem.fromNote(n).status == 'doing') n,
        ].take(_maxRows).toList();
        final now = widget.now ?? DateTime.now();
        final scope = state.scopeUid;
        final open = [
          for (final k in state.openTasks(now))
            if (scope == null || state.taskIsUnder(k, scope)) k,
        ];
        // Read-only Space without tasks: nothing to add, nothing to show.
        final showTasks = state.tasksEditable || state.tasks.isNotEmpty;
        if (doing.isEmpty && !showTasks) return const SizedBox.shrink();
        final panels = [
          if (doing.isNotEmpty)
            _Panel(
              'Doing',
              state,
              count: doing.length,
              rows: [
                for (final n in doing)
                  _Row(
                    key: Key('home-today-doing-${n.uid}'),
                    state: state,
                    note: n,
                  ),
              ],
            ),
          if (showTasks)
            _Panel(
              'Tasks',
              state,
              count: open.length,
              rows: [
                if (open.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(t.space.xs),
                    child: Text(
                      'No open tasks',
                      key: const Key('home-tasks-empty'),
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  ),
                for (final k in open.take(_maxTaskRows))
                  TaskRow(
                    key: Key('home-today-tasks-${k.uid}'),
                    state: state,
                    task: k,
                    now: now,
                  ),
              ],
              footer: state.tasksEditable || open.length > _maxTaskRows
                  ? Padding(
                      padding: EdgeInsets.only(top: t.space.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TaskQuickAdd(state: state),
                          if (state.tasks.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FTappable(
                                key: const Key('home-tasks-all'),
                                onPress: state.openTasksPanel,
                                child: Padding(
                                  padding: EdgeInsets.only(top: t.space.sm),
                                  child: Text(
                                    open.length > _maxTaskRows
                                        ? 'All tasks (${open.length} open)'
                                        : 'All tasks',
                                    style: t.type.captionStyle.copyWith(
                                      color: t.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : null,
            ),
        ];
        return ContentCap(
          child: Padding(
            key: const Key('home-today'),
            padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, 0),
            child: CollapsibleSection(
              id: 'home-today',
              title: 'Today',
              prefs: state.prefs,
              prefKey: _prefKey,
              child: Padding(
                padding: EdgeInsets.only(top: t.space.sm),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final gap = t.space.lg;
                    if (c.maxWidth < Tokens.stackBreakpoint) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < panels.length; i++) ...[
                            if (i > 0) SizedBox(height: gap),
                            panels[i],
                          ],
                        ],
                      );
                    }
                    // Always two half-width slots, so a lone panel keeps its
                    // place and lines up with the board columns below.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 2; i++) ...[
                          if (i > 0) SizedBox(width: gap),
                          Expanded(
                            child: i < panels.length
                                ? panels[i]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel(
    this.title,
    this.state, {
    required this.count,
    required this.rows,
    this.footer,
  });
  final String title;
  final AppState state;
  final int count;
  final List<Widget> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final slug = title.toLowerCase().replaceAll(' ', '-');
    return DecoratedBox(
      key: Key('home-today-$slug'),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.radii.card),
        border: Border.all(color: t.cardBorder),
      ),
      child: Padding(
        padding: EdgeInsets.all(t.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CollapsibleSection(
              id: 'home-today-$slug',
              title: title,
              upper: false,
              count: count,
              prefs: state.prefs,
              prefKey: 'davdart.home.today.$slug.collapsed.v1',
              headerPadding: EdgeInsets.all(t.space.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...rows, ?footer],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.state, required this.note});
  final AppState state;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = PlanItem.fromNote(note);
    final selected = state.peekUid == note.uid;
    return NoteContextMenu(
      state: state,
      uid: note.uid,
      child: NoteDraggable(
        uid: note.uid,
        source: NoteDragSource.list,
        label: note.summary,
        child: FTappable(
          onPress: () => state.clickNote(note.uid),
          child: Container(
            color: selected ? t.selected : null,
            padding: EdgeInsets.symmetric(
              horizontal: t.space.xs,
              vertical: t.space.sm,
            ),
            child: Row(
              children: [
                StatusDot(p.status),
                SizedBox(width: t.space.md),
                Expanded(child: OverflowTip(p.itemId ?? note.summary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
