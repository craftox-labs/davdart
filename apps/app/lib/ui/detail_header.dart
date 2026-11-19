import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'shell_frame.dart';
import 'theme.dart';

/// The detail pane's header, in the shell's header row above the pane: its
/// tab (the open note's title, a [JoinedTab] flush on the panel's top edge)
/// and, at the far end, the pane's Expand (open as a full page) and Close
/// (deselect the note) actions. A row of tabs here could later hold several
/// pane tabs. With [mirror] (the pane is on the left) the order is reversed.
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
    final note = state.selected;
    final title = note == null || note.summary.isEmpty
        ? 'Details'
        : note.summary;
    final tab = Expanded(
      child: Padding(
        // Room for the tab's concave corner on its open side.
        padding: EdgeInsets.only(
          left: mirror ? 0 : t.radii.tab,
          right: mirror ? t.radii.tab : 0,
        ),
        child: Align(
          alignment: mirror ? Alignment.topRight : Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: t.sizes.tabMax),
            child: JoinedTab(
              key: const Key('detail-tab'),
              active: true,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.md),
                child: Row(
                  spacing: t.space.sm,
                  children: [
                    Icon(
                      note != null && AppState.isFolder(note)
                          ? FLucideIcons.folder
                          : FLucideIcons.fileText,
                      size: t.icons.sm,
                      color: t.fg,
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.type.captionStyle.copyWith(color: t.fg),
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
    final actions = [
      IconAction(
        key: const Key('expand-note'),
        tooltip: 'Open full page',
        icon: FLucideIcons.maximize2,
        onPress: state.openFullPage,
      ),
      IconAction(
        key: const Key('detail-close'),
        tooltip: 'Close',
        icon: FLucideIcons.x,
        onPress: () => state.guarded(() => state.select(null)),
      ),
    ];
    return SizedBox(
      key: const Key('detail-header'),
      width: width,
      height: t.sizes.tabStrip + t.borders.hairline,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mirror ? [...actions.reversed, tab] : [tab, ...actions],
      ),
    );
  }
}
