import 'package:timezone/timezone.dart' as tz;

import 'rank.dart';
import 'zone.dart';

/// A date or date-time property value of a task (DUE, DTSTART), kept as the
/// raw iCalendar text plus its raw parameters, so a round trip never shifts
/// it: `20261125`, `20261125T090000Z`, or `20261125T090000` with
/// `;TZID=Europe/Berlin`.
class ICalDate {
  const ICalDate(this.value, [this.params = '']);

  /// A UTC date-time.
  factory ICalDate.utc(DateTime d) {
    final u = d.toUtc();
    String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return ICalDate(
      '${t(u.year, 4)}${t(u.month)}${t(u.day)}T'
      '${t(u.hour)}${t(u.minute)}${t(u.second)}Z',
    );
  }

  /// An all-day date.
  factory ICalDate.date(int year, int month, int day) {
    String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return ICalDate('${t(year, 4)}${t(month)}${t(day)}', ';VALUE=DATE');
  }

  /// Raw value text.
  final String value;

  /// Raw parameter text such as `;TZID=Europe/Berlin` or `;VALUE=DATE`.
  final String params;

  bool get allDay => value.length == 8;
  bool get isUtc => value.endsWith('Z');

  /// The TZID parameter, or null.
  String? get tzid => RegExp(
    r'TZID="?([^;":]+)"?',
    caseSensitive: false,
  ).firstMatch(params)?.group(1);

  /// The wall-clock fields as written, as a UTC-flagged [DateTime]: no zone
  /// is applied. Null if the value does not parse.
  DateTime? get wall {
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})Z?)?$')
        .firstMatch(value.trim());
    if (m == null) return null;
    final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i) ?? '0')];
    return DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]);
  }

  /// The zone of a timed TZID value, or null when there is no TZID, the value
  /// is UTC or all-day, or the TZID is not in the time zone database (such a
  /// value is then treated as floating).
  tz.Location? get _zone {
    if (allDay || isUtc) return null;
    final id = tzid;
    return id == null ? null : LocalZone.location(id);
  }

  /// True for a timed value without a zone: no TZID, or an unknown one.
  bool get isFloating => !allDay && !isUtc && _zone == null;

  /// The exact moment (UTC) of a timed value, or null for an all-day date or
  /// an unparseable value. `Z` is exact, a known TZID is resolved through the
  /// time zone database, floating (and unknown-TZID) times are read in the
  /// viewer's zone ([LocalZone]).
  DateTime? toInstant() {
    final w = wall;
    if (w == null || allDay) return null;
    if (isUtc) return w;
    final z = _zone;
    return z == null ? LocalZone.instantOf(w) : LocalZone.instantIn(z, w);
  }

  /// The wall-clock fields in the viewer's zone (UTC-flagged [DateTime]).
  /// `Z` and known-TZID values are converted from their instant; floating,
  /// unknown-TZID and all-day values stay at their written wall time.
  /// Events use this for expansion, grouping and display.
  DateTime? get localWall {
    final w = wall;
    if (w == null || allDay) return w;
    return localWallOf(w);
  }

  /// [w], wall fields in this value's own flavour (UTC for `Z`, the TZID zone,
  /// or floating), as viewer-zone wall fields.
  DateTime localWallOf(DateTime w) {
    if (allDay) return w;
    if (isUtc) return LocalZone.wallOf(w);
    final z = _zone;
    return z == null ? w : LocalZone.wallOf(LocalZone.instantIn(z, w));
  }

  /// The viewer-zone calendar day (UTC midnight) of this value: the written
  /// date for an all-day or floating value, the converted date for a timed
  /// `Z` or TZID value. Null if it does not parse.
  DateTime? get localDay {
    final l = localWall;
    return l == null ? null : DateTime.utc(l.year, l.month, l.day);
  }

  /// The value for viewer-zone wall [w] in the flavour of [like]: UTC keeps
  /// its `Z`, a known TZID is converted back into that zone and kept, floating
  /// and all-day are written as the same fields. Inverse of [localWall].
  static ICalDate fromLocalWall(DateTime w, ICalDate like) {
    String t(int n, [int l = 2]) => n.toString().padLeft(l, '0');
    if (like.allDay) {
      return ICalDate('${t(w.year, 4)}${t(w.month)}${t(w.day)}', like.params);
    }
    var x = w;
    if (like.isUtc) {
      x = LocalZone.instantOf(w);
    } else {
      final z = like._zone;
      if (z != null) x = LocalZone.wallIn(z, LocalZone.instantOf(w));
    }
    return ICalDate(
      '${t(x.year, 4)}${t(x.month)}${t(x.day)}T${t(x.hour)}${t(x.minute)}'
      '${t(x.second)}${like.isUtc ? 'Z' : ''}',
      like.params,
    );
  }

  /// This value moved by [d] on the local wall clock (an all-day date moves
  /// by whole days). Unchanged when it does not parse.
  ICalDate shifted(Duration d) {
    final w = localWall;
    if (w == null) return this;
    final n = allDay ? w.add(Duration(days: d.inDays)) : w.add(d);
    return fromLocalWall(n, this);
  }

  @override
  bool operator ==(Object other) =>
      other is ICalDate && other.value == value && other.params == params;
  @override
  int get hashCode => Object.hash(value, params);
  @override
  String toString() => 'ICalDate($value$params)';
}

/// A task, stored as an iCalendar VTODO (RFC 5545 section 3.6.2).
///
/// Properties this core does not model (VALARM, ATTACH, RDATE, EXDATE,
/// X-properties, extra RELATED-TO relations, ...) are kept as raw lines and
/// written back, so a task edited here loses nothing another client put there.
class Task {
  Task({
    required this.uid,
    this.summary = '',
    this.description = '',
    List<String>? categories,
    this.status,
    this.percentComplete,
    this.priority,
    this.due,
    this.dtstart,
    DateTime? completed,
    this.rrule,
    this.parentUid,
    DateTime? created,
    DateTime? lastModified,
    DateTime? dtstamp,
    List<String>? extraLines,
    List<String>? calendarLines,
    List<String>? siblingLines,
    Map<String, String>? propertyParams,
    this.href,
    this.etag,
  }) : categories = categories ?? <String>[],
       created = created?.toUtc(),
       lastModified = lastModified?.toUtc(),
       completed = completed?.toUtc(),
       dtstamp = (dtstamp ?? DateTime.now()).toUtc(),
       extraLines = extraLines ?? <String>[],
       calendarLines = calendarLines ?? <String>[],
       siblingLines = siblingLines ?? <String>[],
       propertyParams = propertyParams ?? <String, String>{};

  final String uid;
  String summary;
  String description;
  List<String> categories;

  /// NEEDS-ACTION, IN-PROCESS, COMPLETED or CANCELLED, or null (which means
  /// NEEDS-ACTION per the RFC).
  String? status;

  /// 0..100, or null.
  int? percentComplete;

  /// 0 (undefined), 1 (highest) .. 9 (lowest), or null.
  int? priority;
  ICalDate? due;
  ICalDate? dtstart;

  /// When the task was completed (UTC), or null.
  DateTime? completed;

  /// The raw RRULE value (for example `FREQ=WEEKLY;BYDAY=MO`), or null.
  /// Preserved, never expanded.
  String? rrule;

  /// UID of the parent task or note (`RELATED-TO;RELTYPE=PARENT`), or null.
  String? parentUid;
  DateTime? created;
  DateTime? lastModified;
  DateTime dtstamp;

  /// Raw property lines (and nested components such as VALARM) not modelled.
  final List<String> extraLines;

  /// Raw VCALENDAR-level lines (VTIMEZONE, X-WR-*, ...), written back first.
  final List<String> calendarLines;

  /// Raw lines of other VTODOs of the same resource (recurrence overrides).
  final List<String> siblingLines;

  /// Raw parameter text of SUMMARY/DESCRIPTION (for example `;LANGUAGE=de`).
  final Map<String, String> propertyParams;

  /// Server-side location and entity tag, set by the CalDAV client.
  String? href;
  String? etag;

  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';

  /// Completed or cancelled.
  bool get isClosed => isCompleted || isCancelled;
  bool get isRecurring => rrule != null && rrule!.isNotEmpty;

  /// The board status word (`backlog`, `todo`, `doing`, `blocked`, `review`, `done`,
  /// `canceled`): a `status-*` tag wins (unless the task is closed and the tag
  /// says it is open), else derived from [status].
  String get boardStatus {
    for (final c in categories) {
      if (!c.startsWith('status-')) continue;
      final word = c.substring(7);
      // A client that closed the task (STATUS:COMPLETED/CANCELLED) does not
      // touch our tag: a closed task cannot still be todo or doing.
      if (isClosed && !const {'done', 'canceled', 'cancelled'}.contains(word)) {
        break;
      }
      return word;
    }
    return switch (status) {
      'COMPLETED' => 'done',
      'IN-PROCESS' => 'doing',
      'CANCELLED' => 'canceled',
      _ => 'todo',
    };
  }

  /// Marks the task done: COMPLETED, 100 percent, [completed] set to [now].
  /// A leftover `status-*` tag is replaced by `status-done`.
  void complete(DateTime now) {
    status = 'COMPLETED';
    percentComplete = 100;
    completed = now.toUtc();
    _retag('done');
  }

  /// Reopens a closed task: NEEDS-ACTION, no completion time or percentage.
  void reopen() {
    status = 'NEEDS-ACTION';
    percentComplete = null;
    completed = null;
    _retag('todo');
  }

  /// Sets a board status word and keeps [status] in step (done and
  /// cancelled close the task, doing is IN-PROCESS, anything else
  /// NEEDS-ACTION); the `status-*` tag is written only if one existed or the
  /// word has no RFC equivalent.
  void setBoardStatus(String word, DateTime now) {
    switch (word) {
      case 'done':
        status = 'COMPLETED';
        percentComplete = 100;
        completed = now.toUtc();
      case 'canceled':
      case 'cancelled':
        status = 'CANCELLED';
        completed = null;
      case 'doing':
        status = 'IN-PROCESS';
        completed = null;
        if (percentComplete == 100) percentComplete = null;
      default:
        status = 'NEEDS-ACTION';
        completed = null;
        if (percentComplete == 100) percentComplete = null;
    }
    _retag(word);
  }

  void _retag(String word) {
    final had = categories.any((c) => c.startsWith('status-'));
    categories.removeWhere((c) => c.startsWith('status-'));
    const rfc = {'todo', 'doing', 'done', 'canceled', 'cancelled'};
    if (had || !rfc.contains(word)) categories.add('status-$word');
  }

  /// Manual order in a board column (`X-DAVDART-RANK`): lower first, null
  /// for none. Kept in [extraLines].
  double? get rank => rankOfLines(extraLines);
  set rank(double? v) => setRankInLines(extraLines, v);

  Task copyWith({
    String? summary,
    String? description,
    List<String>? categories,
    String? status,
    bool clearStatus = false,
    int? percentComplete,
    bool clearPercent = false,
    int? priority,
    bool clearPriority = false,
    ICalDate? due,
    bool clearDue = false,
    ICalDate? dtstart,
    bool clearStart = false,
    DateTime? completed,
    bool clearCompleted = false,
    String? rrule,
    bool clearRrule = false,
    String? parentUid,
    bool clearParent = false,
    DateTime? lastModified,
  }) => Task(
    uid: uid,
    summary: summary ?? this.summary,
    description: description ?? this.description,
    categories: categories ?? List.of(this.categories),
    status: clearStatus ? null : (status ?? this.status),
    percentComplete: clearPercent
        ? null
        : (percentComplete ?? this.percentComplete),
    priority: clearPriority ? null : (priority ?? this.priority),
    due: clearDue ? null : (due ?? this.due),
    dtstart: clearStart ? null : (dtstart ?? this.dtstart),
    completed: clearCompleted ? null : (completed ?? this.completed),
    rrule: clearRrule ? null : (rrule ?? this.rrule),
    parentUid: clearParent ? null : (parentUid ?? this.parentUid),
    created: created,
    lastModified: lastModified ?? this.lastModified,
    dtstamp: dtstamp,
    extraLines: List.of(extraLines),
    calendarLines: List.of(calendarLines),
    siblingLines: List.of(siblingLines),
    propertyParams: Map.of(propertyParams),
    href: href,
    etag: etag,
  );

  @override
  String toString() => 'Task($uid, "$summary")';
}
