import 'dart:convert';

import 'package:davdart/davdart.dart';
import 'package:davdart_web/web_app.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final notes = [
    Note(
        uid: 'a b',
        summary: 'Item <one>',
        description: 'item_id: x-1\nstatus: todo\nowner: tm\n\nBody & text',
        categories: ['davdart', 'status-todo']),
    Note(uid: 'n', summary: 'Plain note', description: 'just text'),
  ];
  final h = buildHandler(() async => notes);
  Future<Response> get(String p) async =>
      h(Request('GET', Uri.parse('http://x/$p')));

  test('board groups by status and escapes HTML', () async {
    final r = await get('');
    final body = await r.readAsString();
    expect(r.statusCode, 200);
    expect(body, contains('todo'));
    expect(body, contains('x-1'));
    expect(body, contains('Item &lt;one&gt;'));
    expect(body, isNot(contains('Item <one>')));
    expect(body, contains('notes'));
  });

  test('tag filter narrows the board', () async {
    final body = await (await get('?tag=davdart')).readAsString();
    expect(body, contains('x-1'));
    expect(body, isNot(contains('Plain note')));
  });

  test('detail shows fields and text, 404 for unknown', () async {
    final r = await get('item/${Uri.encodeComponent('a b')}');
    final body = await r.readAsString();
    expect(body, contains('owner'));
    expect(body, contains('Body &amp; text'));
    expect((await get('item/nope')).statusCode, 404);
    expect((await get('zzz')).statusCode, 404);
  });

  test('api/notes returns JSON without raw lines', () async {
    final r = await get('api/notes');
    expect(r.statusCode, 200);
    expect(r.headers['content-type'], contains('application/json'));
    final list = jsonDecode(await r.readAsString()) as List<dynamic>;
    expect(list, hasLength(2));
    final first = list.first as Map<String, dynamic>;
    expect(first['uid'], 'a b');
    expect(first['body'], contains('item_id: x-1'));
    expect(first.keys, isNot(contains('extraLines')));
  });

  test('a server failure becomes a 502 page', () async {
    final bad = buildHandler(() async => throw CalDavException(401, 'x'));
    final r = await bad(Request('GET', Uri.parse('http://x/')));
    expect(r.statusCode, 502);
  });
}
