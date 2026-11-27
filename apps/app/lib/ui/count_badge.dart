import 'package:flutter/widgets.dart';

import 'theme.dart';

/// How a [CountBadge] reads: a filled accent pill (hidden columns), quiet
/// muted text (a section's item count), a tinted danger pill (overdue) or the
/// outlined square of the narrow top bar.
enum BadgeTone { accent, muted, danger, outline }

/// The one count badge: [count] (or [text]) in the tone's shape and colours,
/// built from the badge tokens so no site hand-builds its own box.
class CountBadge extends StatelessWidget {
  const CountBadge(
    this.count, {
    super.key,
    this.tone = BadgeTone.muted,
    this.text,
  });

  final int count;

  /// Overrides the label; [count] still sizes the square outline.
  final String? text;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final label = text ?? '$count';
    switch (tone) {
      case BadgeTone.accent:
        return Container(
          padding: EdgeInsets.symmetric(horizontal: t.space.xs),
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: BorderRadius.circular(t.radii.pill),
          ),
          child: Text(
            label,
            style: t.type.captionStyle.copyWith(color: t.onAccent),
          ),
        );
      case BadgeTone.danger:
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: t.space.sm,
            vertical: t.space.xxs,
          ),
          decoration: BoxDecoration(
            color: t.dangerTint,
            borderRadius: BorderRadius.circular(t.radii.card),
          ),
          child: Text(
            label,
            style: t.type.captionStyle.copyWith(color: t.statusBlocked),
          ),
        );
      case BadgeTone.outline:
        return Container(
          width: t.sizes.countBox,
          height: t.sizes.countBox,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: t.muted, width: t.borders.hairline),
            borderRadius: BorderRadius.circular(t.radii.badge),
          ),
          child: Text(label, style: t.type.labelStyle),
        );
      case BadgeTone.muted:
        return Text(label, style: t.type.captionStyle.copyWith(color: t.muted));
    }
  }
}
