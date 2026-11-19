import 'package:material_ui/material_ui.dart';

import 'package:davdart/davdart.dart';

import '../data/browser_storage_stub.dart'
    if (dart.library.js_interop) '../data/browser_storage_web.dart';
import '../data/key_value_storage.dart';
import '../data/note_source.dart';
import '../data/persistent_store.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'board_view.dart';
import 'detail_view.dart';
import 'list_view.dart';
import 'markdown_lite.dart';
import 'sidebar.dart';

ThemeData buildTheme(Tokens t, Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: t.accent, brightness: b)
      .copyWith(
        surface: t.bg,
        onSurface: t.fg,
        primary: t.accent,
        outline: t.line,
        outlineVariant: t.line,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    splashFactory: NoSplash.splashFactory,
    extensions: [TokensTheme(t)],
    textTheme: Typography.material2021().black.apply(
      bodyColor: t.fg,
      displayColor: t.fg,
      fontFamily: 'Roboto',
    ),
  );
}

/// The real app: a local Space kept in browser storage, filled once from the
/// board server's feed. Edits stay on this device until a server is attached.
NoteSource defaultSource() {
  final storage = defaultStorage();
  return SpaceNoteSource(
    Space(
      SpaceConfig(id: 'planning', name: 'Planning'),
      PersistentNoteStore(storage),
    ),
    seed: ApiNoteSource(),
    flags: storage,
  );
}

class DavdartApp extends StatelessWidget {
  DavdartApp({super.key, NoteSource? source, KeyValueStorage? prefs})
    : state = source == null
          ? AppState(defaultSource(), prefs: defaultStorage())
          : AppState(source, prefs: prefs) {
    state.load();
  }

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'davdart',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Tokens.light, Brightness.light),
      darkTheme: buildTheme(Tokens.dark, Brightness.dark),
      themeMode: ThemeMode.system,
      home: Shell(state: state),
    );
  }
}

/// Sidebar, main view and detail, arranged by width: three panes on a wide
/// screen, sidebar plus one pane in the middle, a drawer and one pane on a
/// phone.
class Shell extends StatelessWidget {
  const Shell({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final t = Theme.of(context).extension<TokensTheme>()!.tokens;
          final wide = c.maxWidth >= Tokens.wideBreakpoint;
          final split = c.maxWidth >= Tokens.splitBreakpoint;
          final hasDetail = state.selected != null;

          Widget main() => state.view == ViewMode.board
              ? BoardView(state: state)
              : NoteListView(state: state);

          final Widget body;
          if (split) {
            body = Row(
              children: [
                Expanded(child: main()),
                if (hasDetail) ...[
                  VerticalDivider(width: 1, color: t.line),
                  SizedBox(
                    width: Tokens.detailWidth,
                    child: DetailView(
                      state: state,
                      onClose: () => state.select(null),
                    ),
                  ),
                ],
              ],
            );
          } else if (hasDetail) {
            body = DetailView(state: state, onClose: () => state.select(null));
          } else {
            body = main();
          }

          final content = Column(
            children: [
              TopBar(state: state, showMenu: !wide),
              Divider(height: 1, color: t.line),
              Expanded(child: body),
            ],
          );

          return Scaffold(
            drawer: wide
                ? null
                : Drawer(
                    width: Tokens.sidebarWidth,
                    backgroundColor: t.bg,
                    child: SafeArea(
                      child: Sidebar(state: state, inDrawer: true),
                    ),
                  ),
            body: SafeArea(
              child: wide
                  ? Row(
                      children: [
                        SizedBox(
                          width: Tokens.sidebarWidth,
                          child: Sidebar(state: state),
                        ),
                        VerticalDivider(width: 1, color: t.line),
                        Expanded(child: content),
                      ],
                    )
                  : content,
            ),
          );
        },
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.state, required this.showMenu});
  final AppState state;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (showMenu)
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: 'Menu',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              state.view == ViewMode.board ? 'Board' : 'List',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            if (state.loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            const Spacer(),
            if (MediaQuery.sizeOf(context).width >= 440)
              SegmentedButton<ViewMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: t.line),
                ),
                segments: const [
                  ButtonSegment(value: ViewMode.board, label: Text('Board')),
                  ButtonSegment(value: ViewMode.list, label: Text('List')),
                ],
                selected: {state.view},
                onSelectionChanged: (s) => state.setView(s.first),
              ),
            if (MediaQuery.sizeOf(context).width < 440)
              IconButton(
                tooltip: state.view == ViewMode.board
                    ? 'Show list'
                    : 'Show board',
                icon: Icon(
                  state.view == ViewMode.board
                      ? Icons.list
                      : Icons.view_kanban_outlined,
                ),
                onPressed: () => state.setView(
                  state.view == ViewMode.board ? ViewMode.list : ViewMode.board,
                ),
              ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: state.load,
            ),
          ],
        ),
      ),
    );
  }
}
