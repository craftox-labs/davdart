import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../chips.dart';
import '../surface.dart';
import '../theme.dart';

/// One choice of a picker: its [value], the row [label], an optional [icon] or
/// status [dot] (`backlog`, `doing`, ...), whether it can be picked and a
/// [hint] after the label.
class PickerOption<T> {
  const PickerOption(
    this.value,
    this.label, {
    this.icon,
    this.dot,
    this.enabled = true,
    this.hint,
  });
  final T value;
  final String label;
  final IconData? icon;
  final String? dot;
  final bool enabled;
  final String? hint;
}

/// One row of a picker: touch-sized, with a dot or icon, the label and a check
/// on the selected one. Tapping it picks it (when [enabled]).
class PickerRow extends StatefulWidget {
  const PickerRow({
    super.key,
    required this.label,
    this.icon,
    this.dot,
    this.selected = false,
    this.enabled = true,
    this.hint,
    this.depth = 0,
    this.onPress,
  });
  final String label;
  final IconData? icon;
  final String? dot;
  final bool selected;
  final bool enabled;
  final String? hint;

  /// Tree depth: the row starts this many [SizeTokens.folderIndent]s in.
  final int depth;
  final VoidCallback? onPress;

  @override
  State<PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<PickerRow> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final on = widget.enabled && widget.onPress != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: FTappable(
        onPress: on ? widget.onPress : null,
        child: Surface(
          hovered: on && _hover,
          child: SizedBox(
            height: t.sizes.touchTarget,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space.md),
              child: Row(
                children: [
                  SizedBox(width: widget.depth * t.sizes.folderIndent),
                  if (widget.dot != null)
                    StatusDot(widget.dot)
                  else if (widget.icon != null)
                    Icon(
                      widget.icon,
                      size: t.icons.sm,
                      color: widget.enabled ? t.muted : t.faint,
                    ),
                  SizedBox(width: t.space.md),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.type.bodyStyle.copyWith(
                        color: widget.enabled ? null : t.faint,
                      ),
                    ),
                  ),
                  if (widget.hint != null) ...[
                    SizedBox(width: t.space.sm),
                    Text(
                      widget.hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.type.captionStyle.copyWith(color: t.muted),
                    ),
                  ],
                  if (widget.selected) ...[
                    SizedBox(width: t.space.sm),
                    Icon(FLucideIcons.check, size: t.icons.sm, color: t.accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-select list of [options] in a picker: the status, priority or
/// other word fields of an item. With [clearable] a "Clear" row picks null.
/// [id] names the rows' keys (`property-option-<id>-<value>`).
class OptionPicker<T> extends StatelessWidget {
  const OptionPicker({
    super.key,
    required this.id,
    required this.options,
    this.value,
    required this.onPick,
    this.clearable = false,
    this.clearLabel = 'Clear',
  });
  final String id;
  final List<PickerOption<T>> options;
  final T? value;
  final ValueChanged<T?> onPick;
  final bool clearable;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: EdgeInsets.all(t.space.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            PickerRow(
              key: Key('property-option-$id-${o.value}'),
              label: o.label,
              icon: o.icon,
              dot: o.dot,
              hint: o.hint,
              enabled: o.enabled,
              selected: o.value == value,
              onPress: o.enabled ? () => onPick(o.value) : null,
            ),
          if (clearable)
            PickerRow(
              key: Key('property-option-$id-clear'),
              label: clearLabel,
              icon: FLucideIcons.x,
              selected: value == null,
              onPress: () => onPick(null),
            ),
        ],
      ),
    );
  }
}
