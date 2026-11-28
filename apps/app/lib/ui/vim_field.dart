import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../state/app_action.dart';
import '../state/app_state.dart';
import '../state/key_bindings.dart';
import '../state/vim_editor/vim_engine.dart';
import 'app_actions.dart';
import 'command_palette.dart';
import 'key_nav_ui.dart';
import 'note_editor.dart' show imeComposing;
import 'parts.dart';
import 'theme.dart';

/// The long-text field of an editor (note body, task or event description)
/// with modal Vim editing (see [VimEngine]).
///
/// Entering edit mode starts in NORMAL. A mouse click into the field enters
/// INSERT at the click position (a drag keeps its selection). The caret in
/// NORMAL is a one-character selection (the engine's [VimEngine.value]), the
/// field is read-only outside INSERT so no stray character can be typed, and
/// keys are taken only in NORMAL, VISUAL and the Ex/search line; INSERT passes
/// every key to the text input except Esc, undo/redo and the chords. A
/// composing IME is never intercepted. With the setting off (or on a touch
/// platform) this is the plain field, exactly as before.
class VimField extends StatefulWidget {
  const VimField({
    super.key,
    required this.state,
    required this.uid,
    required this.controller,
    required this.fieldKey,
    required this.label,
    this.minLines,
  });
  final AppState state;

  /// The item in edit mode (for `:w`, `:q`, `:wq`).
  final String uid;
  final TextEditingController controller;

  /// The key of the text field itself (`edit-body`).
  final Key fieldKey;
  final String label;
  final int? minLines;

  @override
  State<VimField> createState() => _VimFieldState();
}

class _VimFieldState extends State<VimField> {
  late VimEngine engine = _newEngine();

  VimEngine _newEngine() => VimEngine(
    text: widget.controller.text,
    leader: _leader,
    onAction: _action,
  );
  bool _pushing = false;

  bool get _active => widget.state.vimEditor && !isTouchPlatform;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_ctl);
  }

  @override
  void didUpdateWidget(VimField old) {
    super.didUpdateWidget(old);
    // The callers key this widget by item uid, so another item builds a new
    // State (fresh engine; the register is not carried across items). Only a
    // swapped controller reaches here.
    if (old.controller != widget.controller) {
      old.controller.removeListener(_ctl);
      widget.controller.addListener(_ctl);
      engine.dispose();
      engine = _newEngine();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_ctl);
    engine.dispose();
    super.dispose();
  }

  void _ctl() {
    if (_pushing) return;
    engine.external(widget.controller.value);
  }

  /// Shows the engine's text and selection in the field.
  void _push() {
    final v = engine.value;
    final c = widget.controller;
    if (c.text == v.text && c.selection == v.selection) return;
    _pushing = true;
    c.value = v;
    _pushing = false;
  }

  void _action(VimAction a) {
    final s = widget.state;
    final u = widget.uid;
    switch (a) {
      case VimAction.write:
        unawaited(_saved(s.saveEdit(u)));
      case VimAction.quit:
        unawaited(s.leaveEdit(u));
      case VimAction.forceQuit:
        s.discardEdit(u);
      case VimAction.writeQuit:
        // saveAndLeave keeps edit mode when the save fails.
        unawaited(_saved(s.saveAndLeave(u)));
    }
  }

  /// Shows why a `:w` / `:wq` did not save.
  Future<void> _saved(Future<bool> result) async {
    final ok = await result;
    if (ok || !mounted) return;
    final s = widget.state;
    final note = s.draftFor(widget.uid);
    engine.fail(
      note?.titleEmpty == true ? 'E: title is required' : 'E: save failed',
    );
  }

  /// `<Space>` then keys: the bare-key app layer (`g t`), `<Space>` or `:`
  /// the palette.
  LeaderStep _leader(List<String> keys) {
    final s = widget.state;
    final AppAction? a;
    if (keys.length == 1 && (keys[0] == ' ' || keys[0] == ':')) {
      a = buildActions(s).where((x) => x.id == 'palette.open').firstOrNull;
    } else {
      final step = KeyBindings(
        buildActions(s),
        vim: true,
      ).resolve(keys.sublist(0, keys.length - 1), keys.last);
      if (step.keys != null) return const LeaderStep.wait();
      a = step.action;
    }
    if (a == null) return const LeaderStep.none();
    final action = a;
    return LeaderStep.run(() {
      if (!action.enabled(s)) return;
      s.nav.markShown();
      if (navigatingAction(action.id)) s.nav.node.requestFocus();
      Future.sync(
        () => action.run(
          ActionContext(
            s,
            context,
            openPalette: () => showCommandPalette(context, s),
          ),
        ),
      );
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (!_active || e is KeyUpEvent) return KeyEventResult.ignored;
    if (imeComposing()) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    // The stage 1 chords and Ctrl+Enter work in every mode: let them bubble.
    if (widget.state.chords.idFor(e, kb) != null) return KeyEventResult.ignored;
    final key = e.logicalKey;
    // AltGr (Ctrl+Alt on Windows and Linux) typing a character is that
    // character, not a modifier chord.
    final altGr = isAltGrChar(e, kb);
    final mod = !altGr && (kb.isControlPressed || kb.isMetaPressed);
    if (mod && !kb.isAltPressed) {
      if (key == LogicalKeyboardKey.keyZ) {
        kb.isShiftPressed ? engine.redo() : engine.undo();
        _push();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        engine.redo();
        _push();
        return KeyEventResult.handled;
      }
      final insert = engine.mode == VimMode.insert;
      if (kb.isControlPressed && key == LogicalKeyboardKey.keyR && !insert) {
        return _feed('C-r');
      }
      if (kb.isControlPressed && key == LogicalKeyboardKey.bracketLeft) {
        return _feed('Esc');
      }
      return KeyEventResult.ignored;
    }
    if (kb.isAltPressed && !altGr) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape) return _feed('Esc');
    if (engine.mode == VimMode.insert &&
        engine.lineText == null &&
        engine.crlf &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      // The native Enter inserts `\n`: on a CRLF text insert the file's own
      // ending, so the endings do not mix.
      final c = widget.controller;
      final v = c.value;
      final sel = v.selection.isValid
          ? v.selection
          : TextSelection.collapsed(offset: v.text.length);
      c.value = TextEditingValue(
        text: v.text.replaceRange(sel.start, sel.end, '\r\n'),
        selection: TextSelection.collapsed(offset: sel.start + 2),
      );
      return KeyEventResult.handled;
    }
    if (engine.mode == VimMode.insert && engine.lineText == null) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.backspace) return _feed('BS');
    final token = keyToken(e, shift: kb.isShiftPressed);
    if (token == null) return KeyEventResult.ignored;
    return _feed(token);
  }

  KeyEventResult _feed(String token) {
    engine.feed(token);
    _push();
    return KeyEventResult.handled;
  }

  Offset? _down;

  void _pointerDown(PointerDownEvent e) {
    // Only a primary-button press can start a click.
    _down = e.buttons == kPrimaryButton ? e.position : null;
  }

  /// A click into the field: INSERT at the click. A drag (selection handles,
  /// the scrollbar, a text selection), a non-primary button does not
  /// switch modes.
  void _pointerUp(PointerUpEvent e) {
    final down = _down;
    _down = null;
    if (down == null || (e.position - down).distance > kTouchSlop) return;
    if (!_active || engine.mode == VimMode.insert) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || engine.mode == VimMode.insert) return;
      final f = FocusManager.instance.primaryFocus?.context;
      if (f == null || f.findAncestorStateOfType<_VimFieldState>() != this) {
        return;
      }
      final sel = widget.controller.selection;
      if (!sel.isValid) return;
      engine.external(widget.controller.value);
      engine.enterInsertAt(sel.baseOffset, sel.extentOffset);
    });
  }

  Widget _plain({bool readOnly = false, bool? showCursor}) => field(
    key: widget.fieldKey,
    controller: widget.controller,
    minLines: widget.minLines,
    maxLines: null,
    label: widget.label,
    readOnly: readOnly,
    showCursor: showCursor,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      if (!_active) return _plain();
      final t = tokensOf(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _key,
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerUp,
              onPointerCancel: (_) => _down = null,
              child: ListenableBuilder(
                listenable: engine,
                builder: (context, _) => _plain(
                  readOnly: engine.mode != VimMode.insert,
                  showCursor: true,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: t.space.xs),
            child: ListenableBuilder(
              listenable: engine,
              builder: (context, _) {
                final line = engine.lineText;
                final pending = engine.pending;
                final msg = engine.message;
                final insert = engine.mode == VimMode.insert;
                return Row(
                  children: [
                    Text(
                      engine.modeLabel,
                      key: const Key('vim-mode'),
                      style: t.type.captionStrong.copyWith(
                        color: insert ? t.muted : t.accent,
                      ),
                    ),
                    SizedBox(width: t.space.md),
                    if (line != null)
                      Flexible(
                        child: Text(
                          line,
                          key: const Key('vim-ex'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.type.monoStyle,
                        ),
                      )
                    else if (msg.isNotEmpty)
                      Flexible(
                        child: Text(
                          msg,
                          key: const Key('vim-message'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.type.captionStyle.copyWith(color: t.error),
                        ),
                      )
                    else if (pending.isNotEmpty)
                      Text(
                        pending,
                        key: const Key('vim-pending'),
                        style: t.type.monoStyle.copyWith(color: t.muted),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
