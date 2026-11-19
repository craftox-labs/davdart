import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import 'chips.dart';
import 'edit_note_dialog.dart';
import 'markdown_lite.dart';

class DetailView extends StatelessWidget {
  const DetailView({super.key, required this.state, required this.onClose});
  final AppState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
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
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.arrow_back),
                onPressed: onClose,
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
                IconButton(
                  key: const Key('edit-note'),
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => showEditNoteDialog(context, state, note),
                ),
                IconButton(
                  key: const Key('delete-note'),
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => confirmDeleteNote(context, state, note),
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
                if (state.editable) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Status', style: TextStyle(color: t.muted)),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        key: const Key('status-menu'),
                        value: boardOrder.contains(p.status) ? p.status : null,
                        hint: const Text('none'),
                        items: [
                          for (final s in boardOrder)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) {
                          if (v != null) state.setStatus(note.uid, v);
                        },
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}
