import 'package:flutter/foundation.dart' show setEquals;
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

  /// The tags showing here: the last toggle or added label, until the item
  /// reports it back. Two quick taps build on it, so both land.
  List<String>? _pending;

  List<String> get _tags => _pending ?? widget.value;

  @override
  void didUpdateWidget(TagPropertyPicker old) {
    super.didUpdateWidget(old);
    final pending = _pending;
    // The item caught up with the pick, or its labels changed elsewhere: show
    // its own.
    if (pending != null && setEquals(pending.toSet(), widget.value.toSet())) {
      _pending = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _commit(List<String> tags) async {
    setState(() => _pending = tags);
    if (await widget.onPick(tags)) {
      _controller.clear();
      return;
    }
    // Did not go through: the item's own labels show again.
    if (mounted) setState(() => _pending = null);
  }

  void _add(String text) {
    final tag = text.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    _commit([..._tags, tag]);
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final tags = _tags;
    final all = <String>{
      ...tags,
      for (final s in widget.suggestions)
        if (s.isNotEmpty) s,
    }.toList()..sort();
    return Padding(
      padding: EdgeInsets.all(t.property.formPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.property.formGap,
        children: [
          if (all.isEmpty)
            const EmptyState('No labels yet')
          else
            Wrap(
              spacing: t.property.chipGap,
              runSpacing: t.property.chipGap,
              children: [
                for (final tag in all)
                  FTappable(
                    key: Key('property-tag-${widget.id}-$tag'),
                    onPress: () => _commit(
                      tags.contains(tag)
                          ? [...tags.where((v) => v != tag)]
                          : [...tags, tag],
                    ),
                    child: TagChip(tag, selected: tags.contains(tag)),
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
