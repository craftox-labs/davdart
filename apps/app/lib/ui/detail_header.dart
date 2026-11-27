import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import 'event_menu.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'tab_strip.dart';
import 'task_menu.dart';
import 'theme.dart';

/// The peek pane's header, in the shell's header row above the pane: its one
/// tab (the peeked note, closable like a strip tab, with its dirty dot; drag
/// it onto the main area to promote it) and Promote ("Open in main area")
/// after it. With [mirror] (the pane is on the left, its divider on its
/// right) Promote comes first so the tab ends flush at the divider. The
/// Collapse control is not in here: it sits outside the pane ([PeekCollapseButton]).
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

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final uid = state.peekUid;
    final note = state.peek;
    final task = state.peekTask;
    final event = state.peekEvent;
    final name = note?.summary ?? task?.summary ?? event?.summary ?? '';
    final title = name.isEmpty ? 'Details' : name;
    final draft = state.draft;
    final taskDraft = uid == null ? null : state.taskDraftFor(uid);
    final eventDraft = uid == null ? null : state.eventDraftFor(uid);
    final tab = Expanded(
      child: ListenableBuilder(
        // The dirty dot follows the open edit, which notifies on its own.
        listenable: Listenable.merge([state, ?draft, ?taskDraft, ?eventDraft]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) {
            final w = math.min(c.maxWidth, t.sizes.tabMax);
            final icon = task != null
                ? FLucideIcons.listChecks
                : event != null
                ? FLucideIcons.calendar
                : note != null && AppState.isFolder(note)
                ? FLucideIcons.folder
                : FLucideIcons.fileText;
            Widget menu(Widget child) => uid == null
                ? child
                : task != null
                ? TaskContextMenu(
                    state: state,
                    uid: uid,
                    surface: NoteSurface.peekTab,
                    child: child,
                  )
                : event != null
                ? EventContextMenu(
                    state: state,
                    uid: uid,
                    surface: NoteSurface.peekTab,
                    child: child,
                  )
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
                  data: uid == null ? null : NoteDrag(uid, NoteDragSource.peek),
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
                    // The pane's divider side lines up with the divider.
                    flushStart: !mirror,
                    flushEnd: mirror,
                    width: w,
                    icon: icon,
                    title: title,
                    active: true,
                    dirty:
                        state.dirty ||
                        (uid != null &&
                            (state.dirtyTaskFor(uid) ||
                                state.dirtyEventFor(uid))),
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
    );
    final promote = HeaderControl(
      child: IconAction(
        key: const Key('peek-promote'),
        tooltip: 'Open in main area',
        icon: FLucideIcons.squareArrowOutUpRight,
        onPress: uid == null ? null : () => state.promote(uid),
      ),
    );
    return SizedBox(
      key: const Key('detail-header'),
      width: width,
      height: t.sizes.tabStripLine,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mirror ? [promote, tab] : [tab, promote],
      ),
    );
  }
}

/// The Collapse control, in the header row just outside the peek pane (left
/// of it, or right of it when [mirror]ed): a [HeaderControl] square.
class PeekCollapseButton extends StatelessWidget {
  const PeekCollapseButton({
    super.key,
    required this.state,
    required this.mirror,
  });
  final AppState state;
  final bool mirror;

  @override
  Widget build(BuildContext context) => HeaderControl(
    child: IconAction(
      key: const Key('peek-collapse'),
      tooltip: 'Collapse',
      icon: mirror ? FLucideIcons.panelLeftClose : FLucideIcons.panelRightClose,
      onPress: () => state.setPeekCollapsed(true),
    ),
  );
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
      tooltip:
          'Show ${state.peek?.summary ?? state.peekTask?.summary ?? state.peekEvent?.summary ?? 'note'}',
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
