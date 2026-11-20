import 'package:davdart/src/note.dart';
import 'package:davdart/src/plan_item.dart';
import 'package:test/test.dart';

const body = 'item_id: davdart-x\n'
    "status: backlog (proposed; tm's go moves it to todo)\n"
    'owner: tm (decides)\n'
    'github_ref: (none)\n'
    'custom_key: keep\n'
    '\n'
    'First paragraph.\n\n'
    '## Heading\nline: not a header';

void main() {
  test('reads header fields and free text', () {
    final p = PlanItem.fromNote(Note(
        uid: 'u', summary: 'T', description: body, categories: ['davdart']));
    expect(p.itemId, 'davdart-x');
    expect(p.status, 'backlog');
    expect(p.owner, 'tm (decides)');
    expect(p.githubRef, '(none)');
    expect(p.fields.keys.last, 'custom_key');
    expect(p.text, startsWith('First paragraph.'));
    expect(p.text, contains('line: not a header'));
  });

  test('toDescription round-trips unchanged', () {
    final p = PlanItem.fromNote(Note(uid: 'u', description: body));
    expect(p.toDescription(), body);
  });

  test('setStatus updates the field and the status tag', () {
    final n = Note(
        uid: 'u', description: body, categories: ['davdart', 'status-backlog']);
    final p = PlanItem.fromNote(n)..setStatus('todo');
    p.apply();
    expect(PlanItem.fromNote(n).status, 'todo');
    expect(n.categories, ['davdart', 'status-todo']);
    expect(n.description, contains('status: todo\n'));
  });

  test('a note without a header has no fields and keeps its text', () {
    const plain = '# Heading\n\nSome text: with a colon.';
    final p = PlanItem.fromNote(Note(uid: 'u', description: plain));
    expect(p.fields, isEmpty);
    expect(p.toDescription(), plain);
  });

  test('a header run that does not end at a blank line is not a header', () {
    const odd = 'status: x\nthen prose follows directly';
    final p = PlanItem.fromNote(Note(uid: 'u', description: odd));
    expect(p.fields, isEmpty);
    expect(p.text, odd);
  });

  test('falls back to the status-* tag when there is no status field', () {
    final p = PlanItem.fromNote(
        Note(uid: 'u', description: 'owner: tm', categories: ['status-done']));
    expect(p.status, 'done');
  });

  test('clearStatus removes the status line and tags, keeps the rest', () {
    final p = PlanItem.fromNote(Note(
        uid: 'u',
        description: body,
        categories: ['davdart', 'status-backlog']));
    p.clearStatus();
    expect(p.status, isNull);
    expect(p.note.categories, ['davdart']);
    expect(p.toDescription(), isNot(contains('status:')));
    expect(p.toDescription(), contains('custom_key: keep'));
  });
}
