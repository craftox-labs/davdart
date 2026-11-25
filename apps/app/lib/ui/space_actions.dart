import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/space_catalog.dart';
import '../state/app_state.dart';
import 'parts.dart';

/// Sync state line of a Space in the Spaces panel.
String spaceSyncLabel(AppState state, SpaceInfo sp) =>
    sp.id == state.currentSpaceId && state.syncing
    ? 'Syncing…'
    : sp.onServer
    ? 'Synced with the server'
    : 'On this device only';

/// Moves note [uid] (with everything under it) to Space [sp]. A folder is
/// confirmed first; a failure or the success is shown as a toast. [hide] runs
/// as the move starts, for a caller that closes itself (the rail's drop
/// target has nothing to close and passes null).
Future<void> moveNoteToSpace(
  BuildContext context,
  AppState state,
  VoidCallback? hide,
  String uid,
  SpaceInfo sp,
) async {
  final node = state.tree.find(uid);
  if (node == null) {
    final task = state.taskById(uid);
    final event = task == null ? state.eventById(uid) : null;
    final name = task?.summary ?? event?.summary;
    if (name == null) return;
    hide?.call();
    final n = await state.moveToSpace(uid, sp.id);
    if (!context.mounted) return;
    showFToast(
      context: context,
      title: Text(
        n == null
            ? (state.error ?? 'Could not move "$name"')
            : n == 1
            ? 'Moved "$name" to "${sp.name}"'
            : 'Moved $n items to "${sp.name}"',
      ),
    );
    return;
  }
  if (node.children.isNotEmpty || AppState.isFolder(node.note)) {
    final ok = await showAppDialog<bool>(
      context,
      title: 'Move folder?',
      content: Text(
        '"${node.note.summary}" and everything in it will move to '
        '"${sp.name}".',
      ),
      actions: [
        const CancelButton(),
        ActionButton(
          'Move',
          key: const Key('space-move-confirm'),
          onPress: (ctx) => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (ok != true) return;
  }
  hide?.call();
  final n = await state.moveToSpace(uid, sp.id);
  if (!context.mounted) return;
  final msg = n == null
      ? (state.error ?? 'Could not move "${node.note.summary}"')
      : 'Moved ${n == 1 ? '"${node.note.summary}"' : '$n notes'} to "${sp.name}"';
  showFToast(context: context, title: Text(msg));
}
