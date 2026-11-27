import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/space_catalog.dart' show SpaceCatalog;
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
    title: 'New Space',
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

/// Renames Space [id] (default: the open one) in place, never switching.
Future<void> showRenameSpaceDialog(
  BuildContext context,
  AppState state, {
  String? id,
  String? currentName,
}) {
  final name = TextEditingController(
    text: id == null ? state.currentSpaceName ?? '' : currentName ?? '',
  );
  String? error;
  void Function(void Function())? setError;
  Future<void> submit(BuildContext ctx) async {
    final err = await state.renameSpace(name.text, id: id);
    if (!ctx.mounted) return;
    if (err == null) {
      Navigator.of(ctx).pop();
    } else {
      setError?.call(() => error = err);
    }
  }

  return showAppDialog(
    context,
    title: 'Rename Space',
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
  final name = state.currentSpaceName ?? 'this Space';
  final unsynced = await state.unsyncedInCurrent();
  if (!context.mounted) return;
  final base = state.currentOnServer
      ? 'This removes only this device\'s copy of the Space. Notes on the '
            'server are never deleted, and Refresh Spaces brings the Space '
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

/// Deletes the open account Space's collection from the server for everyone.
/// Needs the exact server name typed, shows the item count and offers a
/// backup (an ICS snapshot: saved on a device, a download on the web).
Future<void> showDeleteFromServerDialog(
  BuildContext context,
  AppState state,
) async {
  final ({String name, int items}) info;
  try {
    info = await state.serverCollectionOfCurrent();
  } catch (e) {
    if (!context.mounted) return;
    return showAppDialog(
      context,
      title: 'Cannot delete from server',
      content: Text('$e', key: const Key('server-delete-error')),
      actions: [const CancelButton(label: 'Close')],
    );
  }
  if (!context.mounted) return;
  final typed = TextEditingController();
  var backup = true;
  var busy = false;
  String? error;
  return showAppDialog(
    context,
    title: 'Delete "${info.name}" from the server?',
    content: StatefulBuilder(
      builder: (ctx, setLocal) {
        final match = typed.text == info.name;
        Future<void> submit() async {
          if (!match || busy) return;
          setLocal(() {
            busy = true;
            error = null;
          });
          final err = await state.deleteCurrentFromServer(
            confirmName: typed.text,
            keepBackup: backup,
          );
          if (!ctx.mounted) return;
          if (err == null) {
            Navigator.of(ctx).pop();
          } else {
            setLocal(() {
              busy = false;
              error = err;
            });
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokensOf(ctx).space.lg,
          children: [
            Text(
              'This removes the Space from the server for everyone who uses '
              'it, with ${info.items} item${info.items == 1 ? '' : 's'}. '
              'It cannot be undone.',
              key: const Key('server-delete-text'),
            ),
            if (info.items > 0)
              FCheckbox(
                key: const Key('server-delete-backup'),
                value: backup,
                onChange: (v) => setLocal(() => backup = v),
                label: Text(
                  'Save a backup first (${SpaceCatalog.backupWhere})',
                ),
              ),
            if (info.items > 0 && backup && SpaceCatalog.backupNote.isNotEmpty)
              Text(
                SpaceCatalog.backupNote,
                key: const Key('server-delete-backup-note'),
                style: tokensOf(ctx).type.captionStyle,
              ),
            if (info.items > 0 && !backup)
              Text(
                'Warning: without a backup the items are gone for good.',
                key: const Key('server-delete-nobackup'),
                style: tokensOf(ctx).type.captionStyle,
              ),
            field(
              key: const Key('server-delete-name'),
              controller: typed,
              autofocus: true,
              label: 'Type "${info.name}" to confirm',
              error: error,
              onChange: (_) => setLocal(() {}),
              onSubmit: (_) => submit(),
            ),
            // Enabled only once the typed name matches exactly.
            FButton(
              key: const Key('server-delete-go'),
              mainAxisSize: MainAxisSize.min,
              onPress: match && !busy ? submit : null,
              child: Text(busy ? 'Deleting…' : 'Delete from server'),
            ),
          ],
        );
      },
    ),
    actions: [const CancelButton()],
  );
}
