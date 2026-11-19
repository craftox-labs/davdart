import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';

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
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Move "${note.summary}" to…'),
      content: SizedBox(
        width: 360,
        child: Column(
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
              ListTile(
                key: Key('move-to-${s.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  s.onServer ? Icons.cloud_outlined : Icons.folder_outlined,
                  size: 18,
                ),
                title: Text(s.name),
                onTap: () {
                  Navigator.of(ctx).pop();
                  state.moveToSpace(note.uid, s.id);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
