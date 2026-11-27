import 'task.dart' show ICalDate;

/// An event, stored as an iCalendar VEVENT (RFC 5545 section 3.6.1).
///
/// Same shape as `Task`: what is not modelled (VALARM, TRANSP, ATTENDEE,
/// X-properties, extra RELATED-TO relations, ...) is kept as raw lines and
/// written back. Recurrence is kept raw ([rrule], [exdates], [rdates]);
/// `occurrencesBetween` expands it for display.
class Event {
  Event({
    required this.uid,
    this.summary = '',
    this.description = '',
    this.location = '',
    List<String>? categories,
    this.status,
    this.dtstart,
    this.dtend,
    this.duration,
    this.rrule,
    List<String>? exdates,
    List<String>? rdates,
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
       exdates = exdates ?? <String>[],
       rdates = rdates ?? <String>[],
       created = created?.toUtc(),
       lastModified = lastModified?.toUtc(),
       dtstamp = (dtstamp ?? DateTime.now()).toUtc(),
       extraLines = extraLines ?? <String>[],
       calendarLines = calendarLines ?? <String>[],
       siblingLines = siblingLines ?? <String>[],
       propertyParams = propertyParams ?? <String, String>{};

  final String uid;
  String summary;
  String description;
  String location;
  List<String> categories;

  /// TENTATIVE, CONFIRMED or CANCELLED (raw), or null.
  String? status;
  ICalDate? dtstart;

  /// Exclusive end (for an all-day event, the day after the last day).
  ICalDate? dtend;

  /// Raw DURATION value (`PT1H`, `P2D`), used when there is no [dtend].
  String? duration;

  /// The raw RRULE value, or null.
  String? rrule;

  /// Raw EXDATE and RDATE property lines (name, parameters and value), kept
  /// verbatim.
  List<String> exdates;
  List<String> rdates;

  /// UID of the parent item (`RELATED-TO;RELTYPE=PARENT`), or null.
  String? parentUid;
  DateTime? created;
  DateTime? lastModified;
  DateTime dtstamp;

  /// Raw property lines (and nested components such as VALARM) not modelled.
  final List<String> extraLines;

  /// Raw VCALENDAR-level lines (VTIMEZONE, X-WR-*, ...), written back first.
  final List<String> calendarLines;

  /// Raw lines of other VEVENTs of the same resource (recurrence overrides
  /// with RECURRENCE-ID).
  final List<String> siblingLines;

  /// Raw parameter text of SUMMARY, DESCRIPTION and LOCATION.
  final Map<String, String> propertyParams;

  /// Server-side location and entity tag, set by the CalDAV client.
  String? href;
  String? etag;

  bool get allDay => dtstart?.allDay ?? false;
  bool get isCancelled => status == 'CANCELLED';
  bool get isRecurring =>
      (rrule != null && rrule!.isNotEmpty) || rdates.isNotEmpty;

  /// Start as wall-clock fields in the local zone (UTC-flagged [DateTime];
  /// a `...Z` or TZID value is converted to local time through the time zone
  /// database, floating values stay as written, see [ICalDate.localWall]), or
  /// null.
  DateTime? get startWall => dtstart?.localWall;

  /// Length of one occurrence: [dtend] minus [dtstart] (as written), else
  /// [duration], else one day for an all-day event and zero otherwise.
  Duration get length {
    final ds = dtstart, de = dtend;
    final s = ds?.wall, e = de?.wall;
    if (s != null && e != null && ds != null && de != null) {
      // Same flavour: the written clock difference. Mixed flavours (Z with a
      // TZID, a zone with floating, ...): the difference of the real instants.
      final same =
          ds.allDay == de.allDay && ds.isUtc == de.isUtc && ds.tzid == de.tzid;
      final i = ds.toInstant(), j = de.toInstant();
      final len = same || i == null || j == null
          ? e.difference(s)
          : j.difference(i);
      if (!len.isNegative) return len;
    }
    final d = duration == null ? null : parseIcalDuration(duration!);
    if (d != null) return d;
    return allDay ? const Duration(days: 1) : Duration.zero;
  }

  /// End as local wall-clock fields: the DTEND's own wall fields when written,
  /// else [startWall] plus [length]; null without start. Adding [length] to
  /// the start would cross a DST change wrongly (two real hours can be three
  /// or one wall hours), so a written DTEND is what the viewer sees.
  DateTime? get endWall {
    final s = startWall;
    if (s == null) return null;
    return dtend?.localWall ?? s.add(length);
  }

  Event copyWith({
    String? summary,
    String? description,
    String? location,
    List<String>? categories,
    String? status,
    bool clearStatus = false,
    ICalDate? dtstart,
    bool clearStart = false,
    ICalDate? dtend,
    bool clearEnd = false,
    String? duration,
    bool clearDuration = false,
    String? rrule,
    bool clearRrule = false,
    List<String>? exdates,
    List<String>? rdates,
    List<String>? siblingLines,
    String? parentUid,
    bool clearParent = false,
    DateTime? lastModified,
  }) => Event(
    uid: uid,
    summary: summary ?? this.summary,
    description: description ?? this.description,
    location: location ?? this.location,
    categories: categories ?? List.of(this.categories),
    status: clearStatus ? null : (status ?? this.status),
    dtstart: clearStart ? null : (dtstart ?? this.dtstart),
    dtend: clearEnd ? null : (dtend ?? this.dtend),
    duration: clearDuration ? null : (duration ?? this.duration),
    rrule: clearRrule ? null : (rrule ?? this.rrule),
    exdates: exdates ?? List.of(this.exdates),
    rdates: rdates ?? List.of(this.rdates),
    parentUid: clearParent ? null : (parentUid ?? this.parentUid),
    created: created,
    lastModified: lastModified ?? this.lastModified,
    dtstamp: dtstamp,
    extraLines: List.of(extraLines),
    calendarLines: List.of(calendarLines),
    siblingLines: siblingLines ?? List.of(this.siblingLines),
    propertyParams: Map.of(propertyParams),
    href: href,
    etag: etag,
  );

  @override
  String toString() => 'Event($uid, "$summary")';
}

/// Parses an iCalendar DURATION (`P1W`, `P1DT2H30M`, `-PT15M`); null if it
/// does not parse.
Duration? parseIcalDuration(String v) {
  final m = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(v.trim().toUpperCase());
  if (m == null || v.trim().length < 3) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  final d = Duration(
    days: g(2) * 7 + g(3),
    hours: g(4),
    minutes: g(5),
    seconds: g(6),
  );
  return m.group(1) == '-' ? -d : d;
}
