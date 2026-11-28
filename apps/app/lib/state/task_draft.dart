import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';

import 'note_draft.dart' show setText;

/// The open text buffer of one task: the title and the description, plus the
/// selector values a rebase keeps, and whether anything differs from what was
/// loaded. It is invisible: the page shows the title and the description as
/// [InlineText], and each selector is picked in place ([updateTask] and its
/// siblings), never through this buffer.
class TaskDraft extends ChangeNotifier {
  TaskDraft({
    required this.uid,
    required String title,
    required String body,
    required String tags,
    required this.originalParent,
    required this.originalDue,
    required this.originalPriority,
  }) : originalTitle = title,
       originalBody = body,
       originalTags = tags,
       parent = originalParent,
       due = originalDue,
       priority = originalPriority,
       titleController = TextEditingController(text: title),
       bodyController = TextEditingController(text: body),
       tagsController = TextEditingController(text: tags) {
    titleController.addListener(notifyListeners);
    bodyController.addListener(notifyListeners);
    tagsController.addListener(notifyListeners);
  }

  final String uid;
  String originalTitle, originalBody, originalTags;
  String? originalParent;
  ICalDate? originalDue;
  int? originalPriority;
  final TextEditingController titleController, bodyController, tagsController;

  /// The inline fields of the title and the description: [AppState] focuses
  /// one when a tap on the value (or `e`) starts an edit.
  final FocusNode titleFocus = FocusNode(debugLabel: 'task-title');
  final FocusNode bodyFocus = FocusNode(debugLabel: 'task-body');

  String? parent;
  ICalDate? due;
  int? priority;

  void setParent(String? v) {
    parent = v;
    notifyListeners();
  }

  void setDue(ICalDate? v) {
    due = v;
    notifyListeners();
  }

  void setPriority(int? v) {
    priority = v;
    notifyListeners();
  }

  void markSaved({
    required String title,
    required String body,
    required String tags,
    required String? parent,
    required ICalDate? due,
    required int? priority,
  }) {
    originalTitle = title;
    originalBody = body;
    originalTags = tags;
    originalParent = parent;
    originalDue = due;
    originalPriority = priority;
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
    required String? parent,
    required ICalDate? due,
    required int? priority,
  }) {
    // One change for the listeners: no half-way "dirty" in between.
    _quiet = true;
    this.parent = parent;
    this.due = due;
    this.priority = priority;
    markSaved(
      title: title,
      body: body,
      tags: tags,
      parent: parent,
      due: due,
      priority: priority,
    );
    setText(titleController, title);
    setText(bodyController, body);
    setText(tagsController, tags);
    _quiet = false;
    notifyListeners();
  }

  bool get titleEmpty => titleController.text.trim().isEmpty;

  bool get dirty =>
      titleController.text != originalTitle ||
      bodyController.text != originalBody ||
      tagsController.text != originalTags ||
      parent != originalParent ||
      due != originalDue ||
      priority != originalPriority;

  List<String> get tagList => [
    for (final t in tagsController.text.split(','))
      if (t.trim().isNotEmpty) t.trim(),
  ];

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    tagsController.dispose();
    titleFocus.dispose();
    bodyFocus.dispose();
    super.dispose();
  }
}
