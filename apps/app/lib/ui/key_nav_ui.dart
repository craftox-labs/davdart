import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../state/app_action.dart';
import '../state/app_state.dart';
import '../state/key_bindings.dart';
import '../state/key_nav.dart';
import 'app_actions.dart';
import 'command_palette.dart';
import 'theme.dart';

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

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return KeyEventResult.ignored;
    if (_typing) {
      if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
        nav.node.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final token = keyToken(e, shift: kb.isShiftPressed);
    if (token == null) return KeyEventResult.ignored;
    final pending = nav.pending;

    // Esc first clears a half-typed sequence or count.
    if (token == 'Esc' && (pending.isNotEmpty || nav.count > 0)) {
      nav.clearPending();
      return KeyEventResult.handled;
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
    final bindings = KeyBindings(buildActions(state), vim: state.vimKeys);
    final step = bindings.resolve(pending, token);
    if (step.keys != null) {
      nav.setPending(step.keys!);
      return KeyEventResult.handled;
    }
    final a = step.action;
    if (a != null &&
        token.length > 1 &&
        token != 'Esc' &&
        navListId(state, nav.area) == null) {
      // Arrows, Enter, Home and End belong to the widgets where there is no
      // list under the cursor.
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
    return Listener(
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
    );
  }
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
