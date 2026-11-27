import 'popover_track.dart';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../data/note_source.dart';
import '../state/app_state.dart';
import 'parts.dart';
import 'empty_state.dart';
import 'theme.dart';

/// Connects the local Space to a CalDAV collection through the board
/// server's /dav/ proxy. The first sync sends every local note and merges by
/// UID with what the server holds.
Future<void> showConnectDialog(BuildContext context, AppState state) {
  final path = TextEditingController();
  final user = TextEditingController();
  final password = TextEditingController();
  var replace = false;
  List<FoundCollection>? found;
  String? picked; // the path last chosen from the list
  String? finding; // null idle, '' searching, else the error
  void submit(BuildContext ctx) {
    if (path.text.trim().isEmpty || user.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.connect(
      path.text,
      user.text.trim(),
      password.text,
      replaceLocal: replace,
    );
  }

  return showAppDialog(
    context,
    title: 'Connect server',
    content: StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> find() async {
          if (user.text.trim().isEmpty) {
            setLocal(() => finding = 'Enter the user first');
            return;
          }
          setLocal(() => finding = '');
          try {
            final r = await state.discoverCollections(user.text, password.text);
            if (!ctx.mounted) return;
            setLocal(() {
              found = r;
              finding = null;
            });
          } catch (e) {
            if (!ctx.mounted) return;
            setLocal(() => finding = 'Could not list collections: $e');
          }
        }

        void loginChanged(String _) => setLocal(() {
          // A list found for another login no longer applies.
          if (found != null && path.text == picked) path.text = '';
          found = null;
          picked = null;
        });

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokensOf(ctx).space.lg,
          children: [
            field(
              key: const Key('connect-user'),
              controller: user,
              autofocus: true,
              label: 'User',
              onChange: loginChanged,
            ),
            field(
              key: const Key('connect-password'),
              controller: password,
              obscure: true,
              label: 'Password',
              onChange: loginChanged,
              onSubmit: (_) => submit(ctx),
            ),
            FButton(
              key: const Key('connect-find'),
              variant: FButtonVariant.outline,
              size: FButtonSizeVariant.sm,
              mainAxisSize: MainAxisSize.min,
              onPress: finding == '' ? null : find,
              child: Text(finding == '' ? 'Looking…' : 'Find collections'),
            ),
            if (finding != null && finding != '')
              Text(finding!, style: tokensOf(ctx).type.captionStyle),
            if (found != null)
              found!.isEmpty
                  ? const EmptyState(
                      'No note collections for this user.',
                      padding: EdgeInsets.zero,
                    )
                  : TrackPopover(
                      builder: (_, pc) => FSelect<String>.rich(
                        popoverControl: pc,
                        key: const Key('connect-pick'),
                        label: const Text('Collection'),
                        format: (v) =>
                            [
                              for (final c in found!)
                                if (c.path == v) c.name,
                            ].firstOrNull ??
                            v,
                        control: FSelectControl.lifted(
                          value: picked,
                          onChange: (v) => setLocal(() {
                            picked = v;
                            path.text = v ?? '';
                          }),
                        ),
                        children: [
                          for (final c in found!)
                            FSelectItem<String>(
                              title: Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: c.path,
                            ),
                        ],
                      ),
                    ),
            field(
              key: const Key('connect-path'),
              controller: path,
              label: 'Collection path',
              hint: 'or type it: user/collection/',
            ),
            FCheckbox(
              key: const Key('connect-replace'),
              value: replace,
              onChange: (v) => setLocal(() => replace = v),
              label: const Text('Start from the server (drop local notes)'),
            ),
            Text(
              'Otherwise notes here are sent to this collection and merged with what '
              'it holds. The login is kept in this browser.',
              style: tokensOf(ctx).type.captionStyle,
            ),
          ],
        );
      },
    ),
    actions: [
      const CancelButton(),
      ActionButton('Connect', key: const Key('connect-go'), onPress: submit),
    ],
  );
}
