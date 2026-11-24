import 'package:flutter/widgets.dart';

/// Sets [c]'s text to [text] keeping the caret where it was (clamped).
void setText(TextEditingController c, String text) {
  if (c.text == text) return;
  final s = c.selection;
  c.value = TextEditingValue(
    text: text,
    selection: s.isValid
        ? TextSelection(
            baseOffset: s.baseOffset.clamp(0, text.length),
            extentOffset: s.extentOffset.clamp(0, text.length),
          )
        : TextSelection.collapsed(offset: text.length),
  );
}

/// What the user chose when asked about unsaved edits.
enum DraftChoice { save, discard, keep }

/// An open in-place edit of one note: the text fields and selectors, and
/// whether anything differs from what was loaded. Held by AppState so the
/// peek pane and the full page share one session.
class NoteDraft extends ChangeNotifier {
  NoteDraft({
    required this.uid,
    required String title,
    required String body,
    required String tags,
    required this.originalParent,
    required this.originalStatus,
    this.originalPriority,
  }) : originalTitle = title,
       originalBody = body,
       originalTags = tags,
       parent = originalParent,
       status = originalStatus,
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
  String? originalParent, originalStatus, originalPriority;
  final TextEditingController titleController, bodyController, tagsController;

  String? parent;
  String? status;

  /// `high`, `medium`, `low` or null (none).
  String? priority;

  void setParent(String? v) {
    parent = v;
    notifyListeners();
  }

  void setStatus(String? v) {
    status = v;
    notifyListeners();
  }

  void setPriority(String? v) {
    priority = v;
    notifyListeners();
  }

  /// Records that the given values were saved: the draft is dirty only for
  /// what was typed or changed after them.
  void markSaved({
    required String title,
    required String body,
    required String tags,
    required String? parent,
    required String? status,
    String? priority,
  }) {
    originalTitle = title;
    originalBody = body;
    originalTags = tags;
    originalParent = parent;
    originalStatus = status;
    originalPriority = priority;
    notifyListeners();
  }

  bool _quiet = false;

  @override
  void notifyListeners() {
    if (!_quiet) super.notifyListeners();
  }

  /// Takes new saved [title] and [body] (merged from the server) as both the
  /// text and the originals. Only for a draft with nothing typed.
  void rebase({required String title, required String body}) {
    // One change for the listeners: no half-way "dirty" in between.
    _quiet = true;
    originalTitle = title;
    originalBody = body;
    setText(titleController, title);
    setText(bodyController, body);
    _quiet = false;
    notifyListeners();
  }

  bool get titleEmpty => titleController.text.trim().isEmpty;

  bool get dirty =>
      titleController.text != originalTitle ||
      bodyController.text != originalBody ||
      tagsController.text != originalTags ||
      parent != originalParent ||
      status != originalStatus ||
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
