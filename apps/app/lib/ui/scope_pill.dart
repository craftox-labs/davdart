import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'shell_frame.dart';
import 'theme.dart';

/// The narrow top bar's one joined tab: the open Space and the project the
/// scope sits in, at any depth below it ("Space › Project": the Space becomes
/// its icon); a loose folder or the Space root keeps the Space name.
/// Tapping it opens the Projects panel, the scope picker (the sheet it used to
/// open is gone). The pill looks the same on every screen, so the bar never
/// swaps its title.
class ScopePill extends StatelessWidget {
  const ScopePill({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final space = state.currentSpaceName ?? 'Spaces';
    final scope = state.scopeUid;
    final p = scope == null ? null : state.projectIndex.projectOf(scope);
    final project = p == null
        ? null
        : (p.summary.isEmpty ? 'Untitled' : p.summary);
    final label = project == null ? space : '$space › $project';
    final style = t.type.captionStyle.copyWith(color: t.fg);
    // The active desktop header tab: panel tone, flared concave bottom
    // corners, flush on the top bar's bottom edge (over its hairline).
    final flare = t.radii.tab;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(0, t.borders.hairline),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: flare),
          child: FTappable(
            key: const Key('space-chip'),
            semanticsLabel: label,
            behavior: HitTestBehavior.opaque,
            onPress: () => state.openPanel(Section.projects),
            // The tab takes the whole header height (it is its own hit box)
            // and its content sits on the logo's centre line.
            child: Align(
              alignment: Alignment.bottomCenter,
              child: JoinedTab(
                active: true,
                height: t.sizes.paneHeader,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: t.space.sm,
                    children: [
                      // Same size as the logo.
                      Icon(spacesIcon, size: t.icons.lg, color: t.fg),
                      if (project == null)
                        Flexible(
                          child: Text(
                            space,
                            key: const Key('scope-pill-space'),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: style,
                          ),
                        )
                      else ...[
                        Text('›', style: style.copyWith(color: t.muted)),
                        Flexible(
                          child: Text(
                            project,
                            key: const Key('scope-pill-project'),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: style,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
