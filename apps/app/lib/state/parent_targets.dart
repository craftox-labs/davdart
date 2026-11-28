import 'package:davdart/davdart.dart';

import 'app_state.dart';

/// What a parent target is, so a picker can mark it.
enum ParentKind { top, folder, note, task }

/// One place the item being edited can move to: the top level (a null [uid]),
/// a note, a folder, or a task (a task under a task).
class ParentTarget {
  const ParentTarget(this.uid, this.label, this.kind, this.depth);

  final String? uid;
  final String label;
  final ParentKind kind;

  /// How deep in the tree it sits (the picker indents by it).
  final int depth;
}

/// Every place item [forUid] (a note or a task) can move to, in tree order:
/// the top level first, then the notes and folders (indented), then the tasks
/// that can take it. Personal containers are never offered.
List<ParentTarget> parentTargets(AppState state, {required String forUid}) {
  final targets = <ParentTarget>[
    const ParentTarget(null, 'Top level', ParentKind.top, 0),
  ];
  final task = state.taskById(forUid) != null;
  // An item that does not exist yet (a new-item dialog) has no subtree to avoid.
  final fresh = state.findItem(forUid) == null;
  void collect(List<NoteNode> nodes, int depth) {
    for (final n in nodes) {
      if (isPersonalContainer(n.note)) continue;
      final folder = AppState.isFolder(n.note);
      // A note cannot move under itself or into its own subtree.
      if (task || fresh || state.tree.canMove(forUid, n.note.uid)) {
        targets.add(
          ParentTarget(
            n.note.uid,
            n.note.summary,
            folder ? ParentKind.folder : ParentKind.note,
            depth,
          ),
        );
      }
      collect(n.children, depth + 1);
    }
  }

  collect(state.tree.roots, 0);
  if (task) {
    for (final k in state.tasks) {
      if (state.canMoveTask(forUid, k.uid)) {
        targets.add(ParentTarget(k.uid, k.summary, ParentKind.task, 0));
      }
    }
  }
  return targets;
}
