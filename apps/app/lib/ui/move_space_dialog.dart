import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Moves a note (and the notes under it) to another Space.
Future<void> showMoveSpaceDialog(
  BuildContext context,
  AppState state,
  Note note,
) {
  final others = [
    for (final s in state.spaces)
      if (s.id != state.currentSpaceId) s,
  ];
  final count = state.tree.descendants(note.uid).length;
  return showAppDialog(
    context,
    title: 'Move "${note.summary}" to…',
    width: tokensOf(context).sizes.dialogSm,
    content: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 0
                ? 'The note goes to the top level of the Space you pick.'
                : 'The note and the $count under it go to the top level of '
                      'the Space you pick.',
            style: tokensOf(ctx).type.captionStyle,
          ),
          SizedBox(height: tokensOf(ctx).space.xs),
          Text(
            'Moved notes get new ids and leave their earlier versions '
            'behind. A server Space syncs them when you open it.',
            style: tokensOf(ctx).type.captionStyle,
          ),
          SizedBox(height: tokensOf(ctx).space.md),
          for (final s in others)
            FItem(
              key: Key('move-to-${s.id}'),
              prefix: Icon(
                s.onServer ? FLucideIcons.cloud : FLucideIcons.folder,
                size: tokensOf(ctx).icons.lg,
              ),
              title: Text(s.name),
              onPress: () {
                Navigator.of(ctx).pop();
                state.moveToSpace(note.uid, s.id);
              },
            ),
        ],
      ),
    ),
    actions: [const CancelButton()],
  );
}
