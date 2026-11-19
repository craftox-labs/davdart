import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:shelf/shelf.dart';

const _esc = HtmlEscape(HtmlEscapeMode.element);
const _columnOrder = ['backlog', 'todo', 'doing', 'blocked', 'done'];

typedef NoteLoader = Future<List<Note>> Function();

/// Read-only board over planning notes. [load] returns the current notes; it
/// is called per request (callers may cache).
Handler buildHandler(NoteLoader load) {
  return (Request req) async {
    try {
      final path = req.url.path;
      if (path.isEmpty) {
        return _html(_board(await load(), req.url.queryParameters['tag']));
      }
      if (path == 'api/notes') {
        return Response.ok(jsonEncode(_notesJson(await load())), headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        });
      }
      if (path.startsWith('item/')) {
        final String uid;
        try {
          uid = Uri.decodeComponent(path.substring(5));
        } on FormatException {
          return _html(_page('Not found', '<p>Not found.</p>'), 404);
        }
        final hit = (await load()).where((n) => n.uid == uid).firstOrNull;
        if (hit == null) {
          return _html(_page('Not found', '<p>No such note.</p>'), 404);
        }
        return _html(_detail(PlanItem.fromNote(hit)));
      }
      return _html(_page('Not found', '<p>Not found.</p>'), 404);
    } on CalDavException catch (e) {
      return _html(_page('Error', '<p>Server said ${e.statusCode}.</p>'), 502);
    }
  };
}

/// Read-only JSON for the Flutter app. Body text and fields only: raw
/// iCalendar lines (recordings and the like) are not sent.
List<Map<String, Object?>> _notesJson(List<Note> notes) => [
      for (final n in notes)
        {
          'uid': n.uid,
          'title': n.summary,
          'body': n.description,
          'tags': n.categories,
          'status': n.status,
          'parent': n.parentUid,
          'created': n.created?.toIso8601String(),
          'modified': n.lastModified?.toIso8601String(),
        }
    ];

Response _html(String body, [int status = 200]) =>
    Response(status, body: body, headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    });

String _board(List<Note> notes, String? tag) {
  final items = notes
      .where((n) => !isStructuralNote(n)) // folders and saved views
      .map(PlanItem.fromNote)
      .where((p) => tag == null || p.tags.contains(tag))
      .toList();
  final cols = <String, List<PlanItem>>{};
  for (final p in items) {
    (cols[p.status ?? 'notes'] ??= []).add(p);
  }
  final keys = [
    ..._columnOrder.where(cols.containsKey),
    ...cols.keys.where((k) => !_columnOrder.contains(k) && k != 'notes'),
    if (cols.containsKey('notes')) 'notes',
  ];
  final allTags = {for (final n in notes) ...n.categories}.toList()..sort();
  final filter = StringBuffer('<nav class="tags">'
      '<a href="./"${tag == null ? ' class="on"' : ''}>all</a>');
  for (final t in allTags.where((t) => !t.startsWith('status-') && !t.startsWith('kind-'))) {
    filter.write(
        '<a href="./?tag=${Uri.encodeQueryComponent(t)}"${t == tag ? ' class="on"' : ''}>${_esc.convert(t)}</a>');
  }
  filter.write('</nav>');
  final b = StringBuffer(filter)..write('<div class="board">');
  for (final k in keys) {
    b.write(
        '<section><h2>${_esc.convert(k)} <span>${cols[k]!.length}</span></h2>');
    for (final p in cols[k]!) {
      b.write('<a class="card" href="item/${Uri.encodeComponent(p.note.uid)}">'
          '<b>${_esc.convert(p.itemId ?? p.title)}</b>');
      if (p.itemId != null) {
        b.write('<small>${_esc.convert(p.title)}</small>');
      }
      if (p.owner != null) b.write('<em>${_esc.convert(p.owner!)}</em>');
      b.write('</a>');
    }
    b.write('</section>');
  }
  b.write('</div>');
  return _page('Board', b.toString());
}

String _detail(PlanItem p) {
  final b = StringBuffer('<p><a href="../">&larr; board</a></p>'
      '<h1>${_esc.convert(p.title)}</h1><dl>');
  p.fields.forEach((k, v) =>
      b.write('<dt>${_esc.convert(k)}</dt><dd>${_esc.convert(v)}</dd>'));
  b.write('</dl>');
  if (p.tags.isNotEmpty) {
    b.write(
        '<p class="chips">${p.tags.map((t) => '<span>${_esc.convert(t)}</span>').join()}</p>');
  }
  b.write('<pre>${_esc.convert(p.text)}</pre>');
  return _page(p.title, b.toString());
}

String _page(String title, String body) => '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${_esc.convert(title)} · davdart</title>
<style>
:root{--bg:#fafaf8;--fg:#1b1b1a;--mut:#6b6a66;--card:#fff;--line:#e4e2dc;--acc:#2f5fd0}
@media (prefers-color-scheme:dark){:root{--bg:#161615;--fg:#ecebe7;--mut:#9a9890;--card:#202020;--line:#33322f;--acc:#8fb0ff}}
*{box-sizing:border-box}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
a{color:var(--acc);text-decoration:none}
h1{font-size:1.3rem;margin:.2em 0 .6em}
.tags{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:14px}
.tags a{padding:2px 10px;border:1px solid var(--line);border-radius:99px;font-size:.85rem;color:var(--mut)}
.tags a.on{color:var(--fg);border-color:var(--fg)}
.board{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(240px,1fr);gap:12px;overflow-x:auto;align-items:start}
section h2{font-size:.8rem;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:0 0 8px}
section h2 span{font-weight:400}
.card{display:block;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px 12px;margin-bottom:8px;color:var(--fg)}
.card small,.card em{display:block;color:var(--mut);font-style:normal;font-size:.85rem}
dl{display:grid;grid-template-columns:max-content 1fr;gap:2px 14px;color:var(--mut)}
dd{margin:0;color:var(--fg)}dt{font-family:ui-monospace,monospace;font-size:.85rem}
.chips span{display:inline-block;margin-right:6px;padding:1px 9px;border:1px solid var(--line);border-radius:99px;font-size:.8rem;color:var(--mut)}
pre{white-space:pre-wrap;word-wrap:break-word;font:inherit;background:var(--card);border:1px solid var(--line);border-radius:8px;padding:14px}
</style></head><body>$body</body></html>''';
