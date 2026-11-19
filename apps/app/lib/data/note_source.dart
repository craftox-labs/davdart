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

List<Note> parseNotesJson(String body) {
  DateTime? date(Object? v) => v == null ? null : DateTime.parse(v as String);
  return [
    for (final j in jsonDecode(body) as List<dynamic>)
      Note(
        uid: (j as Map<String, dynamic>)['uid'] as String,
        summary: (j['title'] as String?) ?? '',
        description: (j['body'] as String?) ?? '',
        categories: [for (final t in (j['tags'] as List<dynamic>? ?? [])) '$t'],
        status: j['status'] as String?,
        parentUid: j['parent'] as String?,
        created: date(j['created']),
        lastModified: date(j['modified']),
      ),
  ];
}
