import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'chips.dart';
import 'theme.dart';

class BoardView extends StatelessWidget {
  const BoardView({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    if (state.error != null && state.notes.isEmpty) {
      return Center(
        child: Text(state.error!, style: TextStyle(color: t.muted)),
      );
    }
    final cols = state.columns;
    if (cols.isEmpty && !state.loading) {
      return Center(
        child: Text('No notes', style: TextStyle(color: t.muted)),
      );
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.all(t.space.lg),
      children: [
        for (final (name, notes) in cols)
          Container(
            width: t.sizes.boardColumn,
            margin: EdgeInsets.only(right: t.space.lg),
            child: Column(
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
                      StatusDot(name == 'notes' ? null : name),
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
                        '${notes.length}',
                        style: t.type.captionStyle.copyWith(color: t.muted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final n in notes) _Card(state: state, note: n),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.state, required this.note});
  final AppState state;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final p = PlanItem.fromNote(note);
    final selected = state.selectedUid == note.uid;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.md),
      child: FTappable(
        onPress: () => state.select(note.uid),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.radii.card),
            border: Border.all(color: selected ? t.accent : t.cardBorder),
          ),
          child: Padding(
            padding: EdgeInsets.all(t.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.itemId ?? note.summary, style: t.type.semiboldStyle),
                if (p.itemId != null) ...[
                  SizedBox(height: t.space.xxs),
                  Text(
                    note.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.type.bodyStyle.copyWith(color: t.muted),
                  ),
                ],
                if (p.owner != null) ...[
                  SizedBox(height: t.space.sm),
                  Text(
                    p.owner!,
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
