import 'package:davdart/davdart.dart';

/// The current moment as wall-clock fields (UTC-flagged). Event times carry no
/// zone in the app (the core has no time zone database), so "now" is the
/// user's local clock read the same way.
DateTime wallNow(DateTime now) {
  final l = now.toLocal();
  return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second);
}

/// Midnight (UTC-flagged) of the wall day of [d].
DateTime wallDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// A run of occurrences under one heading of the agenda.
class AgendaGroup {
  const AgendaGroup(this.id, this.label, this.items);
  final String id;
  final String label;
  final List<EventOccurrence> items;
}

int _byWhen(EventOccurrence a, EventOccurrence b) {
  final c = wallDay(a.start).compareTo(wallDay(b.start));
  if (c != 0) return c;
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final s = a.start.compareTo(b.start);
  return s != 0 ? s : a.summary.compareTo(b.summary);
}

/// Occurrences of [events] from the start of [from]'s day for [days] days,
/// grouped Today, Tomorrow, This week (days 2 to 6) and Later (day 7 on).
/// Empty groups are left out. An occurrence that began earlier and is still
/// running counts as Today.
List<AgendaGroup> upcomingGroups(
  Iterable<Event> events,
  DateTime from,
  int days,
) {
  final today = wallDay(wallNow(from));
  final to = today.add(Duration(days: days));
  final all = <EventOccurrence>[
    for (final e in events) ...e.occurrences(today, to),
  ]..sort(_byWhen);
  final by = <String, List<EventOccurrence>>{
    'today': [],
    'tomorrow': [],
    'week': [],
    'later': [],
  };
  for (final o in all) {
    final d = wallDay(o.start).difference(today).inDays;
    by[d <= 0
            ? 'today'
            : d == 1
            ? 'tomorrow'
            : d < 7
            ? 'week'
            : 'later']!
        .add(o);
  }
  const labels = {
    'today': 'Today',
    'tomorrow': 'Tomorrow',
    'week': 'This week',
    'later': 'Later',
  };
  return [
    for (final e in by.entries)
      if (e.value.isNotEmpty) AgendaGroup(e.key, labels[e.key]!, e.value),
  ];
}

/// Occurrences that ended before [from]'s day, within the last [days] days,
/// latest first.
List<EventOccurrence> pastAgenda(
  Iterable<Event> events,
  DateTime from,
  int days,
) {
  final today = wallDay(wallNow(from));
  final since = today.subtract(Duration(days: days));
  return [
    for (final e in events)
      for (final o in e.occurrences(since, today))
        if (!o.end.isAfter(today)) o,
  ]..sort((a, b) => _byWhen(b, a));
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Fri 21 Nov`, with the year when it is not [now]'s year.
String dayLabel(DateTime d, [DateTime? now]) {
  final base = '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
  final year = (now ?? DateTime.now()).toLocal().year;
  return d.year == year ? base : '$base ${d.year}';
}

/// `09:05` (24 hour).
String timeLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// When an event happens, as one line: `Fri 21 Nov, 09:00-10:00`,
/// `Fri 21 Nov, all day`, `Fri 21 Nov - Sun 23 Nov, all day`, or two full
/// stamps for a timed event over several days. Empty without a start.
String eventWhen(Event e, [DateTime? now]) {
  final s = e.startWall;
  if (s == null) return '';
  final end = e.endWall ?? s;
  if (e.allDay) {
    final last = end.subtract(const Duration(days: 1));
    return !last.isAfter(s)
        ? '${dayLabel(s, now)}, all day'
        : '${dayLabel(s, now)} - ${dayLabel(last, now)}, all day';
  }
  if (end == s) return '${dayLabel(s, now)}, ${timeLabel(s)}';
  if (wallDay(end) == wallDay(s)) {
    return '${dayLabel(s, now)}, ${timeLabel(s)}-${timeLabel(end)}';
  }
  return '${dayLabel(s, now)} ${timeLabel(s)} - '
      '${dayLabel(end, now)} ${timeLabel(end)}';
}

/// The date-time value for [wall]. With a timed [like] its flavour carries
/// over (a Z for UTC, the TZID parameter for a zoned time); otherwise it is a
/// floating time. With [allDay] the result is a date.
ICalDate eventDate(DateTime wall, {bool allDay = false, ICalDate? like}) {
  String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  final date = '${t(wall.year, 4)}${t(wall.month)}${t(wall.day)}';
  if (allDay) return ICalDate(date, ';VALUE=DATE');
  final stamp = '${date}T${t(wall.hour)}${t(wall.minute)}00';
  if (like != null && !like.allDay) {
    return ICalDate(like.isUtc ? '${stamp}Z' : stamp, like.params);
  }
  return ICalDate(stamp);
}
