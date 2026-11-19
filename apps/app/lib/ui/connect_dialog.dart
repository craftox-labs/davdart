import 'package:material_ui/material_ui.dart';

import '../data/note_source.dart';
import '../state/app_state.dart';

/// Connects the local Space to a CalDAV collection through the board
/// server's /dav/ proxy. The first sync sends every local note and merges by
/// UID with what the server holds.
Future<void> showConnectDialog(BuildContext context, AppState state) {
  final path = TextEditingController();
  final user = TextEditingController();
  final password = TextEditingController();
  var replace = false;
  List<FoundCollection>? found;
  String? finding; // null idle, '' searching, else the error
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        void submit() {
          if (path.text.trim().isEmpty || user.text.trim().isEmpty) return;
          Navigator.of(ctx).pop();
          state.connect(
            path.text,
            user.text,
            password.text,
            replaceLocal: replace,
          );
        }

        Future<void> find() async {
          if (user.text.trim().isEmpty) {
            setLocal(() => finding = 'Enter the user first');
            return;
          }
          setLocal(() => finding = '');
          try {
            final r = await state.discoverCollections(user.text, password.text);
            setLocal(() {
              found = r;
              finding = null;
            });
          } catch (e) {
            setLocal(() => finding = 'Could not list collections: $e');
          }
        }

        return AlertDialog(
          title: const Text('Connect server'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('connect-user'),
                  controller: user,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'User'),
                ),
                TextField(
                  key: const Key('connect-password'),
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => submit(),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('connect-find'),
                    onPressed: finding == '' ? null : find,
                    child: Text(
                      finding == '' ? 'Looking…' : 'Find collections',
                    ),
                  ),
                ),
                if (finding != null && finding != '')
                  Text(finding!, style: const TextStyle(fontSize: 12)),
                if (found != null)
                  found!.isEmpty
                      ? const Text('No note collections for this user.')
                      : DropdownButtonFormField<String>(
                          key: const Key('connect-pick'),
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Collection',
                          ),
                          items: [
                            for (final c in found!)
                              DropdownMenuItem(
                                value: c.path,
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setLocal(() => path.text = v ?? ''),
                        ),
                TextField(
                  key: const Key('connect-path'),
                  controller: path,
                  decoration: const InputDecoration(
                    labelText: 'Collection path',
                    hintText: 'or type it: user/collection/',
                  ),
                ),
                CheckboxListTile(
                  key: const Key('connect-replace'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: replace,
                  onChanged: (v) => setLocal(() => replace = v ?? false),
                  title: const Text('Start from the server (drop local notes)'),
                ),
                const Text(
                  'Otherwise notes here are sent to this collection and merged with what '
                  'it holds. The login is kept in this browser.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('connect-go'),
              onPressed: submit,
              child: const Text('Connect'),
            ),
          ],
        );
      },
    ),
  );
}
