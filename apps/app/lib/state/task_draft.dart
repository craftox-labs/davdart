import 'package:flutter/widgets.dart';

import 'note_draft.dart' show setText;

/// The open text buffer of one task: the title and the description, and
/// whether either differs from what was loaded.
///
/// It is invisible and holds no selector: the page shows the title and the
/// description as an [InlineText], and every selector (due, priority, parent,
/// labels, status) is picked in place and written at once through [AppState],
/// never through this buffer. A save therefore writes only the text that
/// changed, so it can never put a stale selector back.
class TaskDraft extends ChangeNotifier {
  TaskDraft({required this.uid, required String title, required String body})
    : originalTitle = title,
      originalBody = body,
      titleController = TextEditingController(text: title),
      bodyController = TextEditingController(text: body) {
    titleController.addListener(notifyListeners);
    bodyController.addListener(notifyListeners);
  }

  final String uid;
  String originalTitle, originalBody;
  final TextEditingController titleController, bodyController;

  /// The inline fields of the title and the description: [AppState] focuses
  /// one when a tap on the value (or `e`) starts an edit.
  final FocusNode titleFocus = FocusNode(debugLabel: 'task-title');
  final FocusNode bodyFocus = FocusNode(debugLabel: 'task-body');

  /// Takes the fields that were saved as their new originals; a null field was
  /// not written and keeps its own.
  void markSaved({String? title, String? body}) {
    originalTitle = title ?? originalTitle;
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
  void rebase({required String title, required String body}) {
    // One change for the listeners: no half-way "dirty" in between.
    _quiet = true;
    markSaved(title: title, body: body);
    setText(titleController, title);
    setText(bodyController, body);
    _quiet = false;
    notifyListeners();
  }

  bool get titleEmpty => titleController.text.trim().isEmpty;

  /// The title changed and was not saved yet.
  bool get titleDirty => titleController.text != originalTitle;

  /// The description changed and was not saved yet.
  bool get bodyDirty => bodyController.text != originalBody;

  bool get dirty => titleDirty || bodyDirty;

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    titleFocus.dispose();
    bodyFocus.dispose();
    super.dispose();
  }
}
