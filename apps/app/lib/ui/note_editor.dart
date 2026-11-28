import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_draft.dart';
import 'parts.dart';
import 'popover_track.dart';
import 'theme.dart';
import 'vim_field.dart';

/// The open edit of a note's body: its Vim field, under the page's property
/// rows. The title is the header's inline field and every property is a row,
/// so neither is part of this editor; only the long Markdown text is.
class NoteEditor extends StatelessWidget {
  const NoteEditor({
    super.key,
    required this.state,
    required this.draft,
    required this.full,
  });
  final AppState state;
  final NoteDraft draft;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
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
