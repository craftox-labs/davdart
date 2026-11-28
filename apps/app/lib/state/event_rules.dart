import 'package:davdart/davdart.dart';

/// The current moment as wall-clock fields in the viewer's zone (UTC-flagged).
///
/// Time policy: timed values are compared in the viewer's zone. `Z` and TZID
/// values are converted to it (`ICalDate.localWall`, so 09:00Z is 16:00 at
/// UTC+7 and groups into that local day); floating times and all-day dates
/// stay as written. New and edited UTC events convert the local input back.
DateTime wallNow(DateTime now) => LocalZone.wallOf(now);

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
  final year = wallNow(now ?? DateTime.now()).year;
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

/// The date-time value for viewer-zone [wall]. With a timed [like] its flavour
/// carries over (UTC keeps its Z, a known TZID zone is kept and the wall is
/// converted into it, floating stays floating). Without [like] a timed value is
/// written as UTC (`...Z`, the CalDAV convention). With [allDay] the result is
/// a date (`VALUE=DATE`).
ICalDate eventDate(DateTime wall, {bool allDay = false, ICalDate? like}) {
  String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  if (allDay) {
    return ICalDate(
      '${t(wall.year, 4)}${t(wall.month)}${t(wall.day)}',
      ';VALUE=DATE',
    );
  }
  final w = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  );
  if (like != null && !like.allDay) return ICalDate.fromLocalWall(w, like);
  return ICalDate.fromLocalWall(w, const ICalDate('20000101T000000Z'));
}

/// [line] (an EXDATE or RDATE property line) with every value moved by
/// [delta] on the local wall clock; the name, parameters and each value's
/// flavour (Z, TZID, date) are kept. PERIOD values and lines that do not
/// parse are returned as they are.
String shiftDateLine(String line, Duration delta) {
  var inQuote = false;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '"') inQuote = !inQuote;
    if (line[i] != ':' || inQuote) continue;
    final head = line.substring(0, i);
    final semi = head.indexOf(';');
    final params = semi < 0 ? '' : head.substring(semi);
    if (params.toUpperCase().contains('PERIOD')) return line;
    final vals = [
      for (final v in line.substring(i + 1).split(','))
        ICalDate(v.trim(), params).shifted(delta).value,
    ];
    return '$head:${vals.join(',')}';
  }
  return line;
}

/// The raw lines of a series' other VEVENTs (RECURRENCE-ID overrides) with
/// RECURRENCE-ID, DTSTART and DTEND moved by [delta], so each override keeps
/// naming the shifted instance and keeps its length.
List<String> shiftSiblingLines(List<String> lines, Duration delta) {
  final re = RegExp(
    r'^(RECURRENCE-ID|DTSTART|DTEND)[;:]',
    caseSensitive: false,
  );
  return [for (final l in lines) re.hasMatch(l) ? shiftDateLine(l, delta) : l];
}

/// The when fields of an event as the page edits them: all day, the start and
/// the end — for an all-day event the last day, inclusive.
typedef EventWhen = ({bool allDay, DateTime start, DateTime end});

/// The when fields of [e]: its start (or today), and the end it shows (an
/// all-day event's last day).
EventWhen eventWhenOf(Event e, [DateTime? now]) {
  final allDay = e.allDay;
  final start = e.startWall ?? wallDay(wallNow(now ?? DateTime.now()));
  final endWall = e.endWall ?? start;
  var end = allDay ? endWall.subtract(const Duration(days: 1)) : endWall;
  if (end.isBefore(start)) end = start;
  return (allDay: allDay, start: start, end: end);
}

DateTime _wallDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// [when] switched to all day (or back): the dates stay; a timed event gets
/// 09:00-10:00 on its first day (the last day at 10:00 when it spans days).
EventWhen eventAllDaySwitched(EventWhen when, bool allDay) {
  if (allDay == when.allDay) return when;
  if (allDay) {
    final start = _wallDay(when.start);
    var end = _wallDay(when.end);
    if (end.isBefore(start)) end = start;
    return (allDay: true, start: start, end: end);
  }
  final start = _wallDay(when.start).add(const Duration(hours: 9));
  var end = _wallDay(when.end).add(const Duration(hours: 10));
  if (end.isBefore(start)) end = start.add(const Duration(hours: 1));
  return (allDay: false, start: start, end: end);
}

/// [when] with the start moved to [date] and/or [minutes] into the day; the
/// end moves by the same amount, so the length stays.
EventWhen eventStartMoved(EventWhen when, {DateTime? date, int? minutes}) {
  final length = when.end.difference(when.start);
  final day = date == null ? _wallDay(when.start) : _wallDay(date);
  final mins = when.allDay
      ? 0
      : minutes ?? when.start.hour * 60 + when.start.minute;
  final start = day.add(Duration(minutes: mins));
  return (allDay: when.allDay, start: start, end: start.add(length));
}

/// [when] with the end set to [date] and/or [minutes] into the day.
EventWhen eventEndSet(EventWhen when, {DateTime? date, int? minutes}) {
  final day = date == null ? _wallDay(when.end) : _wallDay(date);
  final mins = when.allDay
      ? 0
      : minutes ?? when.end.hour * 60 + when.end.minute;
  return (
    allDay: when.allDay,
    start: when.start,
    end: day.add(Duration(minutes: mins)),
  );
}

/// The status values an event row offers: none, confirmed, tentative,
/// cancelled.
const eventStatusWords = [
  ('', 'none'),
  ('CONFIRMED', 'confirmed'),
  ('TENTATIVE', 'tentative'),
  ('CANCELLED', 'cancelled'),
];

/// The word a status shows ('none' when it has none).
String eventStatusName(String? status) => eventStatusWords
    .firstWhere(
      (e) => e.$1 == (status ?? ''),
      orElse: () => (status ?? '', status ?? ''),
    )
    .$2;

/// The repeat frequencies a repeat row offers, as (value, label).
const repeatFrequencies = [
  ('', 'Does not repeat'),
  ('DAILY', 'Daily'),
  ('WEEKLY', 'Weekly'),
  ('MONTHLY', 'Monthly'),
  ('YEARLY', 'Yearly'),
];

/// The unit of a repeat frequency, for 'every 2 weeks'.
const _freqUnits = {
  'DAILY': 'day',
  'WEEKLY': 'week',
  'MONTHLY': 'month',
  'YEARLY': 'year',
};

/// A repeat rule as one line for the row that opens the repeat picker:
/// 'Does not repeat', 'Weekly on Mon, Wed', 'Every 2 weeks', 'Monthly, 4
/// times', 'Yearly, until 31 Dec 2026', or the raw rule when it is one the
/// picker cannot write back.
String repeatLabel(String? rrule) {
  if (rrule == null || rrule.trim().isEmpty) return 'Does not repeat';
  final rule = RepeatRule.parse(rrule);
  if (rule == null) return rrule.trim();
  final unit = _freqUnits[rule.freq] ?? rule.freq.toLowerCase();
  final every = rule.interval > 1
      ? 'Every ${rule.interval} ${unit}s'
      : repeatFrequencies
            .firstWhere(
              (e) => e.$1 == rule.freq,
              orElse: () => (rule.freq, rule.freq),
            )
            .$2;
  final days = rule.freq == 'WEEKLY' && rule.weekdays.isNotEmpty
      ? ' on ${[for (final d in rule.weekdays) _weekdays[d - 1]].join(', ')}'
      : '';
  final end = switch ((rule.count, rule.until)) {
    (final int n, _) => ', $n times',
    (_, final DateTime u) => ', until ${dayLabel(u)}',
    _ => '',
  };
  return '$every$days$end';
}
