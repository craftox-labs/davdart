import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';

/// An open in-place edit of one task, like [NoteDraft]: text fields, parent,
/// due date and priority, and whether anything differs from what was loaded.
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
    super.dispose();
  }
}
