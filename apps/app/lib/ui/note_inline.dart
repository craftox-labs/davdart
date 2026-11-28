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
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = _current;
    _controller.text = _value;
  }

  String get _current =>
      noteInlineValue(widget.state, widget.uid, field: widget.field);

  @override
  void didUpdateWidget(NoteInlineText old) {
    super.didUpdateWidget(old);
    final now = _current;
    if (now == _value) return;
    _value = now;
    // The note changed elsewhere: show the new value, unless the field holds
    // something else (someone typing here).
    if (_controller.text != now) setText(_controller, now);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _commit(String text) {
    final field = widget.field;
    return field == null
        ? widget.state.setNoteText(widget.uid, text)
        : widget.state.setNoteField(widget.uid, field, text);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final style = widget.style ?? t.type.bodyStyle;
    final empty = widget.placeholder;
    return InlineText(
      controller: _controller,
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
