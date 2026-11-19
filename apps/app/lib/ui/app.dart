import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/browser_storage_stub.dart'
    if (dart.library.js_interop) '../data/browser_storage_web.dart';
import '../data/key_value_storage.dart';
import '../data/note_source.dart';
import '../data/space_catalog.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'board_view.dart';
import 'detail_view.dart';
import 'list_view.dart';
import 'parts.dart';
import 'scope_bar.dart';
import 'shell_frame.dart';
import 'sidebar.dart';
import 'theme.dart';

/// The real app: Spaces kept in browser storage. `Planning` is filled once
/// from the board server's feed; edits stay on this device until a server is
/// connected.
SpaceCatalog defaultCatalog() =>
    SpaceCatalog(defaultStorage(), planningSeed: ApiNoteSource());

AppState _fromCatalog(SpaceCatalog c) =>
    AppState(c.sourceFor(c.current), prefs: c.storage, catalog: c);

class DavdartApp extends StatelessWidget {
  DavdartApp({
    super.key,
    NoteSource? source,
    KeyValueStorage? prefs,
    AppState? state,
  }) : state =
           state ??
           (source == null
               ? _fromCatalog(defaultCatalog())
               : AppState(source, prefs: prefs)) {
    this.state.load();
  }

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'davdart',
      color: Tokens.light.accent,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      builder: (context, child) => FTheme(
        data: buildTheme(
          MediaQuery.platformBrightnessOf(context),
          touch: isTouchPlatform,
        ),
        child: FToaster(child: FTooltipGroup(child: child!)),
      ),
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
          final t = tokensOf(context);
          final wide = c.maxWidth >= Tokens.wideBreakpoint;
          final split = c.maxWidth >= Tokens.splitBreakpoint;
          final hasDetail = state.selected != null;

          Widget main() => Column(
            children: [
              ScopeBar(state: state),
              Expanded(
                child: state.view == ViewMode.board
                    ? BoardView(state: state)
                    : NoteListView(state: state),
              ),
            ],
          );

          final Widget body;
          if (split) {
            body = Row(
              children: [
                Expanded(child: main()),
                if (hasDetail) ...[
                  Container(width: 1, color: t.line),
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

          return SafeArea(
            child: ShellFrame(
              state: state,
              showRail: wide,
              child: FScaffold(
                childPad: false,
                sidebar: wide ? Sidebar(state: state) : null,
                header: TopBar(state: state, showMenu: !wide),
                child: body,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Opens the sidebar as a sheet from the left edge (the narrow-screen drawer).
Future<void> openSidebarSheet(BuildContext context, AppState state) =>
    showFSheet<void>(
      context: context,
      side: FLayout.ltr,
      mainAxisMaxRatio: null,
      constraints: const BoxConstraints(maxWidth: Tokens.sidebarWidth),
      useSafeArea: true,
      builder: (_) => ListenableBuilder(
        listenable: state,
        builder: (_, _) =>
            _CloseWhenWide(child: Sidebar(state: state, inDrawer: true)),
      ),
    );

/// Pops the sheet it sits in once the window grows to the wide layout, where
/// the sidebar is docked.
class _CloseWhenWide extends StatefulWidget {
  const _CloseWhenWide({required this.child});
  final Widget child;

  @override
  State<_CloseWhenWide> createState() => _CloseWhenWideState();
}

class _CloseWhenWideState extends State<_CloseWhenWide> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    if (!_closing &&
        MediaQuery.sizeOf(context).width >= Tokens.wideBreakpoint) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    return widget.child;
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.state, required this.showMenu});
  final AppState state;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 440;
    final board = state.view == ViewMode.board;
    Widget toggle(String label, ViewMode mode) => FButton(
      variant: state.view == mode
          ? FButtonVariant.secondary
          : FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      mainAxisSize: MainAxisSize.min,
      selected: state.view == mode,
      onPress: () => state.setView(mode),
      child: Text(label),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (showMenu)
                IconAction(
                  key: const Key('menu'),
                  tooltip: 'Menu',
                  icon: FLucideIcons.menu,
                  onPress: () => openSidebarSheet(context, state),
                ),
              const SizedBox(width: 4),
              Text(
                board ? 'Board' : 'List',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              if (state.loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: FCircularProgress(),
                ),
              const Spacer(),
              if (!narrow) ...[
                toggle('Board', ViewMode.board),
                const SizedBox(width: 4),
                toggle('List', ViewMode.list),
              ] else
                IconAction(
                  tooltip: board ? 'Show list' : 'Show board',
                  icon: board ? FLucideIcons.list : FLucideIcons.squareKanban,
                  onPress: () =>
                      state.setView(board ? ViewMode.list : ViewMode.board),
                ),
              IconAction(
                tooltip: 'Reload',
                icon: FLucideIcons.refreshCw,
                onPress: state.load,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
