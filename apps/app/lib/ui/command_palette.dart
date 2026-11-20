import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyEvent, KeyUpEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../state/app_action.dart';
import '../state/app_state.dart';
import '../state/palette_model.dart';
import '../state/palette_recents.dart';
import 'app_actions.dart';
import 'parts.dart';
import 'theme.dart';

bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Binds Ctrl+K and Cmd+K (the only shortcuts bound so far) to the command
/// palette for everything below it. The shell supplies the autofocused node
/// that makes the chord work before anything is clicked. The chord also works while a text field
/// has focus: no other key is taken from the field.
class PaletteShortcuts extends StatelessWidget {
  const PaletteShortcuts({super.key, required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
          showCommandPalette(context, state),
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
          showCommandPalette(context, state),
    },
    child: child,
  );
}

/// Navigators that have a palette open (a second chord does nothing).
final _open = Expando<bool>('palette open');

/// Opens the palette over [context]'s Navigator. On close the focus returns
/// to what had it, then the chosen entry runs.
Future<void> showCommandPalette(BuildContext context, AppState state) async {
  final nav = Navigator.of(context);
  if (_open[nav] == true) {
    // The palette chord again closes it.
    nav.pop();
    return;
  }
  _open[nav] = true;
  final before = FocusManager.instance.primaryFocus;
  final recents = PaletteRecents(state.prefs);
  PaletteEntry? picked;
  try {
    picked = await showGeneralDialog<PaletteEntry>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close command palette',
      barrierColor: tokensOf(context).barrier,
      transitionDuration: Duration.zero,
      pageBuilder: (ctx, _, _) => CommandPalette(
        state: state,
        actions: buildActions(state),
        recents: recents.read(),
      ),
    );
  } finally {
    _open[nav] = false;
  }
  if (before != null && before.context != null && before.canRequestFocus) {
    before.requestFocus();
  }
  if (picked == null || !context.mounted) return;
  if (picked.id != null) recents.add(picked.id!);
  await picked.run(
    ActionContext(
      state,
      context,
      openPalette: () => showCommandPalette(context, state),
    ),
  );
}

/// The palette's content: a search field over a list of results.
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.state,
    required this.actions,
    this.recents = const [],
  });
  final AppState state;
  final List<AppAction> actions;
  final List<String> recents;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  var _index = 0;
  var _entries = <PaletteEntry>[];
  final _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    _entries = paletteEntries(
      widget.state,
      widget.actions,
      _text.text,
      recents: widget.recents,
      apple: _apple,
    );
    _index = 0;
    _keys.clear();
  }

  void _move(int by) {
    if (_entries.isEmpty) return;
    setState(() => _index = (_index + by).clamp(0, _entries.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[_index]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c);
    });
  }

  void _choose(int i) {
    if (i < 0 || i >= _entries.length) return;
    Navigator.of(context).pop(_entries[i]);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (widget.state.chords.idFor(e, HardwareKeyboard.instance) ==
        'palette.open') {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      _choose(_index);
    } else if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final rows = <Widget>[];
    String? last;
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (e.group != last) {
        last = e.group;
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              t.space.lg,
              t.space.md,
              t.space.lg,
              t.space.xs,
            ),
            child: Text(
              e.group.toUpperCase(),
              style: t.type.captionStyle.copyWith(color: t.muted),
            ),
          ),
        );
      }
      rows.add(
        _Row(
          key: _keys[i] = GlobalKey(),
          entry: e,
          selected: i == _index,
          onHover: () {
            if (_index != i) setState(() => _index = i);
          },
          onTap: () => _choose(i),
        ),
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            t.space.lg,
            t.space.huge,
            t.space.lg,
            t.space.lg,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: t.sizes.dialogXl),
            child: DecoratedBox(
              key: const Key('palette'),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(t.radii.card),
                border: Border.all(
                  color: t.panelBorder,
                  width: t.borders.hairline,
                ),
              ),
              child: Focus(
                onKeyEvent: _onKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(t.space.md),
                      child: field(
                        key: const Key('palette-field'),
                        controller: _text,
                        autofocus: true,
                        hint: 'Type a command or search',
                        onChange: (_) => setState(_refresh),
                      ),
                    ),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                        ),
                        child: _entries.isEmpty
                            ? Padding(
                                padding: EdgeInsets.all(t.space.xl),
                                child: Text(
                                  'No matches',
                                  key: const Key('palette-empty'),
                                  style: t.type.bodyStyle.copyWith(
                                    color: t.muted,
                                  ),
                                ),
                              )
                            : ListView(
                                key: const Key('palette-list'),
                                controller: _scroll,
                                shrinkWrap: true,
                                padding: EdgeInsets.only(bottom: t.space.sm),
                                children: rows,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.entry,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });
  final PaletteEntry entry;
  final bool selected;
  final VoidCallback onHover, onTap;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: Key('palette-row-${entry.id ?? entry.uid}'),
          margin: EdgeInsets.symmetric(horizontal: t.space.sm),
          padding: EdgeInsets.symmetric(
            horizontal: t.space.md,
            vertical: t.space.md,
          ),
          decoration: BoxDecoration(
            color: selected ? t.selected : null,
            borderRadius: BorderRadius.circular(t.radii.control),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.title.isEmpty ? '(untitled)' : entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.type.bodyStyle.copyWith(color: t.fg),
                ),
              ),
              if (entry.hint != null) ...[
                SizedBox(width: t.space.md),
                Text(
                  entry.hint!,
                  style: t.type.captionStyle.copyWith(color: t.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
