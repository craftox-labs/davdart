import 'dart:async';

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../state/note_draft.dart' show setText;
import '../../theme/tokens.dart';
import '../note_editor.dart' show imeComposing;
import '../theme.dart';

/// A text value edited in place: the value itself until a press lands on it,
/// then the field, in the same place and style, so nothing shifts.
///
/// The field is mounted throughout ([EditableText], read-only while it has no
/// focus) so a press lands on a text field and takes the focus the way any
/// other field does. Typing pauses for [debounce] and commits through
/// [onCommit]; so does a blur, Enter (a single line) and leaving the field.
/// Esc reverts the field to the last saved text. A commit that fails keeps
/// what was typed and colours it with [Tokens.error] until the next edit (a
/// field left as it was goes back to the saved text); the caller shows the
/// toast. Text typed while a write runs is written once that write is done.
class InlineText extends StatefulWidget {
  const InlineText({
    super.key,
    required this.controller,
    required this.onCommit,
    this.multiline = false,
    this.debounce,
    this.placeholder,
    this.style,
    this.readOnly = false,
    this.maxLines,
    this.preview,
    this.focusNode,
    this.autoBegin = false,
    this.onBegan,
    this.commitSignal,
  });

  final TextEditingController controller;

  /// Saves [text]; false when it did not go through (the text is reverted).
  final Future<bool> Function(String text) onCommit;

  /// A description rather than a one-line title: Enter adds a line and the
  /// field grows to [maxLines].
  final bool multiline;

  /// How long typing must pause before it commits.
  final Duration? debounce;
  final String? placeholder;

  /// The text style of both the value and the field.
  final TextStyle? style;
  final bool readOnly;
  final int? maxLines;

  /// Draws the value while the field has no focus (a markdown preview).
  final Widget Function(String text)? preview;

  /// The node the caller focuses to start editing (a tap on the row); the
  /// widget makes its own when null.
  final FocusNode? focusNode;

  /// Opens the field and takes the focus as soon as it is in the tree (the
  /// page was just asked to edit this value).
  final bool autoBegin;

  /// Called once [autoBegin] has been used, so the page does not open it
  /// again.
  final VoidCallback? onBegan;

  /// Pinged when the value is saved around this field (the page's Ctrl+S):
  /// the field writes what it shows, so it records what it saved instead of
  /// going stale.
  final Listenable? commitSignal;

  @override
  State<InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<InlineText> {
  FocusNode? _ownFocus;
  Timer? _timer;

  /// The text the item holds now: what Esc puts back.
  late String _saved;

  /// The text the field last showed, to tell an edit from a change made
  /// around it (a sync rebase puts the merged text into the controller).
  late String _seen;

  /// A write is in flight; Esc waits for it instead of reverting under it.
  var _writing = false;
  var _failed = false;

  /// Text typed while a write ran: it commits once that write is done.
  var _queued = false;

  FocusNode get _focus => widget.focusNode ?? _ownFocus!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownFocus = FocusNode(debugLabel: 'inline-text');
    }
    _saved = _seen = widget.controller.text;
    _focus.addListener(_focusChanged);
    widget.controller.addListener(_changed);
    widget.commitSignal?.addListener(_pinged);
    if (widget.autoBegin) _autoBegin();
  }

  /// Takes the focus once the field this build creates is in the tree.
  void _autoBegin() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onBegan?.call();
      _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(InlineText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _saved = _seen = widget.controller.text;
    }
    if (old.commitSignal != widget.commitSignal) {
      old.commitSignal?.removeListener(_pinged);
      widget.commitSignal?.addListener(_pinged);
    }
    if (widget.autoBegin && !old.autoBegin) _autoBegin();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    widget.commitSignal?.removeListener(_pinged);
    _focus.removeListener(_focusChanged);
    _ownFocus?.dispose();
    super.dispose();
  }

  /// The value was saved around this field (Ctrl+S): write what it shows, so
  /// [_saved] is what the item holds.
  void _pinged() => unawaited(_commit());

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_focus.hasFocus) {
      _timer?.cancel();
      unawaited(_commit());
    }
  }

  /// A change from the field itself (typing, pasting): the pause commits it.
  void _edited(String text) {
    _seen = text;
    _timer?.cancel();
    _timer = Timer(
      widget.debounce ?? tokensOf(context).property.debounce,
      () => unawaited(_commit()),
    );
  }

  /// A change made around the field (a sync rebase, or a text this widget put
  /// back): it is what the item holds, so Esc reverts to it, not to the text
  /// from before.
  void _changed() {
    final text = widget.controller.text;
    if (text == _seen) return;
    if (!_focus.hasFocus) {
      // The field cannot have typed this while it had no focus.
      _seen = text;
      _saved = text;
      _timer?.cancel();
      return;
    }
    // With the focus here this may be the field's own edit, which reports
    // itself right after this change: decide once both have run.
    scheduleMicrotask(() {
      if (!mounted) return;
      final now = widget.controller.text;
      if (_seen == now) return;
      _seen = now;
      _saved = now;
      _timer?.cancel();
    });
  }

  Future<bool> _commit() async {
    _timer?.cancel();
    final text = widget.controller.text;
    if (text == _saved) {
      if (_failed) setState(() => _failed = false);
      return true;
    }
    // One write at a time: the text showing when it is done commits next.
    if (_writing) {
      _queued = true;
      return false;
    }
    _writing = true;
    final bool ok;
    try {
      ok = await widget.onCommit(text);
    } finally {
      _writing = false;
    }
    if (!mounted) return ok;
    if (ok) {
      // What was written, even if more was typed while it ran: that text is
      // still pending and Esc reverts to this one.
      _saved = text;
      if (_failed) setState(() => _failed = false);
      // Text typed during the write goes next, as the latest text.
      if (_queued) {
        _queued = false;
        unawaited(_commit());
      }
      return true;
    }
    _queued = false;
    _timer?.cancel();
    // Keep what the user typed (the reason is the caller's toast): only a
    // field left as the write found it goes back to what the item holds.
    if (widget.controller.text == text) setText(widget.controller, _saved);
    setState(() => _failed = true);
    return false;
  }

  /// Esc: the text goes back to the last saved one, the field closes. The
  /// unfocus waits for the key event to finish, so the keys above the field
  /// see the field still holding the focus (Esc does not then leave the page).
  void _revert() {
    // A write in flight decides what the text is; Esc leaves it alone.
    if (_writing) return;
    _timer?.cancel();
    if (widget.controller.text != _saved) {
      setText(widget.controller, _saved);
      _timer?.cancel();
    }
    // After the key event has been dispatched to the field, so the keys above
    // it still see the field holding the focus (Esc does not leave the page).
    scheduleMicrotask(() {
      if (mounted) _focus.unfocus();
    });
    if (_failed) setState(() => _failed = false);
  }

  KeyEventResult _keys(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      // Ctrl/Cmd+Enter belongs to the page (flush and leave).
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      if (imeComposing()) return KeyEventResult.ignored;
      _revert();
      return KeyEventResult.handled;
    }
    if (!widget.multiline &&
        (e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      unawaited(_commit());
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    // The value is a Text, so it takes the inherited style; the field must
    // show the same (an EditableText does not inherit it by itself).
    final style = DefaultTextStyle.of(context).style
        .merge(widget.style ?? t.type.bodyStyle);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final text = widget.controller.text;
        if (widget.readOnly) return _value(t, style, text);
        final focused = _focus.hasFocus;
        // The field is always in the tree (invisibly while it has no focus):
        // it owns the focus node, so a press on the value lands on a text
        // field and the shell's key catcher leaves the focus where it is. The
        // value is painted over it, and takes no press of its own, so a press
        // anywhere on it opens the field.
        return Stack(
          alignment: widget.multiline
              ? AlignmentDirectional.topStart
              : AlignmentDirectional.centerStart,
          children: [
            Opacity(opacity: focused ? 1 : 0, child: _field(t, style, focused)),
            if (!focused) IgnorePointer(child: _value(t, style, text)),
            if (focused)
              const Positioned.fill(
                key: Key('inline-text-editing'),
                child: IgnorePointer(child: SizedBox.expand()),
              ),
          ],
        );
      },
    );
  }

  /// The value while the field has no focus.
  Widget _value(Tokens t, TextStyle style, String text) {
    if (text.isEmpty && widget.placeholder != null) {
      return Text(
        widget.placeholder!,
        maxLines: widget.multiline ? null : 1,
        overflow: widget.multiline ? null : TextOverflow.ellipsis,
        style: style.copyWith(color: t.muted),
      );
    }
    final shown =
        widget.preview?.call(text) ??
        Text(
          text,
          maxLines: widget.multiline ? widget.maxLines : 1,
          overflow: widget.multiline ? null : TextOverflow.ellipsis,
          style: style.copyWith(color: _failed ? t.error : null),
        );
    return widget.multiline
        ? shown
        : Align(alignment: .centerLeft, child: shown);
  }

  Widget _field(Tokens t, TextStyle style, bool focused) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _keys,
    child: SizedBox(
      width: widget.multiline ? double.infinity : null,
      child: EditableText(
        key: const Key('inline-text-field'),
        controller: widget.controller,
        focusNode: _focus,
        readOnly: !focused,
        style: style.copyWith(color: _failed ? t.error : t.fg),
        cursorColor: t.accent,
        backgroundCursorColor: t.muted,
        selectionColor: t.selectionFill,
        maxLines: widget.multiline ? widget.maxLines : 1,
        keyboardType: widget.multiline
            ? TextInputType.multiline
            : TextInputType.text,
        textInputAction: widget.multiline
            ? TextInputAction.newline
            : TextInputAction.done,
        onChanged: _edited,
        onSubmitted: widget.multiline
            ? null
            : (_) {
                unawaited(_commit());
                _focus.unfocus();
              },
      ),
    ),
  );
}
