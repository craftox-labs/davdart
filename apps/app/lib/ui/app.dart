import 'dart:math' as math;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/browser_storage_stub.dart'
    if (dart.library.js_interop) '../data/browser_storage_web.dart';
import '../data/key_value_storage.dart';
import '../data/note_source.dart';
import '../data/space_catalog.dart';
import '../state/app_state.dart';
import '../state/note_draft.dart';
import '../theme/tokens.dart';
import 'board_view.dart';
import 'detail_header.dart';
import 'detail_view.dart';
import 'list_view.dart';
import 'parts.dart';
import 'resize_handle.dart';
import 'scope_bar.dart';
import 'shell_frame.dart';
import 'sidebar.dart';
import 'tab_strip.dart';
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
    this.tokens,
  }) : state =
           state ??
           (source == null
               ? _fromCatalog(defaultCatalog())
               : AppState(source, prefs: prefs)) {
    this.state.load();
  }

  final AppState state;

  /// Replaces the default light and dark tokens (previews, tests).
  final Tokens? tokens;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      title: 'davdart',
      color: (tokens ?? Tokens.light).accent,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: FLocalizations.localizationsDelegates,
      supportedLocales: FLocalizations.supportedLocales,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      builder: (context, child) {
        final themed = FTheme(
          data: buildTheme(
            MediaQuery.platformBrightnessOf(context),
            touch: isTouchPlatform,
            tokens: tokens,
          ),
          child: FToaster(child: FTooltipGroup(child: child!)),
        );
        final custom = tokens;
        return custom == null
            ? themed
            : TokensScope(tokens: custom, child: themed);
      },
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

          final mirror = state.layoutSide == LayoutSide.end;
          final Widget body;
          if (wide && state.fullPage) {
            // The note fills the main panel; the peek pane is hidden.
            body = DetailView(
              key: const Key('full-page'),
              state: state,
              onClose: () => state.guarded(() => state.select(null)),
              full: true,
            );
          } else if (split) {
            body = LayoutBuilder(
              builder: (context, bc) {
                final z = t.sizes;
                final hi = detailMaxFor(t, bc.maxWidth);
                final width = detailWidthFor(t, state, bc.maxWidth);
                final divider = Container(
                  width: t.borders.hairline,
                  color: t.divider,
                );
                final detail = SizedBox(
                  key: const Key('detail-pane'),
                  width: width,
                  child: Stack(
                    children: [
                      DetailView(
                        state: state,
                        onClose: () => state.guarded(() => state.select(null)),
                        onExpand: state.openFullPage,
                        inHeader: true,
                      ),
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: mirror ? null : 0,
                        right: mirror ? 0 : null,
                        child: PaneResizeHandle(
                          key: const Key('detail-handle'),
                          width: width,
                          min: z.detailMin,
                          max: hi,
                          grow: mirror ? 1 : -1,
                          onResize: (w) => state.setDetailWidth(w, save: false),
                          onEnd: () => state.setDetailWidth(state.detailWidth),
                          onReset: () => state.setDetailWidth(null),
                        ),
                      ),
                    ],
                  ),
                );
                return Row(
                  children: [
                    if (mirror && hasDetail) ...[detail, divider],
                    Expanded(child: main()),
                    if (!mirror && hasDetail) ...[divider, detail],
                  ],
                );
              },
            );
          } else if (hasDetail) {
            // Wide but not split: the note replaces the list; Expand and Close
            // are on the header's detail tab.
            body = DetailView(
              state: state,
              onClose: () => state.guarded(() => state.select(null)),
              inHeader: wide,
            );
          } else {
            body = main();
          }

          Widget content = FScaffold(
            childPad: false,
            header: TopBar(state: state, showMenu: !wide),
            child: body,
          );
          if (wide && !state.sidebarCollapsed) {
            // Docked beside the content, on the side facing it: left of it
            // normally, right of it when the rail is on the right.
            final dock = IconTheme(
              data: context.theme.style.iconStyle,
              child: DockedSidebar(state: state),
            );
            content = Row(
              children: [
                if (!mirror) dock,
                Expanded(child: content),
                if (mirror) dock,
              ],
            );
          }

          // The header row, over the panel: the tab strip above the main
          // content, the detail tab above the detail pane, the side panel's
          // width left empty.
          Widget header(BuildContext context, double panelWidth) {
            final dockW = state.sidebarCollapsed
                ? 0.0
                : sidebarWidthOf(context, state);
            final contentW = panelWidth - dockW;
            final detailW = hasDetail && !state.fullPage
                ? detailWidthFor(t, state, contentW)
                : null;
            // Clear of the panel's rounded corner where the strip starts at
            // the panel edge, else just the concave corner.
            final edgePad = t.radii.panel + t.radii.tab;
            final strip = Expanded(
              child: TabStrip(
                state: state,
                startPad: mirror
                    ? (detailW != null ? t.radii.tab : edgePad)
                    : (dockW > 0 ? t.radii.tab : edgePad),
                endPad: !mirror && detailW != null ? t.radii.tab : t.space.sm,
              ),
            );
            final detail = detailW == null
                ? null
                : DetailHeader(state: state, width: detailW, mirror: mirror);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (mirror) ?detail else SizedBox(width: dockW),
                strip,
                if (mirror) SizedBox(width: dockW) else ?detail,
              ],
            );
          }

          return _LeaveGuard(
            state: state,
            child: SafeArea(
              child: wide
                  ? CallbackShortcuts(
                      bindings: {
                        const SingleActivator(
                          LogicalKeyboardKey.keyW,
                          control: true,
                        ): state.closeActiveTab,
                        const SingleActivator(
                          LogicalKeyboardKey.keyW,
                          meta: true,
                        ): state.closeActiveTab,
                      },
                      child: ShellFrame(
                        state: state,
                        showRail: true,
                        header: header,
                        child: content,
                      ),
                    )
                  : ShellFrame(state: state, showRail: false, child: content),
            ),
          );
        },
      ),
    );
  }
}

/// The widest the detail pane may be beside a main area [content] wide (the
/// list keeps its least width).
double detailMaxFor(Tokens t, double content) => math.max(
  t.sizes.detailMin,
  math.min(t.sizes.detailMax, content - t.sizes.listMin),
);

/// The detail pane's width in a main area [content] wide: the dragged width
/// (or the default) within the limits.
double detailWidthFor(Tokens t, AppState state, double content) =>
    (state.detailWidth ?? t.sizes.detail).clamp(
      t.sizes.detailMin,
      detailMaxFor(t, content),
    );

/// Registers the dialog asked when leaving a note with unsaved edits.
class _LeaveGuard extends StatefulWidget {
  const _LeaveGuard({required this.state, required this.child});
  final AppState state;
  final Widget child;

  @override
  State<_LeaveGuard> createState() => _LeaveGuardState();
}

class _LeaveGuardState extends State<_LeaveGuard> {
  @override
  void initState() {
    super.initState();
    widget.state.leaveGuard = _ask;
  }

  @override
  void dispose() {
    if (widget.state.leaveGuard == _ask) widget.state.leaveGuard = null;
    super.dispose();
  }

  Future<DraftChoice> _ask() async =>
      await showAppDialog<DraftChoice>(
        context,
        title: 'Unsaved changes',
        content: const Text('This note has edits that are not saved yet.'),
        actions: [
          const CancelButton(label: 'Keep editing'),
          FButton(
            key: const Key('leave-discard'),
            variant: FButtonVariant.outline,
            mainAxisSize: MainAxisSize.min,
            onPress: () => Navigator.of(context).pop(DraftChoice.discard),
            child: const Text('Discard'),
          ),
          ActionButton(
            'Save',
            key: const Key('leave-save'),
            onPress: (ctx) => Navigator.of(ctx).pop(DraftChoice.save),
          ),
        ],
      ) ??
      DraftChoice.keep;

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens the sidebar as a sheet from the left edge (the narrow-screen drawer).
Future<void> openSidebarSheet(BuildContext context, AppState state) =>
    showFSheet<void>(
      context: context,
      side: FLayout.ltr,
      mainAxisMaxRatio: null,
      constraints: BoxConstraints(maxWidth: tokensOf(context).sizes.sidebar),
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
    final narrow = MediaQuery.sizeOf(context).width < t.sizes.narrowBar;
    final board = state.view == ViewMode.board;
    Widget toggle(String label, ViewMode mode) => FButton(
      variant: state.view == mode
          ? FButtonVariant.secondary
          : FButtonVariant.outline,
      size: FButtonSizeVariant.xs,
      mainAxisSize: MainAxisSize.min,
      selected: state.view == mode,
      onPress: () => state.setView(mode),
      child: Text(label),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.divider, width: t.borders.hairline),
        ),
      ),
      child: SizedBox(
        height: t.sizes.topBar,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.md),
          child: Row(
            children: [
              if (showMenu)
                IconAction(
                  compact: true,
                  key: const Key('menu'),
                  tooltip: 'Menu',
                  icon: FLucideIcons.menu,
                  onPress: () => openSidebarSheet(context, state),
                ),
              SizedBox(width: t.space.xs),
              Text(board ? 'Board' : 'List', style: t.type.titleStyle),
              SizedBox(width: t.space.lg),
              if (state.loading)
                SizedBox(
                  width: t.sizes.spinner,
                  height: t.sizes.spinner,
                  child: const FCircularProgress(),
                ),
              const Spacer(),
              if (!narrow) ...[
                toggle('Board', ViewMode.board),
                SizedBox(width: t.space.xs),
                toggle('List', ViewMode.list),
              ] else
                IconAction(
                  compact: true,
                  tooltip: board ? 'Show list' : 'Show board',
                  icon: board ? FLucideIcons.list : FLucideIcons.squareKanban,
                  onPress: () =>
                      state.setView(board ? ViewMode.list : ViewMode.board),
                ),
              IconAction(
                compact: true,
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
