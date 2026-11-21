import 'event.dart';
import 'event_recurrence.dart';
import 'task.dart';

/// One occurrence of a [Task]'s DUE date: the task itself, or one instance
/// of its recurrence. [start] is the due moment in viewer-zone wall fields
/// (UTC-flagged; midnight for an all-day date), [day] its viewer-zone day.
class TaskOccurrence {
  const TaskOccurrence(this.task, this.start, this.allDay);
  final Task task;
  final DateTime start;
  final bool allDay;
  DateTime get day => DateTime.utc(start.year, start.month, start.day);
  @override
  String toString() => 'TaskOccurrence(${task.uid}, $start)';
}

/// The occurrences of [t]'s DUE date in the viewer-zone window `[from, to)`
/// (UTC-flagged wall fields, as for [occurrencesBetween]). A task with an
/// RRULE (or RDATE) is expanded with the event expander, using DUE as the
/// first instance and honouring its EXDATE lines; a plain task gives its due
/// day if it falls in the window. Tasks without a due date give nothing.
/// Completion is not considered (closed tasks are returned too).
List<TaskOccurrence> taskOccurrencesBetween(
    Task t, DateTime from, DateTime to) {
  final due = t.due;
  final w = due?.localWall;
  if (due == null || w == null) return const [];
  if (!t.isRecurring) {
    final d = DateTime.utc(w.year, w.month, w.day);
    return !d.isBefore(DateTime.utc(from.year, from.month, from.day)) &&
            d.isBefore(to)
        ? [TaskOccurrence(t, w, due.allDay)]
        : const [];
  }
  bool line(String l, String name) =>
      l.toUpperCase().startsWith('$name;') ||
      l.toUpperCase().startsWith('$name:');
  final ev = Event(
    uid: t.uid,
    dtstart: due,
    duration: 'PT0S',
    rrule: t.rrule,
    exdates: [
      for (final l in t.extraLines)
        if (line(l, 'EXDATE')) l
    ],
    rdates: [
      for (final l in t.extraLines)
        if (line(l, 'RDATE')) l
    ],
  );
  return [
    for (final o
        in occurrencesBetween(ev, from, to.add(const Duration(days: 1))))
      if (!o.start.isBefore(DateTime.utc(from.year, from.month, from.day)) &&
          DateTime.utc(o.start.year, o.start.month, o.start.day).isBefore(to))
        TaskOccurrence(t, o.start, due.allDay),
  ];
}

/// The items on one viewer-zone calendar day.
class DayBucket {
  DayBucket(this.day);
  final DateTime day;
  final List<EventOccurrence> events = [];
  final List<TaskOccurrence> tasks = [];
  int get count => events.length + tasks.length;
  bool get isEmpty => count == 0;
}

/// Per viewer-zone day items for the window of days `[from, to)` (UTC
/// midnights; e.g. a month grid). Only days that have items appear in the
/// map, keyed by UTC-midnight date.
///
/// Events come from [occurrencesBetween] (recurrence expanded); a multi-day
/// or midnight-crossing occurrence is listed on every day it touches. Tasks
/// count on their DUE day (recurring tasks once per occurrence); closed
/// tasks and cancelled events are left out unless asked for. Items on a day
/// are in start order, all-day first.
Map<DateTime, DayBucket> bucketByDay({
  Iterable<Event> events = const [],
  Iterable<Task> tasks = const [],
  required DateTime from,
  required DateTime to,
  bool includeClosedTasks = false,
  bool includeCancelled = false,
}) {
  final out = <DateTime, DayBucket>{};
  DayBucket at(DateTime d) => out.putIfAbsent(d, () => DayBucket(d));
  final lo = DateTime.utc(from.year, from.month, from.day);
  final hi = DateTime.utc(to.year, to.month, to.day);
  const oneDay = Duration(days: 1);
  for (final e in events) {
    for (final o in occurrencesBetween(e, lo, hi)) {
      if (o.isCancelled && !includeCancelled) continue;
      var d = DateTime.utc(o.start.year, o.start.month, o.start.day);
      final last = o.end.isAfter(o.start)
          ? o.end.subtract(const Duration(seconds: 1))
          : o.start;
      final lastDay = DateTime.utc(last.year, last.month, last.day);
      for (; !d.isAfter(lastDay); d = d.add(oneDay)) {
        if (d.isBefore(lo) || !d.isBefore(hi)) continue;
        at(d).events.add(o);
      }
    }
  }
  for (final t in tasks) {
    if (t.isClosed && !includeClosedTasks) continue;
    for (final o in taskOccurrencesBetween(t, lo, hi)) {
      at(o.day).tasks.add(o);
    }
  }
  for (final b in out.values) {
    b.events.sort((a, c) {
      if (a.allDay != c.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(c.start);
    });
    b.tasks.sort((a, c) {
      if (a.allDay != c.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(c.start);
    });
  }
  return out;
}
