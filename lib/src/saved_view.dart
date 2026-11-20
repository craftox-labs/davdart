import 'note.dart';
import 'plan_item.dart';

/// Tag of a folder note (a container, hidden from Board and List).
const folderTag = 'kind-folder';

/// Tag of a saved-view note (a stored query, hidden everywhere notes are
/// listed, searched or counted).
const viewTag = 'kind-view';

bool isFolderNote(Note n) => n.categories.contains(folderTag);
bool isViewNote(Note n) => n.categories.contains(viewTag);

/// True for notes that hold structure or settings rather than content, so
/// boards and lists leave them out.
bool isStructuralNote(Note n) => isFolderNote(n) || isViewNote(n);

/// A saved view: a named query over a Space, stored as a note so it syncs
/// like any other note and shows up for every client.
///
/// Storage format: a note tagged `kind-view`; the note title is the view
/// name; the body is a PlanItem-style header of `key: value` lines (one
/// per line, lower-case keys), for example
///
///     mode: list
///     search: release notes
///     tags: davdart, planning
///     folder: davdart-1763500000000000
///
/// Keys: `mode` (`board` or `list`, default board), `search` (text, empty
/// if absent), `tags` (comma separated list), `folder` (uid of the folder
/// the view is scoped to; absent means the whole Space). Missing keys take
/// their default; unknown keys and any text after the header are ignored
/// and kept when the view is updated. This repo has no docs/ folder, so this
/// comment is the format's documentation.
class SavedViewSpec {
  SavedViewSpec({
    required this.uid,
    required this.name,
    this.mode = 'board',
    this.search = '',
    List<String>? tags,
    this.folderUid,
  }) : tags = tags ?? <String>[];

  /// The note's uid.
  final String uid;
  final String name;

  /// `board` or `list`; anything else reads as `board`.
  final String mode;
  final String search;
  final List<String> tags;
  final String? folderUid;

  /// Reads [note] as a view; null if it is not tagged `kind-view` or has no
  /// name.
  static SavedViewSpec? fromNote(Note note) {
    if (!isViewNote(note) || note.summary.trim().isEmpty) return null;
    final f = PlanItem.fromNote(note).fields;
    final mode = f['mode']?.trim().toLowerCase();
    final folder = f['folder']?.trim();
    return SavedViewSpec(
      uid: note.uid,
      name: note.summary.trim(),
      mode: mode == 'list' ? 'list' : 'board',
      search: f['search']?.trim() ?? '',
      tags: _splitTags(f['tags']),
      folderUid: folder == null || folder.isEmpty ? null : folder,
    );
  }

  /// A new note for this view.
  Note toNote({DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    final n = Note(
      uid: uid,
      summary: name,
      categories: [viewTag],
      created: t,
      lastModified: t,
    );
    return writeTo(n);
  }

  /// Writes this view's fields into [note]'s header (title too), keeping
  /// unknown header keys and body text, and returns it.
  Note writeTo(Note note) {
    final p = PlanItem.fromNote(note);
    p.fields
      ..['mode'] = mode
      ..['search'] = search.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    _setOrDrop(p.fields, 'tags', tags.join(', '));
    _setOrDrop(p.fields, 'folder', folderUid ?? '');
    if (p.fields['search']!.isEmpty) p.fields.remove('search');
    note.summary = name;
    if (!note.categories.contains(viewTag)) note.categories.add(viewTag);
    note.lastModified = DateTime.now().toUtc();
    return p.apply();
  }

  static void _setOrDrop(Map<String, String> m, String k, String v) {
    if (v.isEmpty) {
      m.remove(k);
    } else {
      m[k] = v;
    }
  }

  static List<String> _splitTags(String? v) => [
        if (v != null)
          for (final t in v.split(','))
            if (t.trim().isNotEmpty) t.trim(),
      ];
}
