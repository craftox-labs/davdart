import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'content_grid.dart';
import 'parts.dart';
import 'theme.dart';

/// The bar under the Home switch on Board and Tasks: a tag filter (clearable)
/// and a column toggle. Both are saved per Space and per view.
class HomeBoardBar extends StatelessWidget {
  const HomeBoardBar({super.key, required this.state, required this.focus});
  final AppState state;
  final HomeFocus focus;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final tasks = focus == HomeFocus.tasks;
    final tag = state.homeTag(focus);
    final tags = tasks ? state.taskTags : state.tags;
    final (cols, _, hidden) = state.homeColumnChoices(focus);
    if (tags.isEmpty && tag == null && cols.length < 2) {
      return const SizedBox.shrink();
    }
    Widget menu({
      required String key,
      required String label,
      required List<FItem> Function(VoidCallback close) items,
    }) => FPopoverMenu(
      menuAnchor: Alignment.topLeft,
      childAnchor: Alignment.bottomLeft,
      menuBuilder: (ctx, controller, _) => [
        FItemGroup(children: items(controller.hide)),
      ],
      builder: (ctx, controller, _) => FButton(
        key: Key(key),
        variant: FButtonVariant.outline,
        size: FButtonSizeVariant.sm,
        onPress: controller.toggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
    return ContentCap(
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, 0),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: t.space.md,
          runSpacing: t.space.sm,
          children: [
            if (tags.isNotEmpty || tag != null) ...[
              menu(
                key: 'home-tag-filter',
                label: tag == null ? 'Tag' : 'Tag: $tag',
                items: (close) => [
                  for (final g in {...tags, ?tag})
                    FItem(
                      key: Key('home-tag-$g'),
                      title: Text(g),
                      suffix: g == tag
                          ? Icon(FLucideIcons.check, size: t.icons.md)
                          : null,
                      onPress: () {
                        close();
                        state.setHomeTag(focus, g);
                      },
                    ),
                ],
              ),
              if (tag != null)
                IconAction(
                  key: const Key('home-tag-clear'),
                  compact: true,
                  icon: FLucideIcons.x,
                  tooltip: 'Clear tag filter',
                  onPress: () => state.setHomeTag(focus, null),
                ),
            ],
            if (cols.length > 1)
              menu(
                key: 'home-cols',
                label: hidden.isEmpty
                    ? 'Columns'
                    : 'Columns (${cols.length - hidden.length}/${cols.length})',
                items: (_) => [
                  for (final c in cols)
                    FItem(
                      key: Key('home-col-$c'),
                      title: Text(c),
                      suffix: hidden.contains(c)
                          ? null
                          : Icon(FLucideIcons.check, size: t.icons.md),
                      onPress: () => state.toggleHomeCol(focus, c),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
