import 'event.dart';
import 'ical.dart';
import 'task.dart' show ICalDate;

/// One occurrence of an [Event] (the event itself, or one instance of its
/// recurrence). Times are wall-clock fields as UTC-flagged [DateTime]s; zones
/// are not applied (see [ICalDate.wall]). [end] is exclusive.
class EventOccurrence {
  EventOccurrence({
    required this.event,
    required this.source,
    required this.start,
    required this.end,
    required this.allDay,
    this.recurrenceId,
    this.isOverride = false,
    this.unsupported = false,
  });

  /// The master event.
  final Event event;

  /// The event whose fields apply: the RECURRENCE-ID override, else [event].
  final Event source;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// The original start of this instance (as RECURRENCE-ID would name it), or
  /// null for a non-recurring event.
  final ICalDate? recurrenceId;

  /// True when a RECURRENCE-ID override replaced this instance.
  final bool isOverride;

  /// True when the recurrence rule could not be expanded and only the base
  /// occurrence is returned (see [Event.recurrenceUnsupported]).
  final bool unsupported;

  String get summary => source.summary;
  String get description => source.description;
  String get location => source.location;
  String? get status => source.status;
  bool get isCancelled => source.isCancelled;

  @override
  String toString() => 'EventOccurrence(${event.uid}, $start)';
}

extension EventRecurrence on Event {
  /// True when [rrule] (or an RDATE period) uses something
  /// [occurrencesBetween] does not expand. Such an event yields only its base
  /// occurrence.
  bool get recurrenceUnsupported => _plan(this).unsupported;

  /// The RECURRENCE-ID overrides of this resource, parsed from [siblingLines].
  List<Event> get overrides => _overrides(this);

  /// Occurrences that overlap `[from, to)`, in start order. See
  /// [occurrencesBetween].
  List<EventOccurrence> occurrences(DateTime from, DateTime to) =>
      occurrencesBetween(this, from, to);
}

const _day = Duration(days: 1);
const _maxOccurrences = 100000;

/// Expands [event] into the occurrences that overlap `[from, to)`.
///
/// [from] and [to] are compared with wall-clock fields (UTC-flagged
/// [DateTime]s): pass a local day boundary as `DateTime.utc(y, m, d)` for
/// all-day and floating events; UTC events are exact instants. All-day events
/// match by local date.
///
/// Supported: FREQ DAILY, WEEKLY, MONTHLY, YEARLY with INTERVAL, COUNT, UNTIL,
/// WKST, BYDAY (weekly and daily plain weekdays; monthly also with an ordinal
/// such as `-1FR`), BYMONTHDAY (monthly, also negative; yearly), BYMONTH
/// (yearly), plus EXDATE, RDATE and RECURRENCE-ID overrides (a moved or
/// edited instance replaces the original; a cancelled override stays in the
/// list with [EventOccurrence.isCancelled]; RANGE=THISANDFUTURE is applied to
/// the one instance only). Anything else (BYSETPOS, BYWEEKNO, BYYEARDAY,
/// BYHOUR, ..., SECONDLY..HOURLY, RDATE periods) returns just the base
/// occurrence with [EventOccurrence.unsupported] set. Time zones are not
/// applied: floating, UTC and TZID values all expand on their wall time.
List<EventOccurrence> occurrencesBetween(
    Event event, DateTime from, DateTime to) {
  final startWall = event.startWall;
  if (startWall == null) return const [];
  final length = event.length;
  final allDay = event.allDay;
  final out = <EventOccurrence>[];

  bool overlaps(DateTime s, DateTime e) =>
      s.isBefore(to) && (e.isAfter(from) || (e == s && !s.isBefore(from)));

  final plan = _plan(event);
  final overrides = _overrides(event);
  final overrideIds = <_Key>{
    for (final o in overrides)
      if (_recurrenceId(o) != null) _key(_recurrenceId(o)!)
  };

  if (plan.rule == null && event.rdates.isEmpty || plan.unsupported) {
    final s = startWall;
    final e = s.add(length);
    final id = event.isRecurring ? event.dtstart : null;
    final hit = id == null ? null : _matchOverride(overrides, id);
    if (hit == null) {
      if (overlaps(s, e)) {
        out.add(EventOccurrence(
            event: event,
            source: event,
            start: s,
            end: e,
            allDay: allDay,
            recurrenceId: id,
            unsupported: plan.unsupported));
      }
    }
    if (plan.unsupported || event.isRecurring) {
      _addOverrides(out, event, overrides, overlaps, plan.unsupported,
          skipBase: false, baseId: id);
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  final starts = <DateTime>{};
  final ex = _excluded(event);
  final lastDay = DateTime.utc(to.year, to.month, to.day);

  void emit(DateTime s) {
    if (!starts.add(s)) return;
    if (ex.contains(_Key(s, false)) ||
        ex.contains(_Key(DateTime.utc(s.year, s.month, s.day), true))) {
      return;
    }
    if (overrideIds.contains(_Key(s, false)) ||
        overrideIds
            .contains(_Key(DateTime.utc(s.year, s.month, s.day), true))) {
      return;
    }
    final e = s.add(length);
    if (overlaps(s, e)) {
      out.add(EventOccurrence(
          event: event,
          source: event,
          start: s,
          end: e,
          allDay: allDay,
          recurrenceId: _idFor(event.dtstart!, s)));
    }
  }

  final rule = plan.rule;
  if (rule != null) {
    final until = rule.until;
    var count = 0;
    var produced = 0;
    final startDate =
        DateTime.utc(startWall.year, startWall.month, startWall.day);
    final tod = startWall.difference(startDate);
    outer:
    for (var i = 0; i < 1000000; i++) {
      final period = rule.period(startDate, i);
      if (period.base.isAfter(lastDay)) break;
      for (final d in period.days) {
        if (d.isBefore(startDate)) continue;
        count++;
        if (rule.count != null && count > rule.count!) break outer;
        final s = d.add(tod);
        if (until != null && _afterUntil(s, until, allDay)) break outer;
        if (!s.isBefore(to)) break outer;
        emit(s);
        if (++produced > _maxOccurrences) break outer;
      }
    }
  } else {
    emit(startWall);
  }
  for (final r in plan.rdates) {
    if (r.isBefore(to)) emit(r);
  }
  _addOverrides(out, event, overrides, overlaps, false,
      skipBase: true, baseId: null);
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

void _addOverrides(
  List<EventOccurrence> out,
  Event event,
  List<Event> overrides,
  bool Function(DateTime, DateTime) overlaps,
  bool unsupported, {
  required bool skipBase,
  required ICalDate? baseId,
}) {
  for (final o in overrides) {
    final id = _recurrenceId(o);
    if (id == null) continue;
    final s = o.startWall ?? id.wall;
    if (s == null) continue;
    final e = o.dtstart == null && o.dtend == null && o.duration == null
        ? s.add(event.length)
        : s.add(o.dtstart == null ? event.length : o.length);
    if (!overlaps(s, e)) continue;
    out.add(EventOccurrence(
        event: event,
        source: o,
        start: s,
        end: e,
        allDay: o.dtstart?.allDay ?? event.allDay,
        recurrenceId: id,
        isOverride: true,
        unsupported: unsupported));
  }
}

Event? _matchOverride(List<Event> overrides, ICalDate id) {
  final k = _key(id);
  for (final o in overrides) {
    final oid = _recurrenceId(o);
    if (oid != null && _key(oid) == k) return o;
  }
  return null;
}

ICalDate _idFor(ICalDate first, DateTime s) {
  String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  final d = '${t(s.year, 4)}${t(s.month)}${t(s.day)}';
  if (first.allDay) return ICalDate(d, first.params);
  return ICalDate(
      '${d}T${t(s.hour)}${t(s.minute)}${t(s.second)}${first.isUtc ? 'Z' : ''}',
      first.params);
}

bool _afterUntil(DateTime s, ICalDate until, bool allDay) {
  final u = until.wall;
  if (u == null) return false;
  if (until.allDay || allDay) {
    return DateTime.utc(s.year, s.month, s.day)
        .isAfter(DateTime.utc(u.year, u.month, u.day));
  }
  return s.isAfter(u);
}

// ---- keys: an instance is named by its wall time, or by day if date-only ----

class _Key {
  const _Key(this.at, this.dateOnly);
  final DateTime at;
  final bool dateOnly;
  @override
  bool operator ==(Object o) =>
      o is _Key && o.at == at && o.dateOnly == dateOnly;
  @override
  int get hashCode => Object.hash(at, dateOnly);
}

_Key _key(ICalDate d) => _Key(d.wall ?? DateTime.utc(0), d.allDay);

ICalDate? _recurrenceId(Event o) {
  for (final l in o.extraLines) {
    if (!l.toUpperCase().startsWith('RECURRENCE-ID')) continue;
    var inQuote = false;
    for (var i = 0; i < l.length; i++) {
      if (l[i] == '"') inQuote = !inQuote;
      if (l[i] == ':' && !inQuote) {
        final head = l.substring(0, i);
        final semi = head.indexOf(';');
        final d = ICalDate(
            l.substring(i + 1).trim(), semi < 0 ? '' : head.substring(semi));
        return d.wall == null ? null : d;
      }
    }
  }
  return null;
}

List<Event> _overrides(Event e) {
  if (e.siblingLines.isEmpty) return const [];
  final text =
      'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${e.siblingLines.join('\r\n')}'
      '\r\nEND:VCALENDAR\r\n';
  try {
    return parseEvents(text).where((o) => _recurrenceId(o) != null).toList();
  } on ICalException {
    return const [];
  }
}

/// Values of every EXDATE line as keys.
Set<_Key> _excluded(Event e) {
  final out = <_Key>{};
  for (final v in _dateLines(e.exdates)) {
    final w = v.wall;
    if (w != null) out.add(_Key(w, v.allDay));
  }
  return out;
}

List<ICalDate> _dateLines(List<String> lines) {
  final out = <ICalDate>[];
  for (final l in lines) {
    var inQuote = false;
    for (var i = 0; i < l.length; i++) {
      if (l[i] == '"') inQuote = !inQuote;
      if (l[i] == ':' && !inQuote) {
        final head = l.substring(0, i);
        final semi = head.indexOf(';');
        final params = semi < 0 ? '' : head.substring(semi);
        for (final v in l.substring(i + 1).split(',')) {
          out.add(ICalDate(v.trim(), params));
        }
        break;
      }
    }
  }
  return out;
}

// ---- rule ----

class _Period {
  _Period(this.base, this.days);

  /// A date on or before every day of the period, for the stop test.
  final DateTime base;
  final List<DateTime> days;
}

class _Plan {
  _Plan(this.rule, this.rdates, this.unsupported);
  final _Rule? rule;
  final List<DateTime> rdates;
  final bool unsupported;
}

_Plan _plan(Event e) {
  var bad = false;
  _Rule? rule;
  final rr = e.rrule;
  if (rr != null && rr.isNotEmpty) {
    rule = _Rule.parse(rr);
    if (rule == null) bad = true;
  }
  final rdates = <DateTime>[];
  for (final l in e.rdates) {
    for (final d in _dateLines([l])) {
      final w = d.wall;
      if (w == null || d.params.toUpperCase().contains('PERIOD')) {
        bad = true;
      } else {
        rdates.add(w);
      }
    }
  }
  return _Plan(bad ? null : rule, rdates, bad);
}

DateTime _addMonths(int year, int month, int n) {
  final m = year * 12 + (month - 1) + n;
  return DateTime.utc(m ~/ 12, m % 12 + 1, 1);
}

int _daysIn(int y, int m) => DateTime.utc(y, m + 1, 0).day;

class _Rule {
  _Rule(this.freq, this.interval, this.count, this.until, this.byday,
      this.bymonthday, this.bymonth, this.wkst);
  final String freq;
  final int interval;
  final int? count;
  final ICalDate? until;
  final List<(int, int)> byday; // (ordinal or 0, weekday 1=MO..7=SU)
  final List<int> bymonthday;
  final List<int> bymonth;
  final int wkst;

  static const _wd = {
    'MO': 1,
    'TU': 2,
    'WE': 3,
    'TH': 4,
    'FR': 5,
    'SA': 6,
    'SU': 7
  };

  /// Null when the rule is outside what this expands.
  static _Rule? parse(String text) {
    final m = <String, String>{};
    for (final part in text.split(';')) {
      final i = part.indexOf('=');
      if (i < 1) return null;
      m[part.substring(0, i).toUpperCase()] = part.substring(i + 1).trim();
    }
    const known = {
      'FREQ',
      'INTERVAL',
      'COUNT',
      'UNTIL',
      'BYDAY',
      'BYMONTHDAY',
      'BYMONTH',
      'WKST'
    };
    if (!m.keys.every(known.contains)) return null;
    final freq = m['FREQ']?.toUpperCase();
    if (freq == null ||
        !{'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'}.contains(freq)) {
      return null;
    }
    final interval =
        m.containsKey('INTERVAL') ? int.tryParse(m['INTERVAL']!) : 1;
    if (interval == null || interval < 1) return null;
    int? count;
    if (m.containsKey('COUNT')) {
      count = int.tryParse(m['COUNT']!);
      if (count == null || count < 1) return null;
    }
    ICalDate? until;
    if (m.containsKey('UNTIL')) {
      until = ICalDate(m['UNTIL']!);
      if (until.wall == null) return null;
    }
    final byday = <(int, int)>[];
    if (m.containsKey('BYDAY')) {
      for (final v in m['BYDAY']!.split(',')) {
        final mm = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$')
            .firstMatch(v.trim().toUpperCase());
        if (mm == null) return null;
        final ord = int.tryParse(mm.group(1) ?? '') ?? 0;
        if (ord != 0 && freq != 'MONTHLY') return null;
        if (ord.abs() > 5) return null;
        byday.add((ord, _wd[mm.group(2)]!));
      }
    }
    List<int>? ints(String k, int lo, int hi) {
      if (!m.containsKey(k)) return const [];
      final r = <int>[];
      for (final v in m[k]!.split(',')) {
        final n = int.tryParse(v.trim());
        if (n == null || n == 0 || n < lo || n > hi) return null;
        r.add(n);
      }
      return r;
    }

    final bmd = ints('BYMONTHDAY', -31, 31);
    final bm = ints('BYMONTH', 1, 12);
    if (bmd == null || bm == null) return null;
    final wk = m.containsKey('WKST') ? _wd[m['WKST']!.toUpperCase()] : 1;
    if (wk == null) return null;
    switch (freq) {
      case 'DAILY' || 'WEEKLY':
        if (bmd.isNotEmpty || bm.isNotEmpty) return null;
      case 'MONTHLY':
        if (bm.isNotEmpty || (bmd.isNotEmpty && byday.isNotEmpty)) return null;
      case 'YEARLY':
        if (byday.isNotEmpty) return null;
    }
    return _Rule(freq, interval, count, until, byday, bmd, bm, wk);
  }

  _Period period(DateTime start, int i) {
    switch (freq) {
      case 'DAILY':
        final d = start.add(_day * (i * interval));
        final ok = byday.isEmpty || byday.any((b) => b.$2 == d.weekday);
        return _Period(d, ok ? [d] : const []);
      case 'WEEKLY':
        final first = start.subtract(_day * ((start.weekday - wkst + 7) % 7));
        final ws = first.add(_day * (7 * interval * i));
        final wds =
            byday.isEmpty ? [start.weekday] : [for (final b in byday) b.$2];
        final offs = {for (final w in wds) (w - wkst + 7) % 7}.toList()..sort();
        return _Period(ws, [for (final o in offs) ws.add(_day * o)]);
      case 'MONTHLY':
        final mo = _addMonths(start.year, start.month, i * interval);
        final n = _daysIn(mo.year, mo.month);
        final days = <int>{};
        if (byday.isEmpty) {
          final src = bymonthday.isEmpty ? [start.day] : bymonthday;
          for (final d in src) {
            final x = d > 0 ? d : n + d + 1;
            if (x >= 1 && x <= n) days.add(x);
          }
        } else {
          for (final (ord, wd) in byday) {
            final all = [
              for (var d = 1; d <= n; d++)
                if (DateTime.utc(mo.year, mo.month, d).weekday == wd) d
            ];
            if (ord == 0) {
              days.addAll(all);
            } else {
              final idx = ord > 0 ? ord - 1 : all.length + ord;
              if (idx >= 0 && idx < all.length) days.add(all[idx]);
            }
          }
        }
        final sorted = days.toList()..sort();
        return _Period(
            mo, [for (final d in sorted) DateTime.utc(mo.year, mo.month, d)]);
      default: // YEARLY
        final y = start.year + i * interval;
        final months =
            bymonth.isEmpty ? [start.month] : (List.of(bymonth)..sort());
        final out = <DateTime>[];
        for (final mo in months) {
          final n = _daysIn(y, mo);
          final src = bymonthday.isEmpty ? [start.day] : bymonthday;
          final ds = <int>{
            for (final d in src)
              if ((d > 0 ? d : n + d + 1) >= 1 && (d > 0 ? d : n + d + 1) <= n)
                d > 0 ? d : n + d + 1
          }.toList()
            ..sort();
          for (final d in ds) {
            out.add(DateTime.utc(y, mo, d));
          }
        }
        return _Period(DateTime.utc(y, 1, 1), out);
    }
  }
}
