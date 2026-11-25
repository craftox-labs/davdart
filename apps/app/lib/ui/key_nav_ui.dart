import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_action.dart';
import '../state/app_state.dart';
import '../state/key_bindings.dart';
import '../state/key_nav.dart';
import 'app_actions.dart';
import 'command_palette.dart';
import 'note_editor.dart' show imeComposing;
import 'popover_track.dart';
import 'theme.dart';

/// Actions that move the keyboard's area or view: a text field gives up the
/// focus for them (chords, the Vim editor's Space leader).
bool navigatingAction(String id) =>
    id.startsWith('focus.') ||
    id.startsWith('go.') ||
    id.startsWith('tab.') ||
    id == 'panel.toggle' ||
    id == 'peek.toggle';

/// Rows are all built (a big cache extent) so a cursor can scroll to any row.
final navCacheExtent = ScrollCacheExtent.pixels(100000);

/// Catches the bare keys for everything below it: runs the registry's
/// actions bound to them (see [KeyBindings]). Text fields keep every key (Esc
/// leaves one), dialogs and the palette are separate routes and never reach
/// it, and chords with Ctrl, Cmd or Alt are left to their own bindings.
class KeyNavHandler extends StatefulWidget {
  const KeyNavHandler({super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  State<KeyNavHandler> createState() => _KeyNavHandlerState();
}

class _KeyNavHandlerState extends State<KeyNavHandler> {
  AppState get state => widget.state;
  KeyNav get nav => state.nav;

  bool get _typing {
    final c = FocusManager.instance.primaryFocus?.context;
    if (c == null) return false;
    return c.widget is EditableText ||
        c.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyBindings? _table;
  bool? _tableVim;
  String? _tableSpaces;

  /// The binding table, rebuilt only when the Vim setting or the Space list
  /// changes (shortcut labels are otherwise fixed; `enabled` runs at key
  /// time).
  KeyBindings get _bindings {
    final sig = state.spaces
        .map((s) => '${s.id}\u0001${s.name}')
        .join('\u0000');
    if (_table == null || _tableVim != state.vimKeys || _tableSpaces != sig) {
      _table = KeyBindings(buildActions(state), vim: state.vimKeys);
      _tableVim = state.vimKeys;
      _tableSpaces = sig;
    }
    return _table!;
  }

  /// A focused control other than the key catcher (a button, chip, toggle):
  /// Enter and Space belong to it.
  bool get _control {
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f == nav.node || f is FocusScopeNode) return false;
    final c = f.context;
    if (c == null) return false;
    var found = false;
    bool check(Widget w) {
      if (w is SelectableRegion) return true; // selectable text
      if (w is FTappable || w is FButton) {
        found = true;
        return true;
      }
      if (w is Actions &&
          (w.actions.containsKey(ActivateIntent) ||
              w.actions.containsKey(ButtonActivateIntent))) {
        found = true;
        return true;
      }
      return false;
    }

    if (check(c.widget)) return found;
    c.visitAncestorElements((e) {
      if (e.widget == widget) return false;
      return !check(e.widget);
    });
    return found;
  }

  bool _restoring = false;

  void _focusChanged() {
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f is! FocusScopeNode) return;
    _restoreSoon();
  }

  /// Puts the focus back on the key catcher when it would otherwise be lost
  /// (a field or dialog closed, a click on empty space).
  void _restoreSoon() {
    if (_restoring) return;
    _restoring = true;
    Future.microtask(() {
      _restoring = false;
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final f = FocusManager.instance.primaryFocus;
      if (f != null && f is! FocusScopeNode) return;
      // A dropdown that is open manages its own focus; it is restored when
      // the dropdown closes (the focus change fires again).
      if (popoverOpen()) return;
      if (nav.node.context != null && nav.node.canRequestFocus) {
        nav.node.requestFocus();
      }
    });
  }

  /// After a click: a focused control (not a text field, not inside a popover
  /// or dialog) hands the focus back to the key catcher, so it keeps no ring.
  void _releaseSoon() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final f = FocusManager.instance.primaryFocus;
    if (f == null || f == nav.node || f is FocusScopeNode) return;
    if (_typing) return;
    final c = f.context;
    if (c == null || c.findAncestorWidgetOfExactType<OverlayPortal>() != null) {
      return;
    }
    // Selectable text keeps the focus, so Ctrl/Cmd+C copies the selection.
    if (c.findAncestorWidgetOfExactType<SelectableRegion>() != null) return;
    if (nav.node.context != null && nav.node.canRequestFocus) {
      nav.node.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  /// The global chord layer: runs the action bound to [e], also while a text
  /// field has focus. A chord is always handled (also repeats, and when the
  /// action is not enabled) so it never reaches the field or the browser;
  /// an IME that is composing keeps its keys.
  KeyEventResult _chord(KeyEvent e) {
    final kb = HardwareKeyboard.instance;
    final id = state.chords.idFor(e, kb);
    if (id == null) return KeyEventResult.ignored;
    if (imeComposing()) return KeyEventResult.ignored;
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    // An open dropdown or date picker owns the keyboard: a chord would act
    // behind it (only the palette chord goes through).
    if (id != 'palette.open' && PopoverTracker.instance.active) {
      return KeyEventResult.handled;
    }
    final a = buildActions(state).where((a) => a.id == id).firstOrNull;
    if (a == null || !a.enabled(state)) return KeyEventResult.handled;
    if (navigatingAction(id)) {
      if (_typing) nav.node.requestFocus();
      nav.markShown();
    }
    nav.clearPending();
    Future.sync(
      () => a.run(
        ActionContext(
          state,
          context,
          openPalette: () => showCommandPalette(context, state),
        ),
      ),
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    final route = ModalRoute.of(context);
    final kb0 = HardwareKeyboard.instance;
    final paletteChord = state.chords.idFor(e, kb0) == 'palette.open';
    // Behind another route nothing runs, except the palette chord closing the
    // palette itself (never opening it over a dialog).
    if (route != null &&
        !route.isCurrent &&
        !(paletteChord && paletteOpen(context))) {
      return KeyEventResult.ignored;
    }
    if (e is! KeyUpEvent) {
      final r = _chord(e);
      if (r == KeyEventResult.handled) return r;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (_typing) {
      if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
        nav.node.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;
    if ((kb.isControlPressed || kb.isMetaPressed) &&
        !kb.isAltPressed &&
        (e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      // Ctrl/Cmd+Enter: save and leave the open edit (the key catcher holds
      // the focus; inside a field the editor handles it).
      if (editingUid(state) == null) return KeyEventResult.ignored;
      final save = buildActions(state)
          .firstWhere((a) => a.id == 'edit.save-exit');
      Future.sync(() => save.run(ActionContext(state, context)));
      return KeyEventResult.handled;
    }
    if ((kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) &&
        !isAltGrChar(e, kb)) {
      return KeyEventResult.ignored;
    }
    final token = keyToken(e, shift: kb.isShiftPressed);
    if (token == null) return KeyEventResult.ignored;
    final pending = nav.pending;

    // Enter and Space activate a focused control; the cursor row's Enter
    // applies only when the key catcher itself holds the focus.
    if (token == 'Enter' || token == ' ') {
      if (_control) return KeyEventResult.ignored;
      // Selectable text or a plain focus node: the cursor row's action runs
      // and the key catcher takes the focus back.
      final f = FocusManager.instance.primaryFocus;
      if (f != null && f != nav.node && f is! FocusScopeNode) {
        nav.node.requestFocus();
      }
    }

    // Esc first clears a half-typed sequence or count, then hides the cursor
    // and rings (and takes the focus off a control); only when nothing shows
    // does it move the area focus up (the registry's Esc action).
    if (token == 'Esc') {
      final f = FocusManager.instance.primaryFocus;
      final off = f != null && f != nav.node && f is! FocusScopeNode;
      if (PopoverTracker.instance.dismiss()) return KeyEventResult.handled;
      if (pending.isNotEmpty || nav.count > 0) {
        nav.clearPending();
        if (nav.shown) nav.hide();
        if (off) nav.node.requestFocus();
        return KeyEventResult.handled;
      }
      if (nav.shown || off) {
        nav.hide();
        if (off) nav.node.requestFocus();
        return KeyEventResult.handled;
      }
    }
    // A numeric prefix (5j), Vim keys only.
    if (state.vimKeys &&
        pending.isEmpty &&
        token.length == 1 &&
        RegExp('[0-9]').hasMatch(token) &&
        (token != '0' || nav.count > 0)) {
      nav.setPending(const [], count: (nav.count * 10 + int.parse(token)));
      return KeyEventResult.handled;
    }
    final step = _bindings.resolve(pending, token);
    if (step.keys != null) {
      nav.setPending(step.keys!);
      return KeyEventResult.handled;
    }
    final a = step.action;
    if (a != null &&
        token.length > 1 &&
        token != 'Esc' &&
        navListId(state, nav.area) == null &&
        !(const {'Down', 'Up', 'Home', 'End'}.contains(token) &&
            nav.hasPage(nav.area) &&
            !PopoverTracker.instance.active)) {
      // Arrows, Enter, Home and End belong to the widgets where there is no
      // list under the cursor (but an open item page takes Down, Up, Home and
      // End: it scrolls).
      return KeyEventResult.ignored;
    }
    if (a == null) {
      final had = pending.isNotEmpty || nav.count > 0;
      nav.clearPending();
      return had ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    nav.markShown();
    if (a.enabled(state)) {
      Future.sync(
        () => a.run(
          ActionContext(
            state,
            context,
            openPalette: () => showCommandPalette(context, state),
          ),
        ),
      );
    }
    nav.clearPending();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // A press hides the cursor and rings (keyboard modality ends). A press
        // on empty space drops the focus to the scope; take it back. After a
        // click on a control, the focus returns to the key catcher too (a
        // text field keeps it), so no ring stays on it.
        onPointerDown: (_) {
          nav.hide();
          WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSoon());
        },
        onPointerUp: (_) =>
            WidgetsBinding.instance.addPostFrameCallback((_) => _releaseSoon()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            Positioned(
              left: t.space.lg,
              bottom: t.space.lg,
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: nav,
                  builder: (context, _) {
                    final label = nav.pendingLabel;
                    if (label.isEmpty) return const SizedBox.shrink();
                    return DecoratedBox(
                      key: const Key('key-pending'),
                      decoration: BoxDecoration(
                        color: t.card,
                        border: Border.all(color: t.cardBorder),
                        borderRadius: BorderRadius.circular(t.radii.small),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.space.md,
                          vertical: t.space.xs,
                        ),
                        child: Text(
                          label,
                          style: t.type.captionStyle.copyWith(color: t.fg),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Marks a pane as the keyboard's area: a thin accent bar on its start edge
/// while the keyboard is in use and this area has the focus (painted over,
/// no layout shift). A press inside moves the focus here.
class AreaMark extends StatelessWidget {
  const AreaMark({
    super.key,
    required this.nav,
    required this.area,
    required this.child,
    this.bar = true,
  });
  final KeyNav nav;
  final NavArea area;
  final Widget child;

  /// False where the rows carry the mark (the rail).
  final bool bar;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return _AreaScope(
      area: area,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => nav.pointerIn(area),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            child,
            if (bar)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: t.borders.focus,
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: nav,
                    builder: (context, _) => nav.shown && nav.area == area
                        ? ColoredBox(
                            key: Key('area-mark-${area.name}'),
                            color: t.accent,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Says which area a subtree belongs to, so the area that holds the primary
/// focus can be found from the focused node.
class _AreaScope extends InheritedWidget {
  const _AreaScope({required this.area, required super.child});
  final NavArea area;

  @override
  bool updateShouldNotify(_AreaScope old) => area != old.area;
}

/// The area whose subtree holds the primary focus; null when the focus is
/// elsewhere (the key catcher, a dialog).
NavArea? focusedAreaOf() {
  final c = FocusManager.instance.primaryFocus?.context;
  return c?.getInheritedWidgetOfExactType<_AreaScope>()?.area;
}

/// A row of a keyboard list: draws the cursor (an accent outline and tint,
/// distinct from the selected row's fill) while the keyboard is in use and
/// the row is the cursor of its list's focused area; scrolls into view when
/// the cursor arrives; a press puts the cursor and the area here.
class NavRow extends StatefulWidget {
  const NavRow({
    super.key,
    required this.nav,
    required this.list,
    required this.id,
    required this.child,
    this.radius,
  });
  final KeyNav nav;
  final String list;
  final String id;
  final Widget child;
  final double? radius;

  @override
  State<NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<NavRow> {
  bool _on = false;

  bool _compute() =>
      widget.nav.shown &&
      widget.nav.area == KeyNav.areaOfList(widget.list) &&
      widget.nav.isCursor(widget.list, widget.id);

  @override
  void initState() {
    super.initState();
    _on = _compute();
    widget.nav.addListener(_changed);
  }

  @override
  void didUpdateWidget(NavRow old) {
    super.didUpdateWidget(old);
    if (old.nav != widget.nav) {
      old.nav.removeListener(_changed);
      widget.nav.addListener(_changed);
    }
    _changed();
  }

  @override
  void dispose() {
    widget.nav.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final on = _compute();
    if (on == _on) return;
    setState(() => _on = on);
    if (on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final d = widget.nav.lastDir;
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: 0.5,
          alignmentPolicy: d > 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : d < 0
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.explicit,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.nav.pointerOn(widget.list, widget.id),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _on
            ? BoxDecoration(
                color: t.accent.withValues(alpha: 0.1),
                border: Border.all(color: t.accent, width: t.borders.hairline),
                borderRadius: BorderRadius.circular(
                  widget.radius ?? t.radii.small,
                ),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}
