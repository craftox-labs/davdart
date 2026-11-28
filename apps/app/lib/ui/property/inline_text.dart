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
/// Esc reverts the field to the last saved text. A commit that fails reverts
/// the text too and colours it with [Tokens.error] until the next edit; the
/// caller shows the toast.
class InlineText extends StatefulWidget {
  const InlineText({
    super.key,
    required this.controller,
    required this.onCommit,
    this.multiline = false,
    this.debounce = const Duration(milliseconds: 800),
    this.placeholder,
    this.style,
    this.readOnly = false,
    this.maxLines,
    this.preview,
    this.focusNode,
    this.autoBegin = false,
    this.onBegan,
  });

  final TextEditingController controller;

  /// Saves [text]; false when it did not go through (the text is reverted).
  final Future<bool> Function(String text) onCommit;

  /// A description rather than a one-line title: Enter adds a line and the
  /// field grows to [maxLines].
  final bool multiline;

  /// How long typing must pause before it commits.
  final Duration debounce;
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

  @override
  State<InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<InlineText> {
  FocusNode? _ownFocus;
  Timer? _timer;

  /// The text the item holds now: what Esc puts back.
  late String _saved;
  var _failed = false;

  FocusNode get _focus => widget.focusNode ?? _ownFocus!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownFocus = FocusNode(debugLabel: 'inline-text');
    }
    _saved = widget.controller.text;
    _focus.addListener(_focusChanged);
    widget.controller.addListener(_typed);
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
      old.controller.removeListener(_typed);
      widget.controller.addListener(_typed);
      _saved = widget.controller.text;
    }
    if (widget.autoBegin && !old.autoBegin) _autoBegin();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_typed);
    _focus.removeListener(_focusChanged);
    _ownFocus?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_focus.hasFocus) {
      _timer?.cancel();
      unawaited(_commit());
    }
  }

  void _typed() {
    // A change from outside (a sync rebase) is not typing.
    if (!_focus.hasFocus) return;
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => unawaited(_commit()));
  }

  Future<bool> _commit() async {
    _timer?.cancel();
    final text = widget.controller.text;
    if (text == _saved) {
      if (_failed) setState(() => _failed = false);
      return true;
    }
    final ok = await widget.onCommit(text);
    if (!mounted) return ok;
    if (ok) {
      _saved = text;
      if (_failed) setState(() => _failed = false);
    } else {
      // Back to what the item holds; the reason is the caller's toast.
      setText(widget.controller, _saved);
      _timer?.cancel();
      setState(() => _failed = true);
    }
    return ok;
  }

  /// Esc: the text goes back to the last saved one, the field closes. The
  /// unfocus waits for the key event to finish, so the keys above the field
  /// see the field still holding the focus (Esc does not then leave the page).
  void _revert() {
    _timer?.cancel();
    if (widget.controller.text != _saved) {
      setText(widget.controller, _saved);
      _timer?.cancel();
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
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
    final style = widget.style ?? t.type.bodyStyle;
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
        style: style.copyWith(color: _failed ? t.error : null),
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
