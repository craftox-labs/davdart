import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'theme.dart';

/// One choice of a [Segmented] control: [value], its [label] and widget key.
/// [icon] is optional: with it the segment shows the icon and label on a wide
/// layout and the icon alone on a narrow one (the label stays in the tooltip
/// and the semantics).
class Segment<T> {
  const Segment(this.value, this.label, this.key, {this.icon});
  final T value;
  final String label;
  final String key;
  final IconData? icon;
}

/// A small segmented selector (outlined box, the chosen segment filled).
/// With [fullWidth] it spans its parent with equal-width segments: the rule
/// on phones for selectors of this kind.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.fullWidth = false,
  });
  final List<Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    Widget seg(Segment<T> s) {
      final on = value == s.value;
      final icon = s.icon;
      final narrow = narrowLayout(context);
      Widget text() => Text(
        s.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.type.captionStyle.copyWith(
          color: on ? t.fg : t.muted,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
      );
      Widget content() {
        if (icon == null) return text();
        final mark = Icon(icon, size: t.icons.sm, color: on ? t.fg : t.muted);
        if (narrow) {
          return FTooltip(tipBuilder: (_, _) => Text(s.label), child: mark);
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            mark,
            SizedBox(width: t.space.xs),
            Flexible(child: text()),
          ],
        );
      }

      final tap = FTappable(
        key: Key(s.key),
        behavior: HitTestBehavior.opaque,
        semanticsLabel: s.label,
        onPress: () => onChanged(s.value),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: narrowLayout(context)
                ? t.sizes.touchTarget
                : t.sizes.segmentHeight,
            minWidth: t.sizes.segmentMin,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: on ? t.selected : null,
              borderRadius: BorderRadius.circular(t.radii.card),
            ),
            child: Padding(
              // Only the icon segments need breathing room; the label-only
              // switchers keep their original look.
              padding: EdgeInsets.symmetric(
                horizontal: icon == null ? 0 : t.space.xs,
              ),
              child: Center(child: content()),
            ),
          ),
        ),
      );
      return fullWidth ? Expanded(child: tap) : tap;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: t.cardBorder),
        borderRadius: BorderRadius.circular(t.radii.card),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [for (final s in segments) seg(s)],
      ),
    );
  }
}
