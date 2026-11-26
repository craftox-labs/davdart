import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'shell_frame.dart' show JoinedTab;
import 'theme.dart';

/// The narrow top bar's one joined pill: an icon and a label, on the bar's
/// bottom edge. The Space and the current page both use it, so the bar keeps
/// one look; only the icon and label change. A tap opens the Projects picker.
class TopTabPill extends StatelessWidget {
  const TopTabPill({
    super.key,
    required this.icon,
    required this.label,
    required this.onPress,
    this.labelKey,
  });

  final IconData icon;
  final String label;

  /// Key for the label text (defaults to `top-title`).
  final Key? labelKey;

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final style = t.type.captionStyle.copyWith(color: t.fg);
    // Panel tone, flared concave bottom corners, flush on the top bar's
    // bottom edge (over its hairline).
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
            onPress: onPress,
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
                      Icon(icon, size: t.icons.lg, color: t.fg),
                      Flexible(
                        child: Text(
                          label,
                          key: labelKey ?? const Key('top-title'),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: style,
                        ),
                      ),
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
