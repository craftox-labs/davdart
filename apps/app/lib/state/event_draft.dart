import 'package:flutter/widgets.dart';

import 'note_draft.dart' show setText;

/// The open text buffer of one event: the title, the location and the
/// description, and whether any of them differs from what was loaded.
///
/// Like [TaskDraft] it holds no selector: when, repeat, status and labels are
/// picked in place and written at once through [AppState], so a save writes
/// only the text that changed. Editing a recurring event edits the series.
class EventDraft extends ChangeNotifier {
  EventDraft({
    required this.uid,
    required String title,
    required String location,
    required String body,
  }) : originalTitle = title,
       originalLocation = location,
       originalBody = body,
       titleController = TextEditingController(text: title),
       locationController = TextEditingController(text: location),
       bodyController = TextEditingController(text: body) {
    titleController.addListener(notifyListeners);
    locationController.addListener(notifyListeners);
    bodyController.addListener(notifyListeners);
  }

  final String uid;
  String originalTitle, originalLocation, originalBody;
  final TextEditingController titleController,
      locationController,
      bodyController;

  /// The inline fields of the title, the location and the description:
  /// [AppState] focuses one when a tap on the value (or `e`) starts an edit.
  final FocusNode titleFocus = FocusNode(debugLabel: 'event-title');
  final FocusNode locationFocus = FocusNode(debugLabel: 'event-location');
  final FocusNode bodyFocus = FocusNode(debugLabel: 'event-body');

  /// Takes the fields that were saved as their new originals; a null field was
  /// not written and keeps its own.
  void markSaved({String? title, String? location, String? body}) {
    originalTitle = title ?? originalTitle;
    originalLocation = location ?? originalLocation;
    originalBody = body ?? originalBody;
    notifyListeners();
  }

  bool _quiet = false;

  @override
  void notifyListeners() {
    if (!_quiet) super.notifyListeners();
  }

  /// Takes the saved text as both the fields and the originals. Only for a
  /// buffer with nothing typed.
  void rebase({
    required String title,
    required String location,
    required String body,
  }) {
    // One change for the listeners: no half-way "dirty" in between.
    _quiet = true;
    markSaved(title: title, location: location, body: body);
    setText(titleController, title);
    setText(locationController, location);
    setText(bodyController, body);
    _quiet = false;
    notifyListeners();
  }

  bool get titleEmpty => titleController.text.trim().isEmpty;

  bool get titleDirty => titleController.text != originalTitle;

  bool get locationDirty => locationController.text != originalLocation;

  bool get bodyDirty => bodyController.text != originalBody;

  bool get dirty => titleDirty || locationDirty || bodyDirty;

  @override
  void dispose() {
    titleController.dispose();
    locationController.dispose();
    bodyController.dispose();
    titleFocus.dispose();
    locationFocus.dispose();
    bodyFocus.dispose();
    super.dispose();
  }
}
