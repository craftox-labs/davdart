import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';
import 'theme.dart';

/// Asks for a title and adds the note, under the selected note if chosen.
Future<void> showNewNoteDialog(BuildContext context, AppState state) {
  final parent = state.selected ?? state.scope;
  final title = TextEditingController();
  var underParent = parent != null;
  void submit(BuildContext ctx) {
    final text = title.text;
    if (text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.addNote(
      text,
      parentUid: underParent ? parent?.uid : null,
      status: 'backlog',
    );
  }

  return showAppDialog(
    context,
    title: 'New note',
    width: tokensOf(context).sizes.dialog,
    content: StatefulBuilder(
      builder: (ctx, setLocal) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokensOf(ctx).space.lg,
          children: [
            field(
              key: const Key('new-note-title'),
              controller: title,
              autofocus: true,
              hint: 'Title',
              onSubmit: (_) => submit(ctx),
            ),
            if (parent != null)
              FCheckbox(
                key: const Key('new-note-under'),
                value: underParent,
                onChange: (v) => setLocal(() => underParent = v),
                label: Text(
                  'Under "${parent.summary}"',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      },
    ),
    actions: [
      const CancelButton(),
      ActionButton('Add', key: const Key('new-note-add'), onPress: submit),
    ],
  );
}
