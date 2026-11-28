import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../card_box.dart';
import '../surface.dart';
import '../theme.dart';

/// One card block of property rows: the meta block of a note, a task or an
/// event, with the card padding and the tight gap between its rows.
class PropertySection extends StatelessWidget {
  const PropertySection({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return CardBox(
      width: double.infinity,
      padding: EdgeInsets.all(t.space.lg),
      child: Column(spacing: t.space.xxs, children: rows),
    );
  }
}

/// One label-and-value line of a [PropertySection]: the icon and label in the
/// muted label column every meta row has had, then the [value] (or [text], or
/// the muted [placeholder] when there is none), and a chevron while hovered
/// when the row opens something.
///
/// [interactive] only paints the hover fill and the chevron; the tap belongs
/// to the caller (usually [PropertyTrigger] around it). [onTap] is for a row
/// that opens something other than a picker. A [readOnly] row is plain text
/// and takes no tap. [error] paints a plain [text] value in the error colour
/// (a write that did not go through).
class PropertyRow extends StatefulWidget {
  const PropertyRow({
    super.key,
    required this.icon,
    required this.label,
    this.text,
    this.value,
    this.placeholder = '—',
    this.onTap,
    this.interactive = false,
    this.readOnly = false,
    this.error = false,
    this.strike = false,
  });
  final IconData icon;
  final String label;

  /// A plain value rendered in the body style; ignored when [value] is set.
  final String? text;
  final Widget? value;
  final String placeholder;
  final VoidCallback? onTap;
  final bool interactive;
  final bool readOnly;
  final bool error;
  final bool strike;

  @override
  State<PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends State<PropertyRow> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final h = narrowLayout(context) ? t.sizes.touchTarget : t.sizes.propertyRow;
    final tappable =
        !widget.readOnly && (widget.onTap != null || widget.interactive);
    final text = widget.text;
    Widget value;
    if (widget.value != null) {
      value = widget.value!;
    } else if (text == null || text.isEmpty) {
      value = Text(
        widget.placeholder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.type.bodyStyle.copyWith(color: t.muted),
      );
    } else {
      value = Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.type.bodyStyle.copyWith(
          color: widget.error ? t.error : null,
          decoration: widget.strike ? TextDecoration.lineThrough : null,
        ),
      );
    }
    final row = Surface(
      hovered: tappable && _hover,
      padding: EdgeInsets.symmetric(horizontal: t.space.sm),
      child: SizedBox(
        height: h,
        child: Row(
          children: [
            SizedBox(
              width: t.sizes.metaLabel,
              child: Row(
                children: [
                  Icon(widget.icon, size: t.icons.sm, color: t.muted),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.type.monoStyle.copyWith(color: t.muted),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: t.space.md),
            Expanded(child: value),
            if (tappable && _hover) ...[
              SizedBox(width: t.space.sm),
              Icon(FLucideIcons.chevronRight, size: t.icons.sm, color: t.muted),
            ],
          ],
        ),
      ),
    );
    Widget out = row;
    if (widget.onTap != null && !widget.readOnly) {
      out = FTappable(onPress: widget.onTap, child: row);
    }
    if (!tappable) return out;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: out,
    );
  }
}
