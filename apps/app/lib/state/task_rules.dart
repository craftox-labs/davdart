import 'package:davdart/davdart.dart';

import 'event_rules.dart' show wallNow;

/// Why a task cannot be completed here yet, or null when it can. Repeating
/// tasks need recurrence handling (advancing the due date, keeping history)
/// that is not built; completing one now would end the whole series.
String? taskCompletionBlocker(Task t) => t.isRecurring
    ? 'This task repeats. Completing repeating tasks is not supported yet.'
    : null;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The calendar day a task is due in the viewer's zone (a UTC-flagged date,
/// time of day dropped), or null without a due date.
///
/// All-day and floating dues keep their own date. A `Z` or TZID time is
/// converted to the viewer's zone first (`ICalDate.localDay`).
DateTime? taskDueDay(Task t) => t.due?.localDay;

/// Open and past due at [now].
///
/// - All-day: overdue from the viewer's next local day.
/// - Timed (`Z`, TZID, or floating read in the viewer's zone): compared as an
///   instant.
bool isTaskOverdue(Task t, DateTime now) {
  final d = t.due;
  final w = d?.wall;
  if (t.isClosed || d == null || w == null) return false;
  if (d.allDay) return _day(wallNow(now)).isAfter(w);
  final i = d.toInstant();
  return i != null && now.toUtc().isAfter(i);
}

/// Open and due on the user's current day (see [taskDueDay]).
bool isTaskDueToday(Task t, DateTime now) {
  if (t.isClosed) return false;
  final d = taskDueDay(t);
  return d != null && d == _day(wallNow(now));
}

/// Sort key for due dates: the due day, then the wall clock.
int compareTasks(Task a, Task b, DateTime now) {
  final ao = isTaskOverdue(a, now), bo = isTaskOverdue(b, now);
  if (ao != bo) return ao ? -1 : 1;
  final aw = a.due?.localWall, bw = b.due?.localWall;
  if (aw != null && bw != null) {
    final c = aw.compareTo(bw);
    if (c != 0) return c;
  } else if (aw != null) {
    return -1;
  } else if (bw != null) {
    return 1;
  }
  int pri(Task t) => (t.priority == null || t.priority == 0) ? 10 : t.priority!;
  final p = pri(a).compareTo(pri(b));
  if (p != 0) return p;
  return a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
}
