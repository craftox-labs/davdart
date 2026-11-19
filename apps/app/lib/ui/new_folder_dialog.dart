import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/app_state.dart';
import 'parts.dart';

/// Names a new folder. Its text is optional: notes about the folder, or
/// instructions for whoever (or whatever agent) works inside it.
Future<void> showNewFolderDialog(BuildContext context, AppState state) {
  final inside = state.scope;
  final title = TextEditingController();
  final text = TextEditingController();
  var underScope = inside != null;
  void submit(BuildContext ctx) {
    if (title.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.addFolder(
      title.text,
      parentUid: underScope ? inside?.uid : null,
      text: text.text,
    );
  }

  return showAppDialog(
    context,
    title: 'New folder',
    width: 480,
    content: StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          field(
            key: const Key('new-folder-title'),
            controller: title,
            autofocus: true,
            hint: 'Name, for example Deployment',
            onSubmit: (_) => submit(ctx),
          ),
          field(
            key: const Key('new-folder-text'),
            controller: text,
            minLines: 3,
            maxLines: 8,
            label: 'Text (optional)',
            hint: 'About this folder, or instructions for agents',
          ),
          if (inside != null)
            FCheckbox(
              key: const Key('new-folder-inside'),
              value: underScope,
              onChange: (v) => setLocal(() => underScope = v),
              label: Text(
                'Inside "${inside.summary}"',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Create', key: const Key('new-folder-add'), onPress: submit),
    ],
  );
}
