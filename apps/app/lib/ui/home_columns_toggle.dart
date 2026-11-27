import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'count_badge.dart';
import 'parts.dart';
import 'theme.dart';

/// Header icon on the Home Board (wide only): a menu of the status
/// columns to show, saved per Space. A badge counts hidden ones.
class HomeColumnsToggle extends StatelessWidget {
  const HomeColumnsToggle({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final (cols, _, hidden) = state.homeColumnChoices();
    if (cols.length < 2) return const SizedBox.shrink();
    return FPopoverMenu(
      menuAnchor: Alignment.topRight,
      childAnchor: Alignment.bottomRight,
      menuBuilder: (ctx, controller, _) => [
        FItemGroup(
          children: [
            for (final c in cols)
              FItem(
                key: Key('home-col-$c'),
                title: Text(c),
                suffix: hidden.contains(c)
                    ? null
                    : Icon(FLucideIcons.check, size: t.icons.md),
                onPress: () => state.toggleHomeCol(c),
              ),
          ],
        ),
      ],
      builder: (ctx, controller, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          IconAction(
            key: const Key('home-cols'),
            compact: true,
            icon: FLucideIcons.columns3,
            tooltip: 'Columns',
            onPress: controller.toggle,
          ),
          if (hidden.isNotEmpty)
            Positioned(
              right: 0,
              top: 0,
              child: IgnorePointer(
                child: CountBadge(
                  hidden.length,
                  key: const Key('home-cols-badge'),
                  tone: BadgeTone.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
