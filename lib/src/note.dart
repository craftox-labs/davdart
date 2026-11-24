import 'rank.dart';

/// A note or task-like journal entry, stored as an iCalendar VJOURNAL.
class Note {
  Note({
    required this.uid,
    this.summary = '',
    this.description = '',
    List<String>? categories,
    this.status,
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
  })  : categories = categories ?? <String>[],
        created = created?.toUtc(),
        lastModified = lastModified?.toUtc(),
        dtstamp = (dtstamp ?? DateTime.now()).toUtc(),
        extraLines = extraLines ?? <String>[],
        calendarLines = calendarLines ?? <String>[],
        siblingLines = siblingLines ?? <String>[],
        propertyParams = propertyParams ?? <String, String>{};

  /// Stable identifier (iCalendar UID).
  final String uid;
  String summary;
  String description;
  List<String> categories;

  /// DRAFT, FINAL or CANCELLED per RFC 5545, or null.
  String? status;

  /// UID of the parent note (iCalendar `RELATED-TO;RELTYPE=PARENT`), or null
  /// for a top-level note.
  String? parentUid;
  DateTime? created;
  DateTime? lastModified;
  DateTime dtstamp;

  /// Unfolded raw property lines this core does not model (for example ATTACH),
  /// kept so a round trip does not lose data written by other clients.
  final List<String> extraLines;

  /// Raw VCALENDAR-level lines (VTIMEZONE, X-WR-*, ...) of the resource this
  /// note was read from, written back unchanged before the VJOURNAL.
  final List<String> calendarLines;

  /// Raw lines of other VJOURNALs in the same resource (recurrence overrides),
  /// written back unchanged after this note.
  final List<String> siblingLines;

  /// Raw parameter text (for example `;LANGUAGE=de`) of SUMMARY/DESCRIPTION.
  final Map<String, String> propertyParams;

  /// Server-side location and entity tag, set by the CalDAV client.
  String? href;
  String? etag;

  /// Manual order in a board column (`X-DAVDART-RANK`): lower first, null
  /// for none. Kept in [extraLines].
  double? get rank => rankOfLines(extraLines);
  set rank(double? v) => setRankInLines(extraLines, v);

  Note copyWith({
    String? summary,
    String? description,
    List<String>? categories,
    String? status,
    bool clearStatus = false,
    String? parentUid,
    bool clearParent = false,
    DateTime? lastModified,
  }) =>
      Note(
        uid: uid,
        summary: summary ?? this.summary,
        description: description ?? this.description,
        categories: categories ?? List.of(this.categories),
        status: clearStatus ? null : (status ?? this.status),
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
  String toString() => 'Note($uid, "$summary")';
}
