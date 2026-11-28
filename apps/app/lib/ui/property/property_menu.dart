import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../note_menu.dart' show NoteMenuItem;
import 'option_picker.dart';
import 'property_defs.dart';

/// A menu entry that opens a picker in a dialog ("Set due"): the label and
/// icon come from [def].
NoteMenuItem dialogMenuItem(
  PropertyDef def, {
  required Key key,
  required VoidCallback onPress,
}) => NoteMenuItem(def.setLabel, def.icon, onPress, key: key);

/// The context-menu form of an option property: a "Set <label>" submenu whose
/// rows are the picker's [options] (same labels and icons as the pickers; a
/// status dot reads as the property's icon), the current [value] checked.
/// [noneLabel] adds a first row that picks null. Rows are keyed
/// `<optionPrefix>-<value>` (`<optionPrefix>-none` for the none row).
NoteMenuItem optionMenuItem<T>(
  PropertyDef def, {
  required Key key,
  required String optionPrefix,
  required List<PickerOption<T>> options,
  required T? value,
  required void Function(T? value) onPick,
  String? noneLabel,
}) => NoteMenuItem(
  def.setLabel,
  def.icon,
  () {},
  key: key,
  children: [
    if (noneLabel != null)
      NoteMenuItem(
        noneLabel,
        FLucideIcons.circle,
        () => onPick(null),
        key: Key('$optionPrefix-none'),
        selected: value == null,
      ),
    for (final o in options)
      if (o.enabled)
        NoteMenuItem(
          o.label,
          o.icon ?? def.icon,
          () => onPick(o.value),
          key: Key('$optionPrefix-${o.value}'),
          selected: o.value == value,
        ),
  ],
);
