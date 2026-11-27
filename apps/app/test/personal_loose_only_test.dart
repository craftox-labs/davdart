import 'package:davdart/davdart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

void main() {
  testWidgets(
    'Personal tasks and events are loose only; a project shows its own',
    (t) async {
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
        ],
        tasks: [
          mkTask('loose', days: 1),
          mkTask('inproj', parent: 'a', days: -1),
        ],
        events: [
          Event(
            uid: 'eloose',
            summary: 'Loose event',
            dtstart: ICalDate.date(2030, 1, 1),
          ),
          Event(
            uid: 'eproj',
            summary: 'Project event',
            parentUid: 'a',
            dtstart: ICalDate.date(2030, 1, 1),
          ),
        ],
      );
      s.openFolder(null);
      expect([for (final k in s.openTasks()) k.uid], ['loose']);
      expect([for (final k in s.overdueTasks()) k.uid], isEmpty);
      expect([for (final k in s.scopedTasks) k.uid], ['loose']);
      expect([for (final e in s.scopedEvents) e.uid], ['eloose']);
      // The Space-wide count (Home tiles) still includes project tasks.
      expect(s.openTasksIn(null).length, 2);
      s.openFolder('a');
      expect([for (final k in s.openTasks()) k.uid], ['inproj']);
      expect([for (final e in s.scopedEvents) e.uid], ['eproj']);
    },
  );
}
