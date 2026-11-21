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
import 'collapsible_section.dart';
import 'command_palette.dart';
import 'key_nav_ui.dart';
import '../state/key_nav.dart';
import 'home_today.dart';
import 'detail_header.dart';
import 'detail_view.dart';
import 'first_run_view.dart';
import 'list_view.dart';
import '../state/tab_state.dart';
import 'logo.dart';
import 'mobile_nav.dart';
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

AppState _fromCatalog(SpaceCatalog c) => AppState(
  c.current == null ? const EmptyNoteSource() : c.sourceFor(c.current!),
  prefs: c.storage,
  catalog: c,
);

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
      home: PaletteShortcuts(
        state: state,
        child: KeyNavHandler(
          state: state,
          child: Shell(state: state),
        ),
      ),
    );
  }
}

/// Sidebar, main view and detail, arranged by width: three panes on a wide
/// screen, sidebar plus one pane in the middle, a drawer and one pane on a
/// phone. The docked sidebar and (split layout) the peek slide open and shut.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

/// Fits [child], laid out at [full] width, into a box [width] wide anchored
/// on the pane's outer edge, so the pane slides in and out without its
/// content reflowing.
class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.width,
    required this.full,
    required this.mirror,
    required this.outerStart,
    required this.child,
  });
  final double width, full;
  final bool mirror;

  /// The pane's outer edge is the start (left) edge when not mirrored.
  final bool outerStart;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Fully open: no clip, so a tab's edge stroke may reach into the divider.
    if (width >= full) return SizedBox(width: full, child: child);
    final left = mirror != outerStart;
    return SizedBox(
      width: width,
      child: ClipRect(
        child: OverflowBox(
          alignment: left ? Alignment.topLeft : Alignment.topRight,
          minWidth: full,
          maxWidth: full,
          child: child,
        ),
      ),
    );
  }
}

class _ShellState extends State<Shell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _dock = AnimationController(
    vsync: this,
    value: _dockOpen ? 1 : 0,
  );
  late final AnimationController _peek = AnimationController(
    vsync: this,
    value: widget.state.hasPeek && !widget.state.peekCollapsed ? 1 : 0,
  );

  /// The last peeked note, kept mounted while the pane slides shut.
  String? _heldPeek;

  /// Whether the last build was wide, to tell a resize from a toggle.
  bool? _wasWide;

  /// Narrow layout: the full-screen side menu and the open-items grid.
  bool _menuOpen = false, _gridOpen = false;
  double _edgeDx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.onNotSaved = (reason) {
      if (mounted) {
        showFToast(context: context, title: Text('Not saved: $reason'));
      }
    };
    widget.state.openMenu = () => setState(() {
      _gridOpen = false;
      _menuOpen = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Narrow: an edit pending its typing pause is saved before the app may
    // be stopped.
    if (s != AppLifecycleState.resumed && widget.state.narrow) {
      widget.state.flushAllEdits();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set before the first build of a size, never during one.
    widget.state.narrow =
        MediaQuery.sizeOf(context).width < Tokens.wideBreakpoint;
  }

  /// Narrow Back: the grid or the menu first, then an open item or view (to
  /// Home). False when nothing is left to close (the app may be left).
  bool _back() {
    final state = widget.state;
    if (_gridOpen || _menuOpen) {
      setState(() => _gridOpen = _menuOpen = false);
    } else if (state.activeTab != null) {
      state.activateTab(null);
    } else {
      return false;
    }
    return true;
  }

  /// Shows [t] (null: Home) and closes the menu and the grid.
  void _show(DocTab? t) {
    setState(() => _gridOpen = _menuOpen = false);
    widget.state.activateTab(t);
  }

  bool get _dockOpen => !widget.state.sidebarCollapsed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.openMenu = null;
    widget.state.onNotSaved = null;
    _dock.dispose();
    _peek.dispose();
    super.dispose();
  }

  /// Drives [c] to open or shut: animated, or at once when [animate] is off.
  void _drive(AnimationController c, bool open, Tokens t, bool animate) {
    c.duration = animate ? t.motion.slide : Duration.zero;
    if (!animate) {
      c.value = open ? 1 : 0;
    } else if (open && !c.isForwardOrCompleted) {
      c.forward();
    } else if (!open && c.status != AnimationStatus.reverse && c.value > 0) {
      c.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) {
          final t = tokensOf(context);
          final wide = c.maxWidth >= Tokens.wideBreakpoint;
          final split = c.maxWidth >= Tokens.splitBreakpoint;
          // Only the wide header row has the expand button, so below it a
          // collapsed peek shows again.
          final collapsedPeek = wide && state.hasPeek && state.peekCollapsed;
          final hasDetail = state.hasPeek && !collapsedPeek;
          final animate = !MediaQuery.disableAnimationsOf(context);
          if (state.peekUid != null) _heldPeek = state.peekUid;
          // Crossing the wide breakpoint jumps; only a toggle slides.
          final crossed = _wasWide != null && _wasWide != wide;
          _wasWide = wide;
          // Growing to wide closes a menu or Space sheet left open.
          if (crossed && wide) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            });
          }
          _drive(_dock, wide && _dockOpen, t, animate && wide && !crossed);
          _drive(_peek, hasDetail, t, animate && split);
          return AnimatedBuilder(
            animation: Listenable.merge([_dock, _peek]),
            builder: (context, _) => _layout(
              context,
              c,
              wide: wide,
              split: split,
              collapsedPeek: collapsedPeek,
              hasDetail: hasDetail,
            ),
          );
        },
      ),
    );
  }

  Widget _layout(
    BuildContext context,
    BoxConstraints c, {
    required bool wide,
    required bool split,
    required bool collapsedPeek,
    required bool hasDetail,
  }) {
    final state = widget.state;
    final t = tokensOf(context);
    final curve = t.motion.curve;
    final dockF = curve.transform(_dock.value);
    final peekF = split ? curve.transform(_peek.value) : 1.0;
    // The peek pane stays while it slides shut, with its last note.
    final showDetail = split ? (hasDetail || _peek.value > 0) : hasDetail;
    final showDock = wide && (_dockOpen || _dock.value > 0);
    // Once the slide-out is over the held note is let go.
    if (!hasDetail && _peek.value == 0) _heldPeek = null;
    final peekUid = state.peekUid ?? _heldPeek;
    final mainNote = state.mainItemUid;
    // Narrow has no peek: an item peeked before (on a wide window) opens
    // full screen.
    if (!wide && state.hasPeek) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.state.narrow) widget.state.promote();
      });
    }
    if (wide) _menuOpen = _gridOpen = false;
    final mirror = state.layoutSide == LayoutSide.end;
    state.nav.setLayout(
      rail: wide,
      panel: (wide && _dockOpen) || _menuOpen,
      // Narrow: the page is covered while the menu or grid is open.
      main: wide ? (split || !hasDetail) : !(_menuOpen || _gridOpen),
      peek: hasDetail,
      mirror: mirror,
    );

    Widget homeBoard({bool embedded = false}) => ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        publishBoardNav(state);
        return CollapsibleSection(
          id: 'home-board',
          title: 'Board',
          count: [
            for (final c in state.columns(includeNoStatus: false)) ...c.$2,
          ].length,
          prefs: state.prefs,
          prefKey: 'davdart.home.board.collapsed.v1',
          fill: !embedded,
          headerPadding: EdgeInsets.fromLTRB(
            t.space.lg,
            t.space.md,
            t.space.lg,
            0,
          ),
          child: BoardView(
            state: state,
            includeNoStatus: false,
            keyboard: true,
            embedded: embedded,
          ),
        );
      },
    );

    Widget mainBody() => state.noSpace
        ? FirstRunView(state: state)
        : mainNote != null
        ? DetailView(
            key: const Key('main-note'),
            state: state,
            uid: mainNote,
            // Below wide there is no strip: Back returns home.
            onClose: () => state.activateTab(null),
            full: wide,
          )
        : Column(
            children: [
              ScopeText(state: state),
              if (state.activeTab == null &&
                  MediaQuery.sizeOf(context).width < Tokens.stackBreakpoint)
                // Phone Home: Today and the board scroll as one.
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('home-scroll'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HomeToday(state: state),
                        homeBoard(embedded: true),
                        SizedBox(height: fabInset(context)),
                      ],
                    ),
                  ),
                )
              else if (state.activeTab == null) ...[
                HomeToday(state: state, capStacked: narrowLayout(context)),
                Flexible(child: homeBoard()),
              ] else
                Expanded(
                  child: state.view == ViewMode.board
                      ? BoardView(state: state)
                      : NoteListView(state: state),
                ),
            ],
          );

    Widget main() =>
        AreaMark(nav: state.nav, area: NavArea.main, child: mainBody());

    Widget peekView({bool header = false}) => AreaMark(
      nav: state.nav,
      area: NavArea.peek,
      child: DetailView(
        key: const Key('peek-view'),
        state: state,
        uid: peekUid!,
        onClose: () => state.guarded(() => state.select(null)),
        inHeader: header,
        area: NavArea.peek,
      ),
    );

    // A main note tab is a full page: no search or view switch.
    // Where the peeked note replaces the main area it brings its own
    // toolbar row, level with the side panel's header.
    final showTopBar = !(wide && (mainNote != null || (hasDetail && !split)));
    final Widget body;
    if (split) {
      body = LayoutBuilder(
        builder: (context, bc) {
          final z = t.sizes;
          final hi = detailMaxFor(t, bc.maxWidth);
          final full = detailWidthFor(t, state, bc.maxWidth);
          final divider = Container(
            width: t.borders.hairline,
            color: t.panelBorder,
          );
          final detail = !showDetail
              ? const SizedBox.shrink()
              : _Slide(
                  key: const Key('detail-pane'),
                  width: full * peekF,
                  full: full,
                  mirror: mirror,
                  outerStart: false,
                  child: SizedBox(
                    width: full,
                    child: Stack(
                      children: [
                        // While sliding out the held note is inert: it may
                        // be live elsewhere (promoted to the main area).
                        IgnorePointer(
                          ignoring: !hasDetail,
                          child: ExcludeFocus(
                            excluding: !hasDetail,
                            child: ExcludeSemantics(
                              excluding: !hasDetail,
                              child: peekView(header: true),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: mirror ? null : 0,
                          right: mirror ? 0 : null,
                          child: PaneResizeHandle(
                            key: const Key('detail-handle'),
                            width: full,
                            min: z.detailMin,
                            max: hi,
                            grow: mirror ? 1 : -1,
                            onResize: (w) =>
                                state.setDetailWidth(w, save: false),
                            onEnd: () =>
                                state.setDetailWidth(state.detailWidth),
                            onReset: () => state.setDetailWidth(null),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
          // The top bar belongs to the main section: the peek is its own
          // pane, full height beside it.
          final mainColumn = Column(
            children: [
              if (showTopBar) TopBar(state: state, showMenu: !wide),
              Expanded(
                child: PromoteTarget(state: state, child: main()),
              ),
            ],
          );
          return Row(
            children: [
              if (mirror && showDetail) ...[detail, divider],
              Expanded(child: mainColumn),
              if (!mirror && showDetail) ...[divider, detail],
            ],
          );
        },
      );
    } else if (!wide) {
      body = main();
    } else if (hasDetail) {
      // Wide but not split: the peeked note replaces the main area;
      // Promote and Collapse are on the header's peek tab.
      body = peekView(header: wide);
    } else {
      body = main();
    }

    final narrowBar = !wide && !state.noSpace;
    Widget content = FScaffold(
      childPad: false,
      header: split || !showTopBar
          ? null
          : TopBar(state: state, showMenu: !wide),
      footer: narrowBar
          ? MobileBar(
              state: state,
              menuOpen: _menuOpen,
              onMenu: () => setState(() {
                _gridOpen = false;
                _menuOpen = !_menuOpen;
              }),
              canBack: _gridOpen || _menuOpen || state.activeTab != null,
              onBack: _back,
              onSearch: () {
                state.setSection(Section.search);
                setState(() => _menuOpen = true);
              },
              onGrid: () => setState(() => _gridOpen = true),
              onHome: () => _show(null),
            )
          : null,
      // Narrow: the side menu and the edge strip live in the body, so the top
      // bar and the bottom bar stay visible and usable.
      child: narrowBar
          ? Stack(
              children: [
                Positioned.fill(
                  child: ExcludeFocus(
                    excluding: _menuOpen || _gridOpen,
                    child: ExcludeSemantics(
                      excluding: _menuOpen || _gridOpen,
                      child: body,
                    ),
                  ),
                ),
                if (!_menuOpen && !_gridOpen) ...[
                  // Not over an open item (full screen on narrow, it has its
                  // own actions) and not while the keyboard is up.
                  if (mainNote == null &&
                      !hasDetail &&
                      MediaQuery.viewInsetsOf(context).bottom == 0)
                    Positioned(
                      right: t.space.lg,
                      bottom: t.space.lg,
                      child: AddFab(state: state),
                    ),
                  // The left edge: a short drag or a fling from it opens the
                  // side menu. The horizontal recogniser leaves taps and
                  // vertical scrolls to what is underneath.
                  // It starts past the system back gesture inset, so Android's
                  // back swipe keeps the very edge. Over a task row the strip
                  // wins the drag (it is the upper layer and claims first), so a
                  // swipe from inside it opens the menu and one starting further
                  // right completes the task.
                  Positioned(
                    left: MediaQuery.systemGestureInsetsOf(context).left,
                    top: 0,
                    bottom: 0,
                    width: t.sizes.edgeSwipe,
                    child: GestureDetector(
                      key: const Key('menu-edge'),
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (_) => _edgeDx = 0,
                      onHorizontalDragUpdate: (d) {
                        _edgeDx += d.primaryDelta ?? 0;
                        if (_edgeDx > 16) setState(() => _menuOpen = true);
                      },
                      onHorizontalDragEnd: (d) {
                        if (!_menuOpen && (d.primaryVelocity ?? 0) > 250) {
                          setState(() => _menuOpen = true);
                        }
                      },
                    ),
                  ),
                ],
                if (_menuOpen)
                  Positioned.fill(
                    child: SideMenuPage(
                      state: state,
                      onClose: () => setState(() => _menuOpen = false),
                    ),
                  ),
              ],
            )
          : body,
    );
    if (narrowBar) {
      final base = content;
      content = Stack(
        children: [
          Positioned.fill(
            child: ExcludeFocus(
              excluding: _gridOpen,
              child: ExcludeSemantics(excluding: _gridOpen, child: base),
            ),
          ),
          if (_gridOpen)
            Positioned.fill(
              child: OpenItemsGrid(
                state: state,
                onDone: () => setState(() => _gridOpen = false),
                onOpen: _show,
                host: context,
              ),
            ),
        ],
      );
    }
    if (showDock) {
      // Docked beside the content, on the side facing it: left of it
      // normally, right of it when the rail is on the right.
      final full = sidebarWidthOf(context, state);
      final dock = _Slide(
        key: const Key('dock-pane'),
        width: full * dockF,
        full: full,
        mirror: mirror,
        outerStart: true,
        child: IconTheme(
          data: context.theme.style.iconStyle,
          child: DockedSidebar(state: state),
        ),
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
    // content, the peek's tab above the peek pane, the side panel's
    // width left empty.
    Widget header(BuildContext context, double panelWidth) {
      final dockW = showDock ? sidebarWidthOf(context, state) * dockF : 0.0;
      final contentW = panelWidth - dockW;
      // Beside the list the tab spans the pane; where the note replaces
      // the list (not split) it is a compact tab at the end of the row.
      final detailFull = showDetail
          ? (split
                ? detailWidthFor(t, state, contentW)
                : t.sizes.detailTab.clamp(0.0, contentW))
          : null;
      final detailW = detailFull == null ? null : detailFull * peekF;
      // The peek has a divider (and the strip a neighbour) only when split.
      final peekBeside = split && detailW != null;
      // Clear of the panel's rounded corner where the strip starts at
      // the panel edge, else just the concave corner.
      final edgePad = t.radii.panel + t.radii.tab;
      final strip = Expanded(
        child: PromoteTarget(
          state: state,
          child: TabStrip(
            state: state,
            // Beside a divider (the side panel or the peek) the home
            // tab lines up with it; at the panel's corner it keeps the
            // clearance for the rounded corner.
            // With the rail on the left that is always a divider (the side
            // panel's, or the collapsed rail's, whose panel corner is square).
            flushStart: !mirror,
            startPad: !mirror ? 0 : (peekBeside ? t.space.sm : edgePad),
            endPad: !mirror && detailW != null && !peekBeside
                ? t.radii.tab
                : t.space.sm,
          ),
        ),
      );
      final detail = detailW == null
          ? (collapsedPeek
                ? PeekExpandButton(state: state, mirror: mirror)
                : null)
          : _Slide(
              width: detailW,
              full: detailFull!,
              mirror: mirror,
              outerStart: false,
              child: DetailHeader(
                state: state,
                width: detailFull,
                mirror: mirror,
              ),
            );
      // The Collapse control sits outside the pane, in the header row.
      final collapse = peekBeside
          ? _Slide(
              width: t.sizes.tabStrip * peekF,
              full: t.sizes.tabStrip,
              mirror: mirror,
              outerStart: false,
              child: PeekCollapseButton(state: state, mirror: mirror),
            )
          : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mirror) ?detail else SizedBox(width: dockW),
          // Mirrored, the peek's divider column sits between the
          // peek header and the strip, so the home tab starts after it.
          if (mirror && peekBeside) SizedBox(width: t.borders.hairline),
          // The control is between the strip and the pane, on either side.
          if (mirror) ?collapse,
          strip,
          if (!mirror) ?collapse,
          if (mirror) SizedBox(width: dockW) else ?detail,
        ],
      );
    }

    return _LeaveGuard(
      state: state,
      child: PopScope(
        // Narrow Back: the grid or menu, then an open item or view, then
        // Home; only from Home does it leave the app.
        canPop: wide || !(_gridOpen || _menuOpen || state.activeTab != null),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: SafeArea(
          child: wide
              ? CallbackShortcuts(
                  bindings: {
                    const SingleActivator(
                      LogicalKeyboardKey.keyW,
                      control: true,
                    ): state.closeActiveTab,
                    const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
                        state.closeActiveTab,
                  },
                  // Focus so the shortcuts work before anything is clicked.
                  child: Focus(
                    focusNode: state.nav.node,
                    autofocus: true,
                    child: ShellFrame(
                      state: state,
                      showRail: true,
                      header: header,
                      child: content,
                    ),
                  ),
                )
              // Focus so Ctrl/Cmd+K works before anything is clicked.
              : Focus(
                  focusNode: state.nav.node,
                  autofocus: true,
                  child: ShellFrame(
                    state: state,
                    showRail: false,
                    child: content,
                  ),
                ),
        ),
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

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.state, required this.showMenu});
  final AppState state;

  /// The narrow layout: the logo left, the title centred.
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return LayoutBuilder(
      builder: (context, c) => _bar(context, t, c.maxWidth < t.sizes.narrowBar),
    );
  }

  /// Narrow title, centred: a folder's or view's crumbs, else the Space chip
  /// (Home, lists and open items alike).
  Widget _title(Tokens t) {
    if (state.scope != null || state.activeViewName != null) {
      return Center(
        child: ScopeCrumbs(state: state, label: state.activeViewName),
      );
    }
    return SpaceChip(state: state);
  }

  /// Left side of the row: the breadcrumb on Home and view tabs, nothing
  /// where a note fills the main area (it has its own header).
  Widget _lead(Tokens t) {
    // A note filling the main area carries its title in its own header.
    if (state.mainItemUid != null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: ScopeCrumbs(state: state, label: state.activeViewName),
    );
  }

  Widget _bar(BuildContext context, Tokens t, bool narrow) {
    final home = !state.mainIsPage;
    final board = state.view == ViewMode.board;
    Widget toggle(String label, ViewMode mode) => touchBox(
      context,
      FButton(
        variant: state.view == mode
            ? FButtonVariant.secondary
            : FButtonVariant.outline,
        size: FButtonSizeVariant.xs,
        mainAxisSize: MainAxisSize.min,
        selected: state.view == mode,
        onPress: () => state.setView(mode),
        child: Text(label),
      ),
    );
    return PaneHeaderRow(
      key: const Key('top-bar'),
      children: [
        // Narrow: the plain app logo (the menu toggle is in the bottom bar).
        if (showMenu)
          SizedBox(
            key: const Key('top-logo'),
            width: t.sizes.touchTarget,
            height: t.sizes.touchTarget,
            child: Center(child: LogoMark(extent: t.icons.lg)),
          ),
        SizedBox(width: t.space.xs),
        Expanded(child: showMenu ? _title(t) : _lead(t)),
        SizedBox(width: t.space.md),
        if (state.loading)
          Padding(
            padding: EdgeInsets.only(right: t.space.md),
            child: SizedBox(
              width: t.sizes.spinner,
              height: t.sizes.spinner,
              child: const FCircularProgress(),
            ),
          ),
        if (home) ScopeActions(state: state, overflow: narrow),
        if (state.activeTab == null || (showMenu && state.mainIsPage))
          const SizedBox.shrink()
        else if (!narrow) ...[
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
    );
  }
}
