import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';
import 'overflow_tip.dart';
import 'theme.dart';

/// A tags drawer pinned to the bottom of a left panel section: [body] (the
/// scrolling list) fills the space above, a hairline rule and the drawer sit
/// below it. Collapsed it is one 'Tags (n)' row with a chevron; expanded the
/// chips wrap and the drawer grows upward (the body shrinks), capped at
/// [maxFraction] of the panel height with its own scroll. With no [tags] only
/// [body] shows.
///
/// Keys (with [keyPrefix], default `tags`): `<prefix>-drawer` the drawer,
/// `<prefix>-toggle` the header row, `<prefix>-chips` the scroll area. Chips
/// are `tag-<tag>`. [onSelect] gets the tapped tag, or null when the selected
/// one is tapped again. [menuBuilder] wraps a chip, for a context menu.
class PanelTagsDrawer extends StatelessWidget {
  const PanelTagsDrawer({
    super.key,
    required this.body,
    required this.tags,
    required this.selected,
    required this.onSelect,
    required this.expanded,
    required this.onExpandedChange,
    this.menuBuilder,
    this.keyPrefix = 'tags',
    this.maxFraction = 0.4,
  });

  final Widget body;
  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final Widget Function(String tag, Widget chip)? menuBuilder;
  final bool expanded;
  final ValueChanged<bool> onExpandedChange;
  final String keyPrefix;
  final double maxFraction;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final cap = c.hasBoundedHeight ? c.maxHeight * maxFraction : 200.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: body),
            if (tags.isNotEmpty)
              Container(
                key: Key('$keyPrefix-drawer'),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: t.divider,
                      width: t.borders.hairline,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FTappable(
                      key: Key('$keyPrefix-toggle'),
                      semanticsLabel: 'Tags (${tags.length})',
                      behavior: HitTestBehavior.opaque,
                      onPress: () => onExpandedChange(!expanded),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: t.space.lg,
                          vertical: t.space.md,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Tags (${tags.length})',
                                style: t.type.labelStyle.copyWith(
                                  color: t.muted,
                                ),
                              ),
                            ),
                            Icon(
                              expanded
                                  ? FLucideIcons.chevronDown
                                  : FLucideIcons.chevronUp,
                              size: t.icons.md,
                              color: t.muted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (expanded)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: cap),
                        child: LayoutBuilder(
                          builder: (context, box) => SingleChildScrollView(
                            key: Key('$keyPrefix-chips'),
                            padding: EdgeInsets.fromLTRB(
                              t.space.lg,
                              0,
                              t.space.lg,
                              t.space.md,
                            ),
                            child: Wrap(
                              spacing: t.space.sm,
                              runSpacing: t.space.sm,
                              children: [
                                for (final tag in tags) _chip(tag, box, t),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _chip(String tag, BoxConstraints box, Tokens t) {
    final on = selected == tag;
    final maxW = (box.maxWidth - 2 * t.space.lg).clamp(60.0, double.infinity);
    final chip = FTappable(
      key: Key('tag-$tag'),
      semanticsLabel: 'Tag $tag',
      onPress: () => onSelect(on ? null : tag),
      child: FBadge(
        variant: on ? FBadgeVariant.secondary : FBadgeVariant.outline,
        child: ConstrainedBox(
          // Leaves room for the badge's own padding.
          constraints: BoxConstraints(maxWidth: maxW - 2 * t.space.md),
          child: OverflowTip(tag),
        ),
      ),
    );
    return menuBuilder == null ? chip : menuBuilder!(tag, chip);
  }
}
