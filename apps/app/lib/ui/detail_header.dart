import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'tab_strip.dart';
import 'theme.dart';

/// The detail pane's header, in the shell's header row above the pane: a row
/// of tabs (one now: the selected note, closable like a strip tab, with its
/// dirty dot) and, at the pane's outer edge, the Maximise / Minimise control.
/// The control keeps its place in both states because the header spans the
/// pane's outer edge either way. With [mirror] (the pane is on the left) the
/// order is reversed. [startPad] clears the panel's rounded corner when the
/// tabs start at the panel edge (maximised, side panel collapsed).
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.state,
    required this.width,
    required this.mirror,
    this.startPad = 0,
  });
  final AppState state;
  final double width;
  final bool mirror;
  final double startPad;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final note = state.selected;
    final title = note == null || note.summary.isEmpty
        ? 'Details'
        : note.summary;
    final draft = state.draft;
    final tab = Expanded(
      child: ListenableBuilder(
        // The dirty dot follows the open edit, which notifies on its own.
        listenable: Listenable.merge([state, ?draft]),
        builder: (context, _) => Padding(
          // Room for the tab's concave corner on its open side.
          padding: EdgeInsets.only(
            left: mirror ? 0 : math.max(t.radii.tab, startPad),
            right: mirror ? math.max(t.radii.tab, startPad) : 0,
          ),
          child: LayoutBuilder(
            builder: (context, c) => Align(
              alignment: mirror ? Alignment.topRight : Alignment.topLeft,
              child: TabItem(
                key: const Key('detail-tab'),
                width: math.min(c.maxWidth, t.sizes.tabMax),
                icon: note != null && AppState.isFolder(note)
                    ? FLucideIcons.folder
                    : FLucideIcons.fileText,
                title: title,
                active: true,
                dirty: state.dirty,
                onPress: () {},
                onClose: () => state.guarded(() => state.select(null)),
              ),
            ),
          ),
        ),
      ),
    );
    final max = state.maximised;
    final toggle = IconAction(
      key: const Key('pane-size'),
      tooltip: max ? 'Minimise' : 'Maximise',
      icon: max ? FLucideIcons.minimize : FLucideIcons.maximize,
      onPress: max ? () => state.guarded(state.minimise) : state.maximise,
    );
    return SizedBox(
      key: const Key('detail-header'),
      width: width,
      height: t.sizes.tabStrip + t.borders.hairline,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mirror ? [toggle, tab] : [tab, toggle],
      ),
    );
  }
}
