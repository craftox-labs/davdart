import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../state/app_state.dart';
import 'property_row.dart';
import 'property_trigger.dart';

/// One property row whose value opens [picker]: the picker hands every picked
/// value to [onPick] (the write). A write that does not go through flashes the
/// row's value in the error colour and shows the shell's "Not saved" notice
/// with the reason; the value itself comes from the item, so it reads as it
/// was before the pick.
class PropertyPicker<T> extends StatefulWidget {
  const PropertyPicker({
    super.key,
    required this.id,
    required this.state,
    required this.icon,
    required this.label,
    required this.picker,
    required this.onPick,
    this.text,
    this.value,
    this.placeholder = '—',
  });

  /// Names the row, its sheet and its options (`property-<id>`,
  /// `property-sheet-<id>`).
  final String id;
  final AppState state;
  final IconData icon;
  final String label;

  /// The picker content; `apply` writes the picked value.
  final Widget Function(
    BuildContext context,
    FPopoverController control,
    ValueChanged<T?> apply,
  )
  picker;
  final Future<bool> Function(T? value) onPick;
  final String? text;
  final Widget? value;
  final String placeholder;

  @override
  State<PropertyPicker<T>> createState() => _PropertyPickerState<T>();
}

class _PropertyPickerState<T> extends State<PropertyPicker<T>> {
  var _failed = false;

  Future<void> _apply(T? value) async {
    final ok = await widget.onPick(value);
    if (!mounted) return;
    if (ok) {
      if (_failed) setState(() => _failed = false);
      return;
    }
    setState(() => _failed = true);
    widget.state.reportNotSaved(widget.state.error ?? 'could not save');
    // One build cycle in the error colour, then the row reads normally.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _failed) setState(() => _failed = false);
    });
  }

  @override
  Widget build(BuildContext context) => PropertyTrigger(
    sheetKey: Key('property-sheet-${widget.id}'),
    picker: (context, control) => widget.picker(context, control, _apply),
    child: PropertyRow(
      key: Key('property-${widget.id}'),
      icon: widget.icon,
      label: widget.label,
      text: widget.text,
      value: widget.value,
      placeholder: widget.placeholder,
      error: _failed,
      interactive: true,
    ),
  );
}
