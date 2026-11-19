import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_draft.dart';
import 'parts.dart';
import 'theme.dart';

/// The unsaved-edits bar: an indicator while anything differs, plus Discard
/// and Save.
class EditBar extends StatelessWidget {
  const EditBar({super.key, required this.state, required this.draft});
  final AppState state;
  final NoteDraft draft;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final dirty = draft.dirty;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.lg,
            vertical: t.space.sm,
          ),
          child: Row(
            children: [
              if (dirty) ...[
                Container(
                  key: const Key('dirty-indicator'),
                  width: t.sizes.statusDot,
                  height: t.sizes.statusDot,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: t.space.sm),
                Flexible(
                  child: Text(
                    'Unsaved changes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.type.captionStyle.copyWith(color: t.muted),
                  ),
                ),
              ] else
                Text(
                  'Editing',
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              const Spacer(),
              SizedBox(width: t.space.sm),
              FButton(
                key: const Key('edit-discard'),
                variant: FButtonVariant.outline,
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: state.discardDraft,
                child: Text(dirty ? 'Discard' : 'Done'),
              ),
              SizedBox(width: t.space.sm),
              FButton(
                key: const Key('edit-save'),
                size: FButtonSizeVariant.sm,
                mainAxisSize: MainAxisSize.min,
                onPress: dirty && !draft.titleEmpty ? state.saveDraft : null,
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The fields of an open edit: title, status, tags, Inside, body.
class NoteEditor extends StatelessWidget {
  const NoteEditor({
    super.key,
    required this.state,
    required this.draft,
    required this.note,
    required this.full,
  });
  final AppState state;
  final NoteDraft draft;
  final Note note;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // Where the note can move: top level, or under any note that is not it
    // or one of its own descendants. Indented like the sidebar tree.
    final targets = <(String?, String, bool, int)>[
      (null, 'Top level', false, 0),
    ];
    void collect(List<NoteNode> nodes, int depth) {
      for (final n in nodes) {
        if (state.tree.canMove(note.uid, n.note.uid)) {
          targets.add((
            n.note.uid,
            n.note.summary,
            AppState.isFolder(n.note),
            depth,
          ));
        }
        collect(n.children, depth + 1);
      }
    }

    collect(state.tree.roots, 0);
    final labels = {for (final e in targets) e.$1 ?? '': e.$2};
    final parent = targets.any((e) => e.$1 == draft.parent)
        ? draft.parent
        : null;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space.lg,
        children: [
          field(
            key: const Key('edit-title'),
            controller: draft.titleController,
            label: 'Title',
            autofocus: true,
            error: draft.titleEmpty ? 'A title is required' : null,
          ),
          if (!AppState.isFolder(note))
            FSelect<String>.rich(
              key: const Key('edit-status'),
              label: const Text('Status'),
              format: (v) => v,
              hint: 'none',
              control: FSelectControl.lifted(
                value: draft.status,
                onChange: (v) => draft.setStatus(v),
              ),
              children: [
                for (final s in boardOrder)
                  FSelectItem<String>(title: Text(s), value: s),
              ],
            ),
          field(
            key: const Key('edit-tags'),
            controller: draft.tagsController,
            label: 'Tags (comma separated)',
          ),
          FSelect<String>.rich(
            key: const Key('edit-parent'),
            label: const Text('Inside'),
            format: (v) => labels[v] ?? v,
            control: FSelectControl.lifted(
              value: parent ?? '',
              onChange: (v) =>
                  draft.setParent((v == null || v.isEmpty) ? null : v),
            ),
            children: [
              for (final e in targets)
                FSelectItem<String>(
                  title: Text(
                    e.$3 ? '${e.$2}  (folder)' : e.$2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  prefix: SizedBox(width: e.$4 * t.space.lg),
                  value: e.$1 ?? '',
                ),
            ],
          ),
          field(
            key: const Key('edit-body'),
            controller: draft.bodyController,
            minLines: full ? t.sizes.editorLinesFull : t.sizes.editorLines,
            maxLines: null,
            label: 'Text',
          ),
        ],
      ),
    );
  }
}
