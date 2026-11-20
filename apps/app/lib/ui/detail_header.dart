import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import '../theme/tokens.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'tab_strip.dart';
import 'theme.dart';

/// The peek pane's header, in the shell's header row above the pane: its one
/// tab (the peeked note, closable like a strip tab, with its dirty dot; drag
/// it onto the main area to promote it), with the Collapse control at the
/// pane's left edge, just before the tab, and Promote ("Open in main area")
/// after it. With [mirror] (the pane is on the left, its divider on its
/// right) both controls come first so the tab ends flush at the divider.
/// Every control is a [Sizes.tabStrip] box, centred on the tab strip's line.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.state,
    required this.width,
    required this.mirror,
  });
  final AppState state;
  final double width;
  final bool mirror;

  /// Where the peek tab's content starts, from the pane's left edge: past the
  /// header controls that come first, plus the tab's own padding. The pane's
  /// breadcrumb and title use it as their left inset so all three line up.
  static double inset(Tokens t, bool mirror) =>
      t.sizes.tabStrip * (mirror ? 2 : 1) + t.space.md;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final uid = state.peekUid;
    final note = state.peek;
    final title = note == null || note.summary.isEmpty
        ? 'Details'
        : note.summary;
    final draft = state.draft;
    final tab = Expanded(
      child: ListenableBuilder(
        // The dirty dot follows the open edit, which notifies on its own.
        listenable: Listenable.merge([state, ?draft]),
        builder: (context, _) => Padding(
          padding: EdgeInsets.only(left: 0, right: 0),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = math.min(c.maxWidth, t.sizes.tabMax);
              final icon = note != null && AppState.isFolder(note)
                  ? FLucideIcons.folder
                  : FLucideIcons.fileText;
              Widget menu(Widget child) => uid == null
                  ? child
                  : NoteContextMenu(
                      state: state,
                      uid: uid,
                      surface: NoteSurface.peekTab,
                      child: child,
                    );
              return Align(
                alignment: mirror ? Alignment.topRight : Alignment.topLeft,
                child: menu(
                  Draggable<NoteDrag>(
                    key: const Key('detail-drag'),
                    data: uid == null
                        ? null
                        : NoteDrag(uid, NoteDragSource.peek),
                    maxSimultaneousDrags: uid == null ? 0 : 1,
                    feedback: DefaultTextStyle(
                      style: t.type.captionStyle.copyWith(color: t.fg),
                      child: Container(
                        width: w,
                        height: t.sizes.tabStrip,
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.symmetric(horizontal: t.space.md),
                        decoration: BoxDecoration(
                          color: t.panel,
                          border: Border.all(color: t.divider),
                          borderRadius: BorderRadius.circular(t.radii.small),
                        ),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    child: TabItem(
                      key: const Key('detail-tab'),
                      // Mirrored, the tab's divider side lines up with the divider.
                      flushEnd: mirror,
                      width: w,
                      icon: icon,
                      title: title,
                      active: true,
                      dirty: state.dirty,
                      // A double click promotes the peek to the main area.
                      onPress: () => state.clickOpenNote(uid ?? ''),
                      onClose: () => state.guarded(() => state.select(null)),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final promote = HeaderControl(
      child: IconAction(
        key: const Key('peek-promote'),
        tooltip: 'Open in main area',
        icon: FLucideIcons.squareArrowOutUpRight,
        onPress: uid == null ? null : () => state.promote(uid),
      ),
    );
    final collapse = HeaderControl(
      child: IconAction(
        key: const Key('peek-collapse'),
        tooltip: 'Collapse',
        icon: FLucideIcons.panelRightClose,
        onPress: () => state.setPeekCollapsed(true),
      ),
    );
    return SizedBox(
      key: const Key('detail-header'),
      width: width,
      height: t.sizes.tabStrip + t.borders.hairline,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mirror ? [collapse, promote, tab] : [collapse, tab, promote],
      ),
    );
  }
}

/// The header cell shown at the outer edge while the peek is collapsed: one
/// button that brings the parked note back at peek width.
class PeekExpandButton extends StatelessWidget {
  const PeekExpandButton({
    super.key,
    required this.state,
    required this.mirror,
  });
  final AppState state;
  final bool mirror;

  @override
  Widget build(BuildContext context) => HeaderControl(
    child: IconAction(
      key: const Key('peek-expand'),
      tooltip: 'Show ${state.peek?.summary ?? 'note'}',
      icon: mirror ? FLucideIcons.panelLeftOpen : FLucideIcons.panelRightOpen,
      onPress: () => state.setPeekCollapsed(false),
    ),
  );
}

/// A control in the shell's header row: a [Sizes.tabStrip] square with its
/// child centred, so it sits on the same centreline as the tabs and the "+".
class HeaderControl extends StatelessWidget {
  const HeaderControl({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return SizedBox(
      width: t.sizes.tabStrip,
      height: t.sizes.tabStrip,
      child: Center(child: child),
    );
  }
}
