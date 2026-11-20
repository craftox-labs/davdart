import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import 'theme.dart';

/// Makes [child] draggable as a note ([NoteDrag]). Phones (touch platforms)
/// do not drag: a touch drag stays a scroll there, and notes move from the
/// menu instead. A plain click is untouched (a drag starts only after the
/// pointer moves).
class NoteDraggable extends StatelessWidget {
  const NoteDraggable({
    super.key,
    required this.uid,
    required this.source,
    required this.label,
    required this.child,
  });
  final String uid;
  final NoteDragSource source;

  /// Text of the floating chip under the pointer.
  final String label;
  final Widget child;

  static bool get _touchPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Draggable<NoteDrag>(
      data: NoteDrag(uid, source),
      maxSimultaneousDrags: _touchPlatform ? 0 : 1,
      feedback: DefaultTextStyle(
        style: t.type.captionStyle.copyWith(color: t.fg),
        child: Container(
          constraints: BoxConstraints(maxWidth: t.sizes.tabMax),
          padding: EdgeInsets.symmetric(
            horizontal: t.space.md,
            vertical: t.space.sm,
          ),
          decoration: BoxDecoration(
            color: t.panel,
            border: Border.all(color: t.divider),
            borderRadius: BorderRadius.circular(t.radii.small),
          ),
          child: Text(
            label.isEmpty ? 'Untitled' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: t.motion.dragGhost, child: child),
      child: child,
    );
  }
}

/// A place a dragged note can be dropped. While an acceptable drag is over
/// it, it outlines itself in the accent tone. [accepts] decides per drag
/// (and so which target, if any, lights up); the deepest accepting target
/// wins, so a folder row takes a drop before the tree area behind it.
class NoteDropTarget extends StatelessWidget {
  const NoteDropTarget({
    super.key,
    required this.accepts,
    required this.onDrop,
    required this.child,
    this.rounded = true,
  });
  final bool Function(NoteDrag drag) accepts;
  final void Function(NoteDrag drag) onDrop;
  final Widget child;

  /// Rounds the outline with the small radius.
  final bool rounded;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return DragTarget<NoteDrag>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: rounded ? BorderRadius.circular(t.radii.small) : null,
          border: candidates.isEmpty
              ? null
              : Border.all(color: t.accent, width: t.borders.focus),
        ),
        child: child,
      ),
    );
  }
}

/// A [NoteDropTarget] that moves the dropped note into folder [folderUid]
/// (null: the top level). Refuses a drop that changes nothing, or that would
/// put a folder inside itself or one of its descendants.
class MoveDropTarget extends StatelessWidget {
  const MoveDropTarget({
    super.key,
    required this.state,
    required this.folderUid,
    required this.child,
    this.rounded = true,
  });
  final AppState state;
  final String? folderUid;
  final Widget child;
  final bool rounded;

  /// Whether dropping [uid] here is a real, valid move.
  static bool canDrop(AppState state, String uid, String? folderUid) =>
      state.editable &&
      state.tree.find(uid) != null &&
      state.tree.find(uid)!.parent?.note.uid != folderUid &&
      state.tree.canMove(uid, folderUid);

  @override
  Widget build(BuildContext context) => NoteDropTarget(
    rounded: rounded,
    accepts: (d) => canDrop(state, d.uid, folderUid),
    onDrop: (d) => state.moveNote(d.uid, folderUid),
    child: child,
  );
}
