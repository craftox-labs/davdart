import 'popover_track.dart';

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Edits a note's title and body text. Header lines are kept as they are.
Future<void> showEditNoteDialog(
  BuildContext context,
  AppState state,
  Note note,
) {
  final title = TextEditingController(text: note.summary);
  final body = TextEditingController(text: PlanItem.fromNote(note).text);
  final tags = TextEditingController(
    text: note.categories
        .where((c) => !c.startsWith('status-') && !c.startsWith('kind-'))
        .join(', '),
  );
  // Where the note can move: top level, or under any note that is not it or
  // one of its own descendants. Indented like the sidebar tree.
  final targets = <(String?, String, bool)>[(null, 'Top level', false)];
  void collect(List<NoteNode> nodes, int depth) {
    for (final n in nodes) {
      if (!isPersonalContainer(n.note) &&
          state.tree.canMove(note.uid, n.note.uid)) {
        targets.add((
          n.note.uid,
          '${'    ' * depth}${n.note.summary}',
          AppState.isFolder(n.note),
        ));
      }
      collect(n.children, depth + 1);
    }
  }

  collect(state.tree.roots, 0);
  final originalParent = state.tree.find(note.uid)?.parent?.note.uid;
  var parent = originalParent;
  if (!targets.any((e) => e.$1 == parent)) parent = null;
  final isFolder = AppState.isFolder(note);
  void save(BuildContext ctx) {
    Navigator.of(ctx).pop();
    state.updateNote(
      note.uid,
      title: title.text,
      text: body.text,
      setParent: parent != state.tree.find(note.uid)?.parent?.note.uid,
      parentUid: parent,
      tags: [
        for (final t in tags.text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ],
    );
  }

  // The Inside menu: '' stands for the top level.
  final labels = {for (final e in targets) e.$1 ?? '': e};
  return showAppDialog(
    context,
    title: isFolder ? 'Edit folder' : 'Edit note',
    width: tokensOf(context).sizes.dialogXl,
    content: StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: tokensOf(ctx).space.lg,
        children: [
          field(
            key: const Key('edit-title'),
            controller: title,
            label: 'Title',
          ),
          field(
            key: const Key('edit-tags'),
            controller: tags,
            label: 'Tags (comma separated)',
          ),
          TrackPopover(
            builder: (_, pc) => FSelect<String>.rich(
              popoverControl: pc,
              key: const Key('edit-parent'),
              label: const Text('Inside'),
              format: (v) => labels[v]?.$2.trim() ?? v,
              control: FSelectControl.lifted(
                value: parent ?? '',
                onChange: (v) => setLocal(() {
                  parent = (v == null || v.isEmpty) ? null : v;
                }),
              ),
              children: [
                for (final e in targets)
                  FSelectItem<String>(
                    title: Text(
                      e.$3 ? '${e.$2.trim()}  (folder)' : e.$2.trim(),
                      overflow: TextOverflow.ellipsis,
                    ),
                    prefix: SizedBox(
                      width: _indent(e.$2) * tokensOf(ctx).space.lg,
                    ),
                    value: e.$1 ?? '',
                  ),
              ],
            ),
          ),
          field(
            key: const Key('edit-body'),
            controller: body,
            minLines: 6,
            maxLines: 14,
            label: isFolder ? 'Text (about this folder, instructions)' : 'Text',
          ),
        ],
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Save', key: const Key('edit-save'), onPress: save),
    ],
  );
}

double _indent(String label) => (label.length - label.trimLeft().length) / 4;

Future<void> confirmDeleteNote(
  BuildContext context,
  AppState state,
  Note note,
) {
  return showAppDialog(
    context,
    title: 'Delete note?',
    content: Text('"${note.summary}" will be deleted. Notes under it move up.'),
    actions: [
      const CancelButton(),
      ActionButton(
        'Delete',
        key: const Key('delete-confirm'),
        onPress: (ctx) {
          Navigator.of(ctx).pop();
          state.deleteNote(note.uid);
        },
      ),
    ],
  );
}
