import 'package:davdart/davdart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

void main() {
  testWidgets('deleting a project keeps its items, now in Personal', (t) async {
    final s = await pumpTasksApp(
      t,
      notes: [
        Note(
          uid: 'c',
          summary: 'Projects',
          categories: [folderTag, projectsTag],
        ),
        Note(
          uid: 'a',
          summary: 'Alpha',
          parentUid: 'c',
          categories: [folderTag],
        ),
        Note(uid: 'n1', summary: 'Kept note', parentUid: 'a'),
      ],
      tasks: [mkTask('t1', parent: 'a')],
      events: [
        Event(
          uid: 'e1',
          summary: 'Kept event',
          parentUid: 'a',
          dtstart: ICalDate.date(2030, 1, 1),
        ),
      ],
    );
    await t.runAsync(() => s.deleteProject('a'));
    await t.pumpAndSettle();
    expect(s.notes.any((n) => n.uid == 'a'), isFalse);
    final personal = s.notes.firstWhere((n) => isPersonalContainer(n)).uid;
    expect(s.notes.firstWhere((n) => n.uid == 'n1').parentUid, personal);
    expect(s.tasks.firstWhere((k) => k.uid == 't1').parentUid, personal);
    expect(s.events.firstWhere((k) => k.uid == 'e1').parentUid, personal);
    expect(s.error, isNull);
  });
}
