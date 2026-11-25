import 'package:davdart/davdart.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_draft.dart';
import 'parts.dart';
import 'popover_track.dart';
import 'theme.dart';
import 'vim_field.dart';

/// The fields of an open edit: title, status, priority, tags, Inside, body.
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
          if (draft.titleEmpty)
            Text(
              'A title is required',
              style: t.type.captionStyle.copyWith(color: t.error),
            ),
          if (!AppState.isFolder(note))
            TrackPopover(
              builder: (_, pc) => FSelect<String>.rich(
                popoverControl: pc,
                key: const Key('edit-status'),
                label: const Text('Status'),
                format: (v) => v.isEmpty ? 'none' : v,
                hint: 'none',
                control: FSelectControl.lifted(
                  value: draft.status,
                  // '' is the "none" row: the note leaves the boards.
                  onChange: (v) =>
                      draft.setStatus(v == null || v.isEmpty ? null : v),
                ),
                children: [
                  const FSelectItem<String>(
                    key: Key('edit-status-none'),
                    title: Text('none'),
                    value: '',
                  ),
                  for (final s in boardOrder)
                    FSelectItem<String>(title: Text(s), value: s),
                ],
              ),
            ),
          if (!AppState.isFolder(note))
            TrackPopover(
              builder: (_, pc) => FSelect<String>.rich(
                popoverControl: pc,
                key: const Key('edit-note-priority'),
                label: const Text('Priority'),
                format: (v) => v.isEmpty ? 'none' : v,
                hint: 'none',
                control: FSelectControl.lifted(
                  value: draft.priority ?? '',
                  onChange: (v) =>
                      draft.setPriority(v == null || v.isEmpty ? null : v),
                ),
                children: [
                  const FSelectItem<String>(title: Text('none'), value: ''),
                  for (final p in notePriorities.keys)
                    FSelectItem<String>(title: Text(p), value: p),
                ],
              ),
            ),
          field(
            key: const Key('edit-tags'),
            controller: draft.tagsController,
            label: 'Tags (comma separated)',
          ),
          TrackPopover(
            builder: (_, pc) => FSelect<String>.rich(
              popoverControl: pc,
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
          ),
          VimField(
            key: ValueKey('vim-${draft.uid}'),
            state: state,
            uid: draft.uid,
            controller: draft.bodyController,
            fieldKey: const Key('edit-body'),
            minLines: full ? t.sizes.editorLinesFull : t.sizes.editorLines,
            label: 'Text',
          ),
        ],
      ),
    );
  }
}

/// True while an input method is composing text (Esc then belongs to it).
bool imeComposing() {
  final c = FocusManager.instance.primaryFocus?.context;
  final ed = c?.findAncestorStateOfType<EditableTextState>();
  return ed != null && ed.textEditingValue.composing.isValid;
}

/// Keys of an open edit, while the focus is inside the editor: Esc leaves
/// edit mode (a dirty edit asks first), Ctrl/Cmd+Enter saves and leaves. An
/// open dropdown or dialog takes Esc first (it handles the key before it
/// bubbles here); so does an IME that is composing.
class EditKeys extends StatelessWidget {
  const EditKeys({
    super.key,
    required this.state,
    required this.uid,
    required this.child,
  });
  final AppState state;
  final String uid;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, e) {
      if (e is! KeyDownEvent) return KeyEventResult.ignored;
      final kb = HardwareKeyboard.instance;
      if (e.logicalKey == LogicalKeyboardKey.escape &&
          !kb.isControlPressed &&
          !kb.isMetaPressed &&
          !kb.isAltPressed) {
        if (imeComposing()) return KeyEventResult.ignored;
        if (PopoverTracker.instance.dismiss()) return KeyEventResult.handled;
        state.leaveEdit(uid);
        return KeyEventResult.handled;
      }
      if ((e.logicalKey == LogicalKeyboardKey.enter ||
              e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
          (kb.isControlPressed || kb.isMetaPressed)) {
        state.saveAndLeave(uid);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

/// The edit-mode icons of a detail header: Cancel (Esc) and Save and close
/// (Ctrl+Enter). The Save icon carries a dot while anything is unsaved, and
/// is off while the draft cannot be saved (empty title, end before start).
List<Widget> editIcons(AppState state, String uid) => [
  IconAction(
    key: const Key('edit-cancel-action'),
    tooltip: 'Cancel (Esc)',
    icon: FLucideIcons.x,
    onPress: () => state.leaveEdit(uid),
  ),
  _SaveIcon(state: state, uid: uid),
];

class _SaveIcon extends StatelessWidget {
  const _SaveIcon({required this.state, required this.uid});
  final AppState state;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final Listenable draft =
        state.draftFor(uid) ??
        state.taskDraftFor(uid) ??
        state.eventDraftFor(uid) ??
        state;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final dirty = state.dirtyItem(uid);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconAction(
              key: const Key('edit-save-action'),
              tooltip: 'Save and close (Ctrl+Enter)',
              icon: FLucideIcons.check,
              onPress: state.editBlocked(uid)
                  ? null
                  : () => state.saveAndLeave(uid),
            ),
            if (dirty)
              Positioned(
                top: t.space.xs,
                right: t.space.xs,
                child: IgnorePointer(
                  child: Container(
                    key: const Key('dirty-indicator'),
                    width: t.sizes.statusDot,
                    height: t.sizes.statusDot,
                    decoration: BoxDecoration(
                      color: t.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
