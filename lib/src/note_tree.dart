import 'note.dart';

class NoteNode {
  NoteNode(this.note);
  final Note note;
  NoteNode? parent;
  final List<NoteNode> children = [];
}

/// Notes arranged by their parent links. Built the same way on every device:
/// a note whose parent is missing (not synced yet, or deleted) or whose link
/// would close a loop is shown at the top level instead of being lost.
final _epoch = DateTime.utc(1970);

class NoteTree {
  NoteTree._(this.roots, this._byUid);

  final List<NoteNode> roots;
  final Map<String, NoteNode> _byUid;

  /// Default sibling order: oldest first, then title.
  static int byCreated(Note a, Note b) {
    // No CREATED sorts first at a fixed time: DTSTAMP defaults to "now" on
    // parse, which would shuffle those siblings on every sync.
    final ca = a.created ?? _epoch, cb = b.created ?? _epoch;
    final c = ca.compareTo(cb);
    if (c != 0) return c;
    final t = a.summary.compareTo(b.summary);
    return t != 0 ? t : a.uid.compareTo(b.uid);
  }

  factory NoteTree.build(Iterable<Note> notes,
      {int Function(Note, Note)? compare}) {
    final cmp = compare ?? byCreated;
    final nodes = {for (final n in notes) n.uid: NoteNode(n)};
    // Attach in uid order so every device breaks a loop at the same place.
    final order = nodes.keys.toList()..sort();
    for (final uid in order) {
      final node = nodes[uid]!;
      final p = node.note.parentUid;
      final parent = p == null ? null : nodes[p];
      if (parent == null || parent == node || _reaches(parent, node)) continue;
      node.parent = parent;
      parent.children.add(node);
    }
    final roots = [
      for (final n in nodes.values)
        if (n.parent == null) n
    ];
    void sortAll(List<NoteNode> l) {
      l.sort((a, b) => cmp(a.note, b.note));
      for (final n in l) {
        sortAll(n.children);
      }
    }

    sortAll(roots);
    return NoteTree._(roots, nodes);
  }

  static bool _reaches(NoteNode from, NoteNode target) {
    for (NoteNode? n = from; n != null; n = n.parent) {
      if (n == target) return true;
    }
    return false;
  }

  NoteNode? find(String uid) => _byUid[uid];

  /// Every note below [uid], depth first.
  List<Note> descendants(String uid) {
    final out = <Note>[];
    void walk(NoteNode n) {
      for (final c in n.children) {
        out.add(c.note);
        walk(c);
      }
    }

    final n = _byUid[uid];
    if (n != null) walk(n);
    return out;
  }

  /// Whether making [newParentUid] the parent of [uid] would be valid: the
  /// parent exists (or is null for top level) and is not the note itself or
  /// one of its descendants.
  bool canMove(String uid, String? newParentUid) {
    if (newParentUid == null) return _byUid.containsKey(uid);
    if (uid == newParentUid) return false;
    final p = _byUid[newParentUid], n = _byUid[uid];
    if (p == null || n == null) return false;
    return !_reaches(p, n);
  }

  /// The parent a deleted note's children should move to: its own parent.
  String? adoptiveParent(String uid) => _byUid[uid]?.note.parentUid;
}
