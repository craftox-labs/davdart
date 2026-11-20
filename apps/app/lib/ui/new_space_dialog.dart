import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Names a new local Space and opens it.
Future<void> showNewSpaceDialog(BuildContext context, AppState state) {
  final name = TextEditingController();
  var onServer = state.accountUser != null;
  void submit(BuildContext ctx) {
    if (name.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.createSpace(name.text, onServer: onServer);
  }

  return showAppDialog(
    context,
    title: 'New space',
    content: StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: tokensOf(ctx).space.lg,
        children: [
          field(
            key: const Key('space-name'),
            controller: name,
            autofocus: true,
            hint: 'Name, for example Inbox',
            onSubmit: (_) => submit(ctx),
          ),
          if (state.accountUser != null)
            FCheckbox(
              key: const Key('space-on-server'),
              value: onServer,
              onChange: (v) => setLocal(() => onServer = v),
              label: const Text('Create on the server and sync'),
            ),
        ],
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Create', key: const Key('space-create'), onPress: submit),
    ],
  );
}

/// Renames the open Space.
Future<void> showRenameSpaceDialog(BuildContext context, AppState state) {
  final name = TextEditingController(text: state.currentSpaceName ?? '');
  String? error;
  void Function(void Function())? setError;
  Future<void> submit(BuildContext ctx) async {
    final err = await state.renameSpace(name.text);
    if (!ctx.mounted) return;
    if (err == null) {
      Navigator.of(ctx).pop();
    } else {
      setError?.call(() => error = err);
    }
  }

  return showAppDialog(
    context,
    title: 'Rename space',
    content: StatefulBuilder(
      builder: (ctx, setState) {
        setError = setState;
        return field(
          key: const Key('space-rename-name'),
          controller: name,
          autofocus: true,
          error: error,
          onSubmit: (_) => submit(ctx),
        );
      },
    ),
    actions: [
      const CancelButton(),
      ActionButton('Rename', key: const Key('space-rename'), onPress: submit),
    ],
  );
}

/// Confirms deleting the open Space from this device. Says plainly that
/// server notes are never deleted, and warns about changes not synced yet.
Future<void> showDeleteSpaceDialog(BuildContext context, AppState state) async {
  final name = state.currentSpaceName ?? 'this space';
  final unsynced = await state.unsyncedInCurrent();
  if (!context.mounted) return;
  final base = state.currentOnServer
      ? 'This removes only this device\'s copy of the space. Notes on the '
            'server are never deleted, and Refresh spaces brings the space '
            'back.'
      : 'This removes only this device\'s copy: its notes and saved views '
            'are deleted from this device. Notes on a server, if it was '
            'connected to one, are never deleted.';
  final warn = unsynced == 0
      ? ''
      : state.currentOnServer
      ? ' Warning: $unsynced note${unsynced == 1 ? ' has' : 's have'} changes '
            'that are not saved or not synced to the server yet; they will '
            'be lost.'
      : ' Warning: $unsynced note${unsynced == 1 ? ' has' : 's have'} '
            'unsaved edits that will be lost.';
  return showAppDialog(
    context,
    title: 'Delete $name?',
    content: Text('$base$warn', key: const Key('space-delete-text')),
    actions: [
      const CancelButton(),
      ActionButton(
        'Delete',
        key: const Key('space-delete'),
        onPress: (ctx) {
          Navigator.of(ctx).pop();
          state.deleteSpace();
        },
      ),
    ],
  );
}
