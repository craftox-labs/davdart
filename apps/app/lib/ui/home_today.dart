import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../theme/tokens.dart';
import 'chips.dart';
import 'drag_drop.dart';
import 'note_menu.dart';
import 'theme.dart';

// A small "Today" strip on Home: Doing and Recently changed. A pure view over
// AppState.filtered. To remove: delete this file, its tests and the one
// `HomeToday(...)` line in app.dart.

const _prefKey = 'davdart.home.today.collapsed.v1';
const _maxRows = 5;

/// Short age: 'now', '5m', '2h', 'yesterday', '3d', '2w'.
String shortAge(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 14) return '${d.inDays}d';
  return '${d.inDays ~/ 7}w';
}

class HomeToday extends StatefulWidget {
  const HomeToday({super.key, required this.state, this.now});
  final AppState state;

  /// Clock override for tests.
  final DateTime? now;

  @override
  State<HomeToday> createState() => _HomeTodayState();
}

class _HomeTodayState extends State<HomeToday> {
  late bool _collapsed = widget.state.prefs?.read(_prefKey) == 'true';

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    final p = widget.state.prefs;
    if (_collapsed) {
      p?.write(_prefKey, 'true');
    } else {
      p?.remove(_prefKey);
    }
  }

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
        final recent = all.take(_maxRows).toList();
        if (doing.isEmpty && recent.isEmpty) return const SizedBox.shrink();
        final now = widget.now ?? DateTime.now().toUtc();
        final panels = [
          if (doing.isNotEmpty) _Panel('Doing', doing, state, now, false),
          if (recent.isNotEmpty)
            _Panel('Recently changed', recent, state, now, true),
        ];
        return Padding(
          key: const Key('home-today'),
          padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FTappable(
                key: const Key('home-today-toggle'),
                semanticsLabel: _collapsed ? 'Expand Today' : 'Collapse Today',
                onPress: _toggle,
                child: Row(
                  children: [
                    Icon(
                      _collapsed
                          ? FLucideIcons.chevronRight
                          : FLucideIcons.chevronDown,
                      size: t.icons.lg,
                      color: t.muted,
                    ),
                    SizedBox(width: t.space.sm),
                    Text(
                      'TODAY',
                      style: t.type.labelStyle.copyWith(
                        fontSize: t.type.caption,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_collapsed) ...[
                SizedBox(height: t.space.sm),
                LayoutBuilder(
                  builder: (context, c) {
                    final stack = c.maxWidth < Tokens.stackBreakpoint;
                    final gap = t.space.lg;
                    if (stack) {
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
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < panels.length; i++) ...[
                          if (i > 0) SizedBox(width: gap),
                          Expanded(child: panels[i]),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel(this.title, this.rows, this.state, this.now, this.showAge);
  final String title;
  final List<Note> rows;
  final AppState state;
  final DateTime now;
  final bool showAge;

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
            Padding(
              padding: EdgeInsets.all(t.space.xs),
              child: Row(
                children: [
                  Text(
                    title,
                    style: t.type.labelStyle.copyWith(
                      fontSize: t.type.caption,
                      color: t.muted,
                    ),
                  ),
                  SizedBox(width: t.space.sm),
                  Text(
                    '${rows.length}',
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
            for (final n in rows)
              _Row(
                key: Key('home-today-$slug-${n.uid}'),
                state: state,
                note: n,
                age: showAge ? shortAge(n.lastModified, now) : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.state, required this.note, this.age});
  final AppState state;
  final Note note;
  final String? age;

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
                Expanded(
                  child: Text(
                    p.itemId ?? note.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (age != null && age!.isNotEmpty) ...[
                  SizedBox(width: t.space.md),
                  Text(
                    age!,
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
