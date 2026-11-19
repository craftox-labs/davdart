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
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
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
                  style: TextStyle(fontSize: 12, color: t.muted),
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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.summary,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (state.editable && !AppState.isFolder(note)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Status', style: TextStyle(color: t.muted)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 160,
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
                const SizedBox(height: 12),
                if (p.fields.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surface,
                      border: Border.all(color: t.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        for (final e in p.fields.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 104,
                                  child: Text(
                                    e.key,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: t.muted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                if (note.categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final c in note.categories) TagChip(c)],
                  ),
                ],
                const SizedBox(height: 16),
                MarkdownLite(p.text),
                FutureBuilder<List<Revision>>(
                  key: ValueKey('rev-${note.uid}-${note.lastModified}'),
                  future: state.revisionsFor(note.uid),
                  builder: (context, snap) {
                    final revs = snap.data ?? const <Revision>[];
                    if (revs.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: FAccordion(
                        key: const Key('revisions'),
                        children: [
                          FAccordionItem(
                            title: Text(
                              'Earlier versions (${revs.length})',
                              style: TextStyle(fontSize: 13, color: t.muted),
                            ),
                            child: Column(
                              children: [
                                for (final r in revs.reversed)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: t.surface,
                                      border: Border.all(color: t.line),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${r.at.toLocal().toString().substring(0, 16)}  ·  ${r.reason}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: t.muted,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          r.summary,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SelectableBody(
                                          child: Text(
                                            r.body,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
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
