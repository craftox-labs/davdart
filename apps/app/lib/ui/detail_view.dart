import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'chips.dart';
import 'edit_note_dialog.dart';
import 'markdown_lite.dart';
import 'parts.dart';
import 'theme.dart';
import 'move_space_dialog.dart';

class DetailView extends StatelessWidget {
  const DetailView({super.key, required this.state, required this.onClose});
  final AppState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final note = state.selected;
    if (note == null) return const SizedBox.shrink();
    final p = PlanItem.fromNote(note);
    final path = <Note>[];
    for (var n = state.tree.find(note.uid)?.parent; n != null; n = n.parent) {
      path.insert(0, n.note);
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(t.space.xs, t.space.xs, t.space.md, 0),
          child: Row(
            children: [
              IconAction(
                tooltip: 'Close',
                icon: FLucideIcons.arrowLeft,
                onPress: onClose,
              ),
              Expanded(
                child: Text(
                  path.map((n) => n.summary).join('  /  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ),
              if (state.editable) ...[
                if (state.spaces.length > 1)
                  IconAction(
                    key: const Key('move-note'),
                    tooltip: 'Move to another space',
                    icon: FLucideIcons.folderInput,
                    onPress: () => showMoveSpaceDialog(context, state, note),
                  ),
                IconAction(
                  key: const Key('edit-note'),
                  tooltip: 'Edit',
                  icon: FLucideIcons.pencil,
                  onPress: () => showEditNoteDialog(context, state, note),
                ),
                IconAction(
                  key: const Key('delete-note'),
                  tooltip: 'Delete',
                  icon: FLucideIcons.trash2,
                  onPress: () => confirmDeleteNote(context, state, note),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              t.space.xxl,
              t.space.xs,
              t.space.xxl,
              t.space.huge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.summary, style: t.type.displayStyle),
                if (state.editable && !AppState.isFolder(note)) ...[
                  SizedBox(height: t.space.md),
                  Row(
                    children: [
                      Text('Status', style: TextStyle(color: t.muted)),
                      SizedBox(width: t.space.lg),
                      SizedBox(
                        width: t.sizes.statusField,
                        child: FSelect<String>.rich(
                          key: const Key('status-menu'),
                          format: (v) => v,
                          hint: 'none',
                          control: FSelectControl.lifted(
                            value: boardOrder.contains(p.status)
                                ? p.status
                                : null,
                            onChange: (v) {
                              if (v != null) state.setStatus(note.uid, v);
                            },
                          ),
                          children: [
                            for (final s in boardOrder)
                              FSelectItem<String>(title: Text(s), value: s),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: t.space.lg),
                if (p.fields.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(t.space.lg),
                    decoration: BoxDecoration(
                      color: t.card,
                      border: Border.all(color: t.cardBorder),
                      borderRadius: BorderRadius.circular(t.radii.card),
                    ),
                    child: Column(
                      children: [
                        for (final e in p.fields.entries)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: t.space.xxs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: t.sizes.metaLabel,
                                  child: Text(
                                    e.key,
                                    style: t.type.monoStyle.copyWith(
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(e.value, style: t.type.bodyStyle),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (note.categories.isNotEmpty) ...[
                  SizedBox(height: t.space.lg),
                  Wrap(
                    spacing: t.space.sm,
                    runSpacing: t.space.sm,
                    children: [for (final c in note.categories) TagChip(c)],
                  ),
                ],
                SizedBox(height: t.space.xl),
                MarkdownLite(p.text),
                FutureBuilder<List<Revision>>(
                  key: ValueKey('rev-${note.uid}-${note.lastModified}'),
                  future: state.revisionsFor(note.uid),
                  builder: (context, snap) {
                    final revs = snap.data ?? const <Revision>[];
                    if (revs.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: EdgeInsets.only(top: t.space.xxl),
                      child: FAccordion(
                        key: const Key('revisions'),
                        children: [
                          FAccordionItem(
                            title: Text(
                              'Earlier versions (${revs.length})',
                              style: t.type.bodyStyle.copyWith(color: t.muted),
                            ),
                            child: Column(
                              children: [
                                for (final r in revs.reversed)
                                  Container(
                                    width: double.infinity,
                                    margin: EdgeInsets.only(bottom: t.space.md),
                                    padding: EdgeInsets.all(t.space.lg),
                                    decoration: BoxDecoration(
                                      color: t.card,
                                      border: Border.all(color: t.cardBorder),
                                      borderRadius: BorderRadius.circular(
                                        t.radii.card,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${r.at.toLocal().toString().substring(0, 16)}  ·  ${r.reason}',
                                          style: t.type.microStyle.copyWith(
                                            color: t.muted,
                                          ),
                                        ),
                                        SizedBox(height: t.space.xs),
                                        Text(
                                          r.summary,
                                          style: t.type.semiboldStyle,
                                        ),
                                        SelectableBody(
                                          child: Text(
                                            r.body,
                                            style: t.type.bodyStyle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
