import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../theme/tokens.dart';
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
      padding: const EdgeInsets.all(Tokens.gap),
      children: [
        for (final (name, notes) in cols)
          Container(
            width: 264,
            margin: const EdgeInsets.only(right: Tokens.gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Row(
                    children: [
                      StatusDot(name == 'notes' ? null : name),
                      const SizedBox(width: 8),
                      Text(
                        name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: .8,
                          color: t.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${notes.length}',
                        style: TextStyle(fontSize: 12, color: t.muted),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: FTappable(
        onPress: () => state.select(note.uid),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(Tokens.radius),
            border: Border.all(color: selected ? t.accent : t.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.itemId ?? note.summary,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (p.itemId != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.muted),
                  ),
                ],
                if (p.owner != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    p.owner!,
                    style: TextStyle(fontSize: 12, color: t.muted),
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
