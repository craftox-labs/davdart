import 'package:flutter/widgets.dart';

import 'note_draft.dart' show setText;

/// An open in-place edit of one event, like [TaskDraft]: text fields, the
/// all-day switch, start and end (wall-clock fields; for an all-day event the
/// end is the last day, inclusive) and the status, and whether anything
/// differs from what was loaded. Editing a recurring event edits the series.
class EventDraft extends ChangeNotifier {
  EventDraft({
    required this.uid,
    required String title,
    required String body,
    required String tags,
    required String location,
    required bool allDay,
    required DateTime start,
    required DateTime end,
    required String? status,
  }) : originalTitle = title,
       originalBody = body,
       originalTags = tags,
       originalLocation = location,
       originalAllDay = allDay,
       originalStart = start,
       originalEnd = end,
       originalStatus = status,
       allDay = allDay,
       start = start,
       end = end,
       status = status,
       titleController = TextEditingController(text: title),
       bodyController = TextEditingController(text: body),
       tagsController = TextEditingController(text: tags),
       locationController = TextEditingController(text: location) {
    titleController.addListener(notifyListeners);
    bodyController.addListener(notifyListeners);
    tagsController.addListener(notifyListeners);
    locationController.addListener(notifyListeners);
  }

  final String uid;
  String originalTitle, originalBody, originalTags, originalLocation;
  bool originalAllDay;
  DateTime originalStart, originalEnd;
  String? originalStatus;
  final TextEditingController titleController,
      bodyController,
      tagsController,
      locationController;

  bool allDay;
  DateTime start, end;
  String? status;

  DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Switching to all day keeps the dates; switching back gives 09:00-10:00
  /// on the first day (the last day at 10:00 when it spans days).
  void setAllDay(bool v) {
    if (v == allDay) return;
    allDay = v;
    if (v) {
      start = _day(start);
      end = _day(end);
      if (end.isBefore(start)) end = start;
    } else {
      final s = _day(start);
      start = s.add(const Duration(hours: 9));
      end = _day(end).add(const Duration(hours: 10));
      if (end.isBefore(start)) end = start.add(const Duration(hours: 1));
    }
    notifyListeners();
  }

  /// Moves the start to [d] (date) and optionally [minutes] into the day,
  /// shifting the end by the same amount so the length stays.
  void moveStart({DateTime? date, int? minutes}) {
    final len = end.difference(start);
    final day = date == null ? _day(start) : _day(date);
    final mins = allDay ? 0 : minutes ?? start.hour * 60 + start.minute;
    start = day.add(Duration(minutes: mins));
    end = start.add(len);
    notifyListeners();
  }

  void setEnd({DateTime? date, int? minutes}) {
    final day = date == null ? _day(end) : _day(date);
    final mins = allDay ? 0 : minutes ?? end.hour * 60 + end.minute;
    end = day.add(Duration(minutes: mins));
    notifyListeners();
  }

  void setStatus(String? v) {
    status = v;
    notifyListeners();
  }

  void markSaved({
    required String title,
    required String body,
    required String tags,
    required String location,
    required bool allDay,
    required DateTime start,
    required DateTime end,
    required String? status,
  }) {
    originalTitle = title;
    originalBody = body;
    originalTags = tags;
    originalLocation = location;
    originalAllDay = allDay;
    originalStart = start;
    originalEnd = end;
    originalStatus = status;
    notifyListeners();
  }

  bool _quiet = false;

  @override
  void notifyListeners() {
    if (!_quiet) super.notifyListeners();
  }

  /// Takes the merged saved values as both the fields and the originals.
  /// Only for a draft with nothing typed or changed.
  void rebase({
    required String title,
    required String body,
    required String tags,
    required String location,
    required bool allDay,
    required DateTime start,
    required DateTime end,
    required String? status,
  }) {
    // One change for the listeners: no half-way "dirty" in between.
    _quiet = true;
    this.allDay = allDay;
    this.start = start;
    this.end = end;
    this.status = status;
    markSaved(
      title: title,
      body: body,
      tags: tags,
      location: location,
      allDay: allDay,
      start: start,
      end: end,
      status: status,
    );
    setText(titleController, title);
    setText(bodyController, body);
    setText(tagsController, tags);
    setText(locationController, location);
    _quiet = false;
    notifyListeners();
  }

  bool get titleEmpty => titleController.text.trim().isEmpty;
  bool get endBeforeStart => end.isBefore(start);

  /// Start, end or all-day changed (the saved event keeps its own end form
  /// otherwise).
  bool get whenChanged =>
      allDay != originalAllDay || start != originalStart || end != originalEnd;

  bool get dirty =>
      titleController.text != originalTitle ||
      bodyController.text != originalBody ||
      tagsController.text != originalTags ||
      locationController.text != originalLocation ||
      status != originalStatus ||
      whenChanged;

  List<String> get tagList => [
    for (final t in tagsController.text.split(','))
      if (t.trim().isNotEmpty) t.trim(),
  ];

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    tagsController.dispose();
    locationController.dispose();
    super.dispose();
  }
}
