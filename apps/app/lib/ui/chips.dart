import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'theme.dart';

Color statusColor(String? status, BuildContext context) {
  final t = tokensOf(context);
  switch (status) {
    case 'done':
      return t.statusDone;
    case 'doing':
      return t.accent;
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
