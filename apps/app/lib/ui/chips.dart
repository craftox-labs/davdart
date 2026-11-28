import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/tokens.dart';
import 'theme.dart';

/// The colour of a priority bucket ('high', 'medium', 'low'; anything else is
/// no priority): red, orange, cool slate. Shared by every card's priority mark.
Color priorityColorOf(Tokens t, String bucket) => switch (bucket) {
  'high' => t.error,
  'medium' => t.warning,
  'low' => t.priorityLow,
  _ => t.muted,
};

Color statusColor(String? status, BuildContext context) {
  final t = tokensOf(context);
  switch (status) {
    case 'done':
      return t.statusDone;
    case 'doing':
      return t.statusDoing;
    case 'blocked':
      return t.statusBlocked;
    case 'todo':
      return t.statusTodo;
    default:
      return t.muted;
  }
}

/// The one small round marker: a status colour, or any token colour through
/// [color] (a kind mark rather than a status, as in the calendar's day cells).
/// [size] overrides [SizeTokens.statusDot] for denser places; [hollow] draws
/// the tone as a hairline ring instead of a fill.
class StatusDot extends StatelessWidget {
  const StatusDot(
    this.status, {
    super.key,
    this.color,
    this.size,
    this.hollow = false,
  });
  final String? status;
  final Color? color;
  final double? size;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final dot = size ?? t.sizes.statusDot;
    final c = color ?? statusColor(status, context);
    return Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(
        color: hollow ? null : c,
        shape: BoxShape.circle,
        border: hollow ? Border.all(color: c, width: t.borders.hairline) : null,
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) =>
      FBadge(variant: FBadgeVariant.outline, child: Text(label));
}

/// Short label for a note: its item id when it has one, else its title.
String noteLabel(Note n) => PlanItem.fromNote(n).itemId ?? n.summary;
