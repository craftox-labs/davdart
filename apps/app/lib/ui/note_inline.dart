import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import '../state/note_draft.dart' show setText;
import 'property/inline_text.dart';
import 'theme.dart';

/// The value of note [uid]'s inline text: its body text, or the header field
/// [field] (null: the body).
String noteInlineValue(AppState state, String uid, {String? field}) {
  final n = state.tree.find(uid)?.note;
  if (n == null) return '';
  final p = PlanItem.fromNote(n);
  return field == null ? p.text : p.fields[field] ?? '';
}

/// One inline text of a note, with the controller [InlineText] needs: its body
/// text ([field] null, a markdown body) or one header field of it (a project
/// detail). The value follows the note when it changes elsewhere; a save
/// writes only this text or field, so the rest of the note stays as it is.
class NoteInlineText extends StatefulWidget {
  const NoteInlineText({
    super.key,
    required this.state,
    required this.uid,
    this.field,
    this.multiline = false,
    this.placeholder,
    this.style,
    this.preview,
    this.textKey,
  });
  final AppState state;
  final String uid;
  final String? field;
  final bool multiline;
  final String? placeholder;
  final TextStyle? style;
  final Widget Function(String text)? preview;

  /// Key of the plain value text (the field name for tests).
  final Key? textKey;

  @override
  State<NoteInlineText> createState() => _NoteInlineTextState();
}

class _NoteInlineTextState extends State<NoteInlineText> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'note-inline-text');

  /// The note's value this field last took.
  late String _value;

  /// The text this field last wrote to the note. The field holds an edit of
  /// its own while it shows anything else.
  late String _saved;

  /// A write of this field is in flight: the note it reloads is this field's
  /// own text on its way back, not a change made elsewhere.
  var _writing = false;

  @override
  void initState() {
    super.initState();
    _value = _saved = _current;
    _controller.text = _value;
  }

  String get _current =>
      noteInlineValue(widget.state, widget.uid, field: widget.field);

  @override
  void didUpdateWidget(NoteInlineText old) {
    super.didUpdateWidget(old);
    _followNote();
  }

  /// Takes the note's value when the note changed elsewhere, and leaves the
  /// field alone while it is the one being typed in: it has the focus, it
  /// holds text this field has not written yet, or its write is in flight
  /// (that write, not a reload, decides what the note holds).
  void _followNote() {
    final now = _current;
    if (now == _value) return;
    if (_focus.hasFocus || _writing) return;
    if (_controller.text != _saved) return;
    _value = _saved = now;
    setText(_controller, now);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<bool> _commit(String text) async {
    final field = widget.field;
    _writing = true;
    final bool ok;
    try {
      ok = await (field == null
          ? widget.state.setNoteText(widget.uid, text)
          : widget.state.setNoteField(widget.uid, field, text));
    } finally {
      _writing = false;
    }
    if (!ok) return false;
    // What the note holds, even if the field has moved on since: text typed
    // while the write ran is an edit of its own. A reload that landed during
    // the write was skipped, so it is taken now if it says something else.
    _value = _saved = text;
    if (mounted) _followNote();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final style = widget.style ?? t.type.bodyStyle;
    final empty = widget.placeholder;
    return InlineText(
      controller: _controller,
      focusNode: _focus,
      multiline: widget.multiline,
      style: style,
      onCommit: _commit,
      // An empty value still paints its [textKey] (the placeholder), so a row
      // keeps one key whether it has a value or not.
      preview:
          widget.preview ??
          (text) => Text(
            text.isEmpty ? (empty ?? '') : text,
            key: widget.textKey,
            maxLines: widget.multiline ? null : 1,
            overflow: widget.multiline ? null : TextOverflow.ellipsis,
            style: style.copyWith(
              color: text.isEmpty && empty != null ? t.muted : null,
            ),
          ),
    );
  }
}
