/// A simple repeat rule the event editor can show and change: FREQ, INTERVAL,
/// BYDAY (weekly only) and one end (COUNT or UNTIL date). Anything else in an
/// RRULE (BYMONTHDAY, BYSETPOS, ordinals, a time UNTIL, ...) makes [parse]
/// return null and the editor keeps the raw rule.
class RepeatRule {
  const RepeatRule({
    required this.freq,
    this.interval = 1,
    this.weekdays = const [],
    this.count,
    this.until,
    this.untilTimed = false,
  });

  /// DAILY, WEEKLY, MONTHLY or YEARLY.
  final String freq;
  final int interval;

  /// Weekly only: weekday numbers, 1 = Monday .. 7 = Sunday, ascending.
  final List<int> weekdays;

  /// At most one of [count] and [until] is set; both null repeats forever.
  final int? count;

  /// The last day (a date, wall-clock fields as UTC).
  final DateTime? until;

  /// Write [until] as `YYYYMMDDT235959Z` (RFC 5545 wants a date-time UNTIL for
  /// a timed event) instead of a date.
  final bool untilTimed;

  static const freqs = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
  static const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// The rule of [rrule], or null when it is empty or uses anything this
  /// class cannot write back unchanged.
  static RepeatRule? parse(String? rrule) {
    if (rrule == null || rrule.trim().isEmpty) return null;
    final parts = <String, String>{};
    for (final p in rrule.trim().split(';')) {
      final i = p.indexOf('=');
      if (i <= 0) return null;
      final k = p.substring(0, i).toUpperCase();
      if (parts.containsKey(k)) return null;
      parts[k] = p.substring(i + 1).toUpperCase();
    }
    const known = {'FREQ', 'INTERVAL', 'BYDAY', 'COUNT', 'UNTIL', 'WKST'};
    if (!parts.keys.every(known.contains)) return null;
    final freq = parts['FREQ'];
    if (freq == null || !freqs.contains(freq)) return null;
    if (parts.containsKey('WKST') && parts['WKST'] != 'MO') return null;
    final interval = int.tryParse(parts['INTERVAL'] ?? '1');
    if (interval == null || interval < 1) return null;
    var weekdays = <int>[];
    if (parts.containsKey('BYDAY')) {
      if (freq != 'WEEKLY') return null;
      for (final d in parts['BYDAY']!.split(',')) {
        final n = _days.indexOf(d);
        if (n < 0) return null;
        weekdays.add(n + 1);
      }
      weekdays = (weekdays.toSet().toList()..sort());
    }
    if (parts.containsKey('COUNT') && parts.containsKey('UNTIL')) return null;
    int? count;
    if (parts.containsKey('COUNT')) {
      count = int.tryParse(parts['COUNT']!);
      if (count == null || count < 1) return null;
    }
    DateTime? until;
    var untilTimed = false;
    if (parts.containsKey('UNTIL')) {
      // A date, or the end-of-day UTC form this class writes for timed
      // events; any other time stays a custom rule.
      final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(T235959Z)?$')
          .firstMatch(parts['UNTIL']!);
      if (m == null) return null;
      until = DateTime.utc(
        int.parse(m[1]!),
        int.parse(m[2]!),
        int.parse(m[3]!),
      );
      if (until.year != int.parse(m[1]!) ||
          until.month != int.parse(m[2]!) ||
          until.day != int.parse(m[3]!)) {
        return null;
      }
      untilTimed = m[4] != null;
    }
    return RepeatRule(
      freq: freq,
      interval: interval,
      weekdays: weekdays,
      count: count,
      until: until,
      untilTimed: untilTimed,
    );
  }

  RepeatRule copyWith({
    String? freq,
    int? interval,
    List<int>? weekdays,
    int? count,
    DateTime? until,
    bool? untilTimed,
    bool clearEnd = false,
  }) {
    final f = freq ?? this.freq;
    return RepeatRule(
      freq: f,
      interval: interval ?? this.interval,
      weekdays: f == 'WEEKLY' ? (weekdays ?? this.weekdays) : const [],
      count: clearEnd ? null : (count ?? this.count),
      until: clearEnd ? null : (until ?? this.until),
      untilTimed: untilTimed ?? this.untilTimed,
    );
  }

  /// The RRULE value (without `RRULE:`).
  String toRrule() {
    final b = StringBuffer('FREQ=$freq');
    if (interval > 1) b.write(';INTERVAL=$interval');
    if (freq == 'WEEKLY' && weekdays.isNotEmpty) {
      final w = weekdays.toList()..sort();
      b.write(';BYDAY=${w.map((d) => _days[d - 1]).join(',')}');
    }
    if (count != null) {
      b.write(';COUNT=$count');
    } else if (until != null) {
      final u = until!;
      b.write(
        ';UNTIL=${u.year.toString().padLeft(4, '0')}'
        '${u.month.toString().padLeft(2, '0')}'
        '${u.day.toString().padLeft(2, '0')}'
        '${untilTimed ? 'T235959Z' : ''}',
      );
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is RepeatRule && other.toRrule() == toRrule();

  @override
  int get hashCode => toRrule().hashCode;
}
