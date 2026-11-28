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

/// A nudge to the inline fields of a text buffer: the page pings it to have
/// them write what they show (Ctrl+S saves through the fields, so each one
/// records the text it saved instead of going stale).
class CommitSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The open text buffer of one note: its title and its body, and whether
/// either differs from what was loaded.
///
/// Like a task's buffer it holds no selector: the page shows the title as an
/// [InlineText] and every property (status, priority, labels, belongs to) is
/// picked in place and written at once through [AppState], never through this
/// buffer. The body keeps the note's explicit edit mode (the Vim field), and a
/// save writes only the text that changed, so it can never put a stale selector
/// back.
class NoteDraft extends ChangeNotifier {
  NoteDraft({required this.uid, required String title, required String body})
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

  /// The title's inline field: [AppState] focuses it when a tap on the title
  /// starts the edit.
  final FocusNode titleFocus = FocusNode(debugLabel: 'note-title');

  /// The fields' Ctrl+S: the page pings it to save through them.
  final commitSignal = CommitSignal();

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

  /// Takes new saved [title] and [body] (merged from the server) as both the
  /// text and the originals. Only for a draft with nothing typed.
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

  /// The body changed and was not saved yet.
  bool get bodyDirty => bodyController.text != originalBody;

  bool get dirty => titleDirty || bodyDirty;

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    titleFocus.dispose();
    commitSignal.dispose();
    super.dispose();
  }
}
