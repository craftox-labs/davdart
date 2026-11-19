import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import 'parts.dart';

/// Names and saves the current view, search and tag filter.
Future<void> showSaveViewDialog(BuildContext context, AppState state) {
  final name = TextEditingController(
    text:
        state.tag ??
        (state.query.trim().isEmpty
            ? state.scope?.summary
            : state.query.trim()) ??
        '',
  );
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

/// Renames a saved view.
Future<void> showRenameViewDialog(
  BuildContext context,
  AppState state,
  SavedView view,
) {
  final name = TextEditingController(text: view.name);
  String? error;
  void Function(void Function())? setError;
  Future<void> submit(BuildContext ctx) async {
    final err = await state.renameView(view, name.text);
    if (!ctx.mounted) return;
    if (err == null) {
      Navigator.of(ctx).pop();
    } else {
      setError?.call(() => error = err);
    }
  }

  return showAppDialog(
    context,
    title: 'Rename view',
    content: StatefulBuilder(
      builder: (ctx, setState) {
        setError = setState;
        return field(
          key: const Key('view-rename-name'),
          controller: name,
          autofocus: true,
          error: error,
          onSubmit: (_) => submit(ctx),
        );
      },
    ),
    actions: [
      const CancelButton(),
      ActionButton('Rename', key: const Key('view-rename'), onPress: submit),
    ],
  );
}
