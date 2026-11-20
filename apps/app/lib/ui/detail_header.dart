import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import '../state/note_drag.dart';
import 'note_menu.dart';
import 'parts.dart';
import 'tab_strip.dart';
import 'theme.dart';

/// The peek pane's header, in the shell's header row above the pane: its one
/// tab (the peeked note, closable like a strip tab, with its dirty dot; drag
/// it onto the main area to promote it) and, at the pane's outer edge, the
/// Promote ("Open in main area") and Collapse controls. With [mirror] (the
/// pane is on the left) the order is reversed.
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
                      // The pane's divider side lines up with the divider.
                      flushStart: !mirror,
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
    final promote = IconAction(
      key: const Key('peek-promote'),
      tooltip: 'Open in main area',
      icon: FLucideIcons.squareArrowOutUpRight,
      onPress: uid == null ? null : () => state.promote(uid),
    );
    final collapse = IconAction(
      key: const Key('peek-collapse'),
      tooltip: 'Collapse',
      icon: mirror ? FLucideIcons.panelLeftClose : FLucideIcons.panelRightClose,
      onPress: () => state.setPeekCollapsed(true),
    );
    return SizedBox(
      key: const Key('detail-header'),
      width: width,
      height: t.sizes.tabStrip + t.borders.hairline,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mirror ? [collapse, promote, tab] : [tab, promote, collapse],
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
  Widget build(BuildContext context) => IconAction(
    key: const Key('peek-expand'),
    tooltip: 'Show ${state.peek?.summary ?? 'note'}',
    icon: mirror ? FLucideIcons.panelLeftOpen : FLucideIcons.panelRightOpen,
    onPress: () => state.setPeekCollapsed(false),
  );
}
