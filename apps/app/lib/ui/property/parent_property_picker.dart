import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../state/parent_targets.dart';
import '../parts.dart';
import '../theme.dart';
import 'option_picker.dart';

/// Where an item sits in a picker: a search field over the [targets], each
/// row indented by its depth and marked when it is a folder or a task.
class ParentPropertyPicker extends StatefulWidget {
  const ParentPropertyPicker({
    super.key,
    required this.id,
    required this.targets,
    this.value,
    required this.onPick,
  });

  /// Names the rows' and field's keys (`property-parent-<id>-...`).
  final String id;
  final List<ParentTarget> targets;
  final String? value;
  final Future<bool> Function(String?) onPick;

  @override
  State<ParentPropertyPicker> createState() => _ParentPropertyPickerState();
}

class _ParentPropertyPickerState extends State<ParentPropertyPicker> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(String? uid) async {
    await widget.onPick(uid);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final p in widget.targets)
        if (q.isEmpty || p.label.toLowerCase().contains(q)) p,
    ];
    return Padding(
      padding: EdgeInsets.all(t.space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: t.space.sm,
        children: [
          field(
            key: Key('property-parent-${widget.id}-search'),
            controller: _search,
            hint: 'Search…',
            prefixIcon: FLucideIcons.search,
            onChange: (v) => setState(() => _query = v),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: t.sizes.dialogLg),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in shown)
                    PickerRow(
                      key: Key(
                        'property-parent-${widget.id}-${p.uid ?? 'top'}',
                      ),
                      label: p.label,
                      hint: switch (p.kind) {
                        ParentKind.folder => 'folder',
                        ParentKind.task => 'task',
                        ParentKind.note || ParentKind.top => null,
                      },
                      icon: switch (p.kind) {
                        ParentKind.top => FLucideIcons.arrowUpToLine,
                        ParentKind.folder => FLucideIcons.folder,
                        ParentKind.task => FLucideIcons.circleCheck,
                        ParentKind.note => FLucideIcons.fileText,
                      },
                      selected: p.uid == widget.value,
                      depth: p.depth,
                      onPress: () => _pick(p.uid),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
