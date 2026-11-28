import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../chips.dart';
import '../empty_state.dart';
import '../parts.dart';
import '../theme.dart';

/// The labels of an item in a picker: one checkable chip per tag (the item's
/// own and any [suggestions]), and a field to add a new one. Each toggle and
/// each added tag commits at once.
class TagPropertyPicker extends StatefulWidget {
  const TagPropertyPicker({
    super.key,
    required this.id,
    required this.value,
    required this.onPick,
    this.suggestions = const [],
  });

  /// Names the chips' and field's keys (`property-tag-<id>-...`).
  final String id;
  final List<String> value;
  final Future<bool> Function(List<String>) onPick;
  final List<String> suggestions;

  @override
  State<TagPropertyPicker> createState() => _TagPropertyPickerState();
}

class _TagPropertyPickerState extends State<TagPropertyPicker> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _commit(List<String> tags) async {
    if (await widget.onPick(tags)) _controller.clear();
  }

  void _add(String text) {
    final tag = text.trim();
    if (tag.isEmpty || widget.value.contains(tag)) return;
    _commit([...widget.value, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final all = <String>{
      ...widget.value,
      for (final s in widget.suggestions)
        if (s.isNotEmpty) s,
    }.toList()..sort();
    return Padding(
      padding: EdgeInsets.all(t.space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space.lg,
        children: [
          if (all.isEmpty)
            const EmptyState('No labels yet')
          else
            Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.sm,
              children: [
                for (final tag in all)
                  FTappable(
                    key: Key('property-tag-${widget.id}-$tag'),
                    onPress: () => _commit(
                      widget.value.contains(tag)
                          ? [...widget.value.where((v) => v != tag)]
                          : [...widget.value, tag],
                    ),
                    child: TagChip(tag, selected: widget.value.contains(tag)),
                  ),
              ],
            ),
          field(
            key: Key('property-tag-${widget.id}-field'),
            controller: _controller,
            hint: 'Add a label…',
            prefixIcon: FLucideIcons.plus,
            onSubmit: _add,
          ),
        ],
      ),
    );
  }
}
