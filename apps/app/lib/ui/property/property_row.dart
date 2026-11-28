import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../surface.dart';
import '../theme.dart';

/// The rows of one item's properties, flat on the page: no card and no
/// padding box, with a hairline divider between rows, so the rows read as the
/// page's own lines. Each row keeps its hover fill.
class PropertySection extends StatelessWidget {
  const PropertySection({super.key, required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const PropertyDivider(),
          rows[i],
        ],
      ],
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
    // No horizontal inset: the label column starts flush with the page's own
    // text (a title, a section label), and the hover fill does not move it.
    final row = Surface(
      hovered: tappable && _hover,
      radius: t.radii.small,
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

/// The hairline between two [PropertyRow]s of a flat [PropertySection].
class PropertyDivider extends StatelessWidget {
  const PropertyDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(height: t.borders.hairline, color: t.divider);
  }
}
