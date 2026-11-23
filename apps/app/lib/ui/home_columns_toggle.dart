import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Header icon on Home Board and Tasks (wide only): a menu of the status
/// columns to show, saved per Space and view. A badge counts hidden ones.
class HomeColumnsToggle extends StatelessWidget {
  const HomeColumnsToggle({
    super.key,
    required this.state,
    required this.focus,
  });
  final AppState state;
  final HomeFocus focus;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final (cols, _, hidden) = state.homeColumnChoices(focus);
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
                onPress: () => state.toggleHomeCol(focus, c),
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
                child: Container(
                  key: const Key('home-cols-badge'),
                  padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(t.space.md),
                  ),
                  child: Text(
                    '${hidden.length}',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      color: t.onAccent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
