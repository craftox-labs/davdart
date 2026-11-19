import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';

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
    width: 360,
    content: Builder(
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 0
                ? 'The note goes to the top level of the space you pick.'
                : 'The note and the $count under it go to the top level of '
                      'the space you pick.',
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Moved notes get new ids and leave their earlier versions '
            'behind. A server space syncs them when you open it.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final s in others)
            FItem(
              key: Key('move-to-${s.id}'),
              prefix: Icon(
                s.onServer ? FLucideIcons.cloud : FLucideIcons.folder,
                size: 18,
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
