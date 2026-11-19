import 'package:davdart/davdart.dart';
import 'package:material_ui/material_ui.dart';

import 'markdown_lite.dart';

Color statusColor(String? status, BuildContext context) {
  final t = Theme.of(context).extension<TokensTheme>()!.tokens;
  switch (status) {
    case 'done':
      return const Color(0xFF3FA37A);
    case 'doing':
      return t.accent;
    case 'blocked':
      return const Color(0xFFD9694F);
    case 'todo':
      return const Color(0xFFD8A23A);
    default:
      return t.muted;
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key});
  final String? status;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: statusColor(status, context),
      shape: BoxShape.circle,
    ),
  );
}

class TagChip extends StatelessWidget {
  const TagChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<TokensTheme>()!.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: t.muted)),
    );
  }
}

/// Short label for a note: its item id when it has one, else its title.
String noteLabel(Note n) => PlanItem.fromNote(n).itemId ?? n.summary;
