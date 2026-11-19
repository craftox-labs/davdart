import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import 'parts.dart';

/// Names and saves the current view, search and tag filter.
Future<void> showSaveViewDialog(BuildContext context, AppState state) {
  final name = TextEditingController(text: state.tag ?? state.query.trim());
  void submit(BuildContext ctx) {
    if (name.text.trim().isEmpty) return;
    Navigator.of(ctx).pop();
    state.saveView(name.text);
  }

  return showAppDialog(
    context,
    title: 'Save this view',
    content: Builder(
      builder: (ctx) => field(
        key: const Key('view-name'),
        controller: name,
        autofocus: true,
        hint: 'Name',
        onSubmit: (_) => submit(ctx),
      ),
    ),
    actions: [
      const CancelButton(),
      ActionButton('Save', key: const Key('view-save'), onPress: submit),
    ],
  );
}
