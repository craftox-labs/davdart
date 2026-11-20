import 'package:davdart/davdart.dart';

/// Why a task cannot be completed here yet, or null when it can. Repeating
/// tasks need recurrence handling (advancing the due date, keeping history)
/// that is not built; completing one now would end the whole series.
String? taskCompletionBlocker(Task t) => t.isRecurring
    ? 'This task repeats. Completing repeating tasks is not supported yet.'
    : null;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// The calendar day a task is due (a UTC-flagged date, time of day dropped),
/// or null without a due date.
///
/// All-day and floating dues use their own date. A UTC time is shown in the
/// user's day. A time with a TZID uses its wall-clock date: there is no time
/// zone database, so it is not converted (it can differ from the user's day
/// by the zone offset).
DateTime? taskDueDay(Task t) {
  final d = t.due;
  final w = d?.wall;
  if (d == null || w == null) return null;
  if (d.isUtc && !d.allDay) return _day(w.toLocal());
  return _day(w);
}

/// Open and past due at [now]. Conservative: never early.
///
/// - All-day: overdue from the user's next local day.
/// - Floating time (no zone): compared with the user's local wall clock.
/// - UTC time: compared as an instant.
/// - Time with a TZID: the zone is unknown (no tz database), and real UTC
///   lies between wall-14h and wall+12h, so it counts as overdue only after
///   wall+12h. It can be flagged up to 12 hours late, never early.
bool isTaskOverdue(Task t, DateTime now) {
  final d = t.due;
  final w = d?.wall;
  if (t.isClosed || d == null || w == null) return false;
  final local = now.toLocal();
  if (d.allDay) return _day(local).isAfter(w);
  if (d.isUtc) return now.toUtc().isAfter(w);
  if (d.tzid != null) {
    return now.toUtc().isAfter(w.add(const Duration(hours: 12)));
  }
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  ).isAfter(w);
}

/// Open and due on the user's current day (see [taskDueDay]).
bool isTaskDueToday(Task t, DateTime now) {
  if (t.isClosed) return false;
  final d = taskDueDay(t);
  return d != null && d == _day(now.toLocal());
}

/// Sort key for due dates: the due day, then the wall clock.
int compareTasks(Task a, Task b, DateTime now) {
  final ao = isTaskOverdue(a, now), bo = isTaskOverdue(b, now);
  if (ao != bo) return ao ? -1 : 1;
  final aw = a.due?.wall, bw = b.due?.wall;
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
