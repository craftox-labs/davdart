import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

Note _f(String uid, String name, {String? parent, bool container = false}) =>
    Note(
      uid: uid,
      summary: name,
      parentUid: parent,
      categories: [folderTag, if (container) projectsTag],
      created:
          DateTime.utc(2026, 1, 1).add(Duration(minutes: uid.hashCode % 50)),
      // A folder's own stamp is its dtstamp: pin it, or a project with
      // nothing under it looks like it changed just now.
      dtstamp: DateTime.utc(2026, 1, 1),
    );

Note _n(String uid, {String? parent, DateTime? at}) => Note(
      uid: uid,
      summary: uid,
      parentUid: parent,
      lastModified: at,
      dtstamp: at,
    );

Task _t(String uid, {String? parent, DateTime? at}) =>
    Task(uid: uid, summary: uid, parentUid: parent, lastModified: at);

Event _e(String uid, {String? parent, DateTime? at}) =>
    Event(uid: uid, summary: uid, parentUid: parent, lastModified: at);

DateTime _day(int d) => DateTime.utc(2026, 3, d);

void main() {
  group('projects by last change', () {
    final notes = [
      _f('c', 'Projects', container: true, parent: null),
      _f('a', 'A', parent: 'c'),
      _f('b', 'B', parent: 'c'),
      _f('d', 'D', parent: 'c'), // nothing under it: no change stamp
      _n('na', parent: 'a', at: _day(3)),
      _n('nb', parent: 'b', at: _day(9)),
    ];

    test('newest change first, a project with none last', () {
      final ix = ProjectIndex(notes);
      expect(ix.projectsByLastChanged().map((p) => p.uid), ['b', 'a', 'd']);
    });

    test('tasks and events anywhere under a project count', () {
      final ix = ProjectIndex(notes, [
        _t('ta', parent: 'a', at: _day(20)),
      ], [
        _e('eb', parent: 'b', at: _day(4)),
      ]);
      expect(ix.projectsByLastChanged().map((p) => p.uid), ['a', 'b', 'd']);
    });

    test('a project folder is ordered by its own stamp too', () {
      final ix = ProjectIndex([
        _f('c', 'Projects', container: true),
        _f('a', 'A', parent: 'c')..lastModified = _day(30),
        _f('b', 'B', parent: 'c'),
        _n('nb', parent: 'b', at: _day(2)),
      ]);
      expect(ix.projectsByLastChanged().map((p) => p.uid), ['a', 'b']);
    });

    test('built once per index: the same list on every call', () {
      final ix = ProjectIndex(notes);
      final first = ix.projectsByLastChanged();
      expect(identical(ix.projectsByLastChanged(), first), isTrue);
      // A rebuild (a new index, as AppState makes per notification) is what
      // picks up a change.
      final rebuilt = ProjectIndex([
        ...notes.where((n) => n.uid != 'nb'),
        _n('nb', parent: 'b', at: _day(1)),
      ]);
      expect(
        rebuilt.projectsByLastChanged().map((p) => p.uid),
        [
          'a',
          'b',
          'd',
        ],
      );
    });

    test('no projects: an empty list', () {
      expect(ProjectIndex(const []).projectsByLastChanged(), isEmpty);
    });
  });
}
