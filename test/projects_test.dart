import 'package:davdart/davdart.dart';
import 'package:test/test.dart';

Note _f(String uid, String name, {String? parent, bool container = false}) =>
    Note(
      uid: uid,
      summary: name,
      parentUid: parent,
      categories: [folderTag, if (container) projectsTag],
      created: DateTime.utc(
        2026,
        1,
        1,
      ).add(Duration(minutes: uid.hashCode % 50)),
    );

Note _n(String uid, {String? parent, String? status}) => Note(
  uid: uid,
  summary: uid,
  parentUid: parent,
  description: status == null ? '' : 'status: $status\n\nx',
);

Task _t(
  String uid, {
  String? parent,
  String status = 'NEEDS-ACTION',
  List<String> tags = const [],
}) => Task(
  uid: uid,
  summary: uid,
  parentUid: parent,
  status: status,
  categories: tags,
);

void main() {
  group('derivation', () {
    test('container and its direct child folders are the projects', () {
      final ix = ProjectIndex([
        _f('c', 'Projects', container: true),
        _f('a', 'A', parent: 'c'),
        _f('b', 'B', parent: 'c'),
        _f('sub', 'Sub', parent: 'a'),
        _f('other', 'Other'),
      ]);
      expect(ix.containers().map((n) => n.uid), ['c']);
      expect(ix.projects().map((n) => n.uid).toSet(), {'a', 'b'});
      expect(ix.isProject('sub'), isFalse);
      expect(ix.projectOf('sub')!.uid, 'a');
      expect(ix.projectOf('other'), isNull);
      expect(ix.projectOf('c'), isNull);
    });

    test('items at any depth and tasks, events belong to one project', () {
      final ix = ProjectIndex(
        [
          _f('c', 'Projects', container: true),
          _f('a', 'A', parent: 'c'),
          _f('sub', 'Sub', parent: 'a'),
          _n('deep', parent: 'sub'),
          _n('loose', parent: 'c'),
          _n('free'),
        ],
        [_t('t', parent: 'deep')],
        [Event(uid: 'e', parentUid: 'sub')],
      );
      expect(ix.projectOf('deep')!.uid, 'a');
      expect(ix.projectOf('t')!.uid, 'a');
      expect(ix.projectOf('e')!.uid, 'a');
      expect(ix.projectOf('a')!.uid, 'a');
      expect(ix.projectOf('loose'), isNull);
      expect(ix.projectOf('free'), isNull);
      expect(ix.projectOf('missing'), isNull);
    });

    test('loose non-folder items under the container are not projects', () {
      final ix = ProjectIndex([
        _f('c', 'Projects', container: true),
        _n('note', parent: 'c'),
      ]);
      expect(ix.projects(), isEmpty);
    });

    test('several containers are all containers', () {
      final ix = ProjectIndex([
        _f('c1', 'Projects', container: true),
        _f('c2', 'More', container: true),
        _f('a', 'A', parent: 'c1'),
        _f('b', 'B', parent: 'c2'),
      ]);
      expect(ix.containers(), hasLength(2));
      expect(ix.projects().map((n) => n.uid).toSet(), {'a', 'b'});
    });

    test('a container needs both tags', () {
      final ix = ProjectIndex([
        Note(uid: 'x', summary: 'x', categories: [projectsTag]),
        _f('f', 'F'),
        _f('a', 'A', parent: 'f'),
      ]);
      expect(ix.containers(), isEmpty);
      expect(ix.projects(), isEmpty);
    });

    test('loops and orphans are safe', () {
      final ix = ProjectIndex(
        [
          _f('c', 'Projects', container: true),
          _f('a', 'A', parent: 'c'),
          _n('x', parent: 'y'),
          _n('y', parent: 'x'),
          _n('self', parent: 'self'),
          _n('orphan', parent: 'gone'),
        ],
        [_t('t', parent: 't')],
      );
      for (final u in ['x', 'y', 'self', 'orphan', 't']) {
        expect(ix.projectOf(u), isNull, reason: u);
      }
      expect(ix.statsOf('a').total, 0);
      expect(ix.everythingElse.open, 1); // the looping task
    });
  });

  group('counts and progress', () {
    final notes = [
      _f('c', 'Projects', container: true),
      _f('a', 'A', parent: 'c'),
      _f('b', 'B', parent: 'c'),
      _f('sub', 'Sub', parent: 'a'),
      _n('n1', parent: 'a', status: 'doing'),
      _n('n2', parent: 'sub', status: 'review'),
      _n('n3', parent: 'sub', status: 'done'),
      _n('n4', parent: 'a', status: 'canceled'),
      _n('plain', parent: 'a'),
      _n('out', status: 'todo'),
    ];
    final tasks = [
      _t('t1', parent: 'a'),
      _t('t2', parent: 'sub', status: 'COMPLETED'),
      _t('t3', parent: 'a', tags: ['status-review']),
      _t('t4', parent: 'a', status: 'CANCELLED'),
      _t('t5'),
      _t('t6', parent: 'out', status: 'COMPLETED'),
    ];
    final ix = ProjectIndex(notes, tasks);

    test('open, review, done and total', () {
      final s = ix.statsOf('a');
      expect(s.open, 2); // n1, t1
      expect(s.review, 2); // n2, t3
      expect(s.done, 2); // n3, t2
      expect(s.total, 6); // canceled and status-less notes not counted
    });

    test('progress is done over total, 0 when empty', () {
      expect(ix.statsOf('a').progress, closeTo(2 / 6, 1e-9));
      expect(ix.statsOf('b').total, 0);
      expect(ix.statsOf('b').progress, 0);
      expect(ix.statsOf('nope').progress, 0);
      expect(const ProjectStats(0, 0, 3).progress, 1);
    });

    test('everything else counts items outside every project', () {
      final r = ix.everythingElse;
      expect(r.open, 2); // out, t5
      expect(r.done, 1); // t6
      expect(r.review, 0);
    });
  });

  group('parent map', () {
    final notes = [
      _f('c', 'Projects', container: true),
      _f('a', 'A', parent: 'c'),
      _f('sub', 'Sub', parent: 'a'),
      _n('deep', parent: 'sub'),
      _n('loose'),
    ];
    final tasks = [_t('t1', parent: 'sub'), _t('t2', parent: 't1')];
    final events = [Event(uid: 'e1', summary: 'e1', parentUid: 't2')];
    final ix = ProjectIndex(notes, tasks, events);

    test('parentOf answers from the built map, notes first', () {
      expect(ix.parentOf('deep'), 'sub');
      expect(ix.parentOf('t1'), 'sub');
      expect(ix.parentOf('e1'), 't2');
      expect(ix.parentOf('loose'), isNull);
      expect(ix.parentOf('gone'), isNull);
    });

    test('isUnder walks the chain across notes, tasks and events', () {
      expect(ix.isUnder('e1', 'c'), isTrue);
      expect(ix.isUnder('t1', 'sub'), isTrue);
      expect(ix.isUnder('deep', 'deep'), isTrue, reason: 'the item itself');
      expect(ix.isUnder('loose', 'c'), isFalse);
      expect(ix.isUnder(null, 'c'), isFalse);
    });

    test('a parent loop ends instead of spinning', () {
      final looped = ProjectIndex([_n('x', parent: 'y'), _n('y', parent: 'x')]);
      expect(looped.isUnder('x', 'gone'), isFalse);
      expect(looped.isUnder('x', 'y'), isTrue);
    });

    test('a few thousand items stay fast', () {
      // A 4000-deep chain plus 4000 siblings: the old findItem walk did a
      // list scan per step, so one lookup went quadratic and a page of them
      // hung. The map walk is one step per ancestor.
      final chain = <Note>[];
      for (var i = 0; i < 4000; i++) {
        chain.add(_n('c$i', parent: i == 0 ? null : 'c${i - 1}'));
      }
      for (var i = 0; i < 4000; i++) {
        chain.add(_n('s$i'));
      }
      final clock = Stopwatch()..start();
      final big = ProjectIndex(chain);
      for (var i = 0; i < 4000; i++) {
        expect(big.isUnder('c${3999 - i}', 'c0'), isTrue);
      }
      expect(big.isUnder('c3999', 'gone'), isFalse);
      clock.stop();
      expect(
        clock.elapsedMilliseconds,
        lessThan(2000),
        reason: '4000 parent walks over 8000 items',
      );
    });
  });

  test('isProjectsContainer needs the folder and projects tags', () {
    expect(isProjectsContainer(_f('c', 'P', container: true)), isTrue);
    expect(isProjectsContainer(_f('f', 'F')), isFalse);
  });
}
