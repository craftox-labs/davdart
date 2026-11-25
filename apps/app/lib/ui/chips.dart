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

class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final size = tokensOf(context).sizes.statusDot;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusColor(status, context),
        shape: BoxShape.circle,
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
