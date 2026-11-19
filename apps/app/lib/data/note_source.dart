import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:http/http.dart' as http;

/// Where the app gets notes from. The dev build reads the board server's
/// read-only feed; the real app will read a local Space.
abstract class NoteSource {
  Future<List<Note>> load();
}

/// Notes from the JSON feed at `/api/notes` on the same origin.
class ApiNoteSource implements NoteSource {
  ApiNoteSource({Uri? url, http.Client? client})
    : url = url ?? Uri.base.resolve('/api/notes'),
      _client = client ?? http.Client();

  final Uri url;
  final http.Client _client;

  @override
  Future<List<Note>> load() async {
    final r = await _client.get(url);
    if (r.statusCode != 200) {
      throw Exception('Notes feed answered ${r.statusCode}');
    }
    return parseNotesJson(utf8.decode(r.bodyBytes));
  }
}

/// Reads the feed, skipping entries that are not usable (no uid, bad date)
/// instead of failing the whole load.
List<Note> parseNotesJson(String body) {
  DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
  final out = <Note>[];
  final seen = <String>{};
  for (final j in jsonDecode(body) as List<dynamic>) {
    if (j is! Map<String, dynamic>) continue;
    final uid = j['uid'];
    if (uid is! String || uid.isEmpty || !seen.add(uid)) continue;
    out.add(
      Note(
        uid: uid,
        summary: (j['title'] as String?) ?? '',
        description: (j['body'] as String?) ?? '',
        categories: [for (final t in (j['tags'] as List<dynamic>? ?? [])) '$t'],
        status: j['status'] as String?,
        parentUid: j['parent'] as String?,
        created: date(j['created']),
        lastModified: date(j['modified']),
      ),
    );
  }
  return out;
}

/// A source the app can also write to.
abstract class EditableNoteSource implements NoteSource {
  Future<Note> save(Note note);
  Future<void> delete(String uid);
}

/// Notes held in a local [Space]. Edits go through the Space (and so the sync
/// engine), never to the network. When the Space is empty and a [seed] source
/// is given, its notes are copied in once.
class SpaceNoteSource implements EditableNoteSource {
  SpaceNoteSource(this.space, {this.seed});

  final Space space;
  final NoteSource? seed;

  @override
  Future<List<Note>> load() async {
    var notes = await space.notes();
    if (notes.isEmpty && seed != null) {
      for (final n in await seed!.load()) {
        await space.save(n);
      }
      notes = await space.notes();
    }
    return notes;
  }

  @override
  Future<Note> save(Note note) => space.save(note);

  @override
  Future<void> delete(String uid) => space.delete(uid);
}
