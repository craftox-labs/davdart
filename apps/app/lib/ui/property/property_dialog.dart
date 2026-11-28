import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';

import '../../state/app_state.dart';
import '../move_folder_dialog.dart';
import '../parts.dart';
import '../theme.dart';
import 'date_property_picker.dart';
import 'parent_property_picker.dart';
import 'property_defs.dart';

/// Moves item [uid] (a note, a task or an event) under another item: the one
/// entry every menu and command uses. A note keeps its own dialog (its Personal
/// container and project rules); a task or event gets the same
/// [ParentPropertyPicker] the "belongs to" row opens, with the row's write
/// (and Undo). The dialog closes on a pick.
Future<void> showMoveToParentDialog(
  BuildContext context,
  AppState state,
  String uid,
) {
  final note = state.tree.find(uid)?.note;
  if (note != null) return showMoveFolderDialog(context, state, note);
  return _showParentPickerDialog(context, state, uid);
}

Future<void> _showParentPickerDialog(
  BuildContext context,
  AppState state,
  String uid,
) => showAppDialog(
  context,
  title: Props.moveLabel,
  width: tokensOf(context).sizes.dialogSm,
  content: Builder(
    builder: (ctx) => ParentPropertyPicker(
      id: 'move',
      state: state,
      uid: uid,
      onPick: (v) async {
        Navigator.of(ctx).pop();
        final ok = switch (state.findItem(uid)) {
          Note _ => await state.setNoteParent(uid, v),
          Task _ => await state.setTaskParent(uid, v),
          Event _ => await state.setEventParent(uid, v),
          _ => false,
        };
        if (!ok) state.reportNotSaved(state.error ?? 'could not move');
        return ok;
      },
    ),
  ),
  actions: [const CancelButton()],
);

/// A date property in a dialog, through the shared [DatePropertyPicker]:
/// [onPick] gets the picked day (a UTC date) or null for Clear; the dialog
/// closes on a pick.
Future<void> showDateDialog(
  BuildContext context, {
  required PropertyDef def,
  required DateTime? value,
  required ValueChanged<DateTime?> onPick,
}) => showAppDialog(
  context,
  title: def.setLabel,
  width: tokensOf(context).sizes.dialogSm,
  content: Builder(
    builder: (ctx) => DatePropertyPicker(
      id: def.id,
      value: value,
      onPick: (d) {
        Navigator.of(ctx).pop();
        onPick(d);
      },
    ),
  ),
  actions: [const CancelButton()],
);
