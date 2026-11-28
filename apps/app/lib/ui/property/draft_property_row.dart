import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'property_defs.dart';
import 'property_row.dart';
import 'property_trigger.dart';

/// A property row for an item that is not saved yet (a new-item dialog): the
/// same row and picker as [PropertyPicker], but the pick lands in the dialog's
/// form through [picker] instead of a write. [text] or [value] is what the row
/// shows now.
class DraftPropertyRow extends StatelessWidget {
  const DraftPropertyRow({
    super.key,
    required this.def,
    required this.picker,
    this.text,
    this.value,
    this.id,
  });
  final PropertyDef def;

  /// Names the row and its sheet (default: the property's id).
  final String? id;
  final String? text;
  final Widget? value;
  final Widget Function(BuildContext context, FPopoverController control)
  picker;

  String get _name => id ?? def.id;

  @override
  Widget build(BuildContext context) => PropertyTrigger(
    sheetKey: Key('property-sheet-$_name'),
    picker: picker,
    child: PropertyRow(
      key: Key('property-$_name'),
      icon: def.icon,
      label: def.label,
      text: text,
      value: value,
      interactive: true,
    ),
  );
}
