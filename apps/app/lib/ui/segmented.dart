import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'theme.dart';

/// One choice of a [Segmented] control: [value], its [label] and widget key.
class Segment<T> {
  const Segment(this.value, this.label, this.key);
  final T value;
  final String label;
  final String key;
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
            child: Center(
              child: Text(
                s.label,
                style: t.type.captionStyle.copyWith(
                  color: on ? t.fg : t.muted,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
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
