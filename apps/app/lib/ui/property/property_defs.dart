import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../state/app_state.dart' show boardOrder;
import '../../state/event_rules.dart' show eventStatusWords;
import 'option_picker.dart';

/// One property of an item: its [id] (keys and sheet names), the row [label]
/// and its [icon]. Rows, menus, dialogs and cards all read these, so renaming
/// a property or changing its icon is one edit here.
class PropertyDef {
  const PropertyDef(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;

  /// The menu entry that edits it ("Set status").
  String get setLabel => 'Set $label';
}

/// Every property the pickers edit.
abstract final class Props {
  static const status = PropertyDef('status', 'status', FLucideIcons.circleDot);
  static const priority = PropertyDef(
    'priority',
    'priority',
    FLucideIcons.flag,
  );
  static const due = PropertyDef('due', 'due', FLucideIcons.calendar);
  static const start = PropertyDef(
    'start',
    'start',
    FLucideIcons.calendarRange,
  );
  static const labels = PropertyDef('tags', 'labels', FLucideIcons.tag);
  static const parent = PropertyDef(
    'parent',
    'belongs to',
    FLucideIcons.folderKanban,
  );

  /// The menu and command entry that moves an item under another one.
  static const moveLabel = 'Move to project…';
  static const moveIcon = FLucideIcons.folderInput;

  /// The label of the "no value" row of the priority picker.
  static const noPriority = 'No priority';
  static const noStatus = 'No status';
}

/// The task board statuses as (board word, shown word).
const statusWords = [
  ('backlog', 'Backlog'),
  ('todo', 'To do'),
  ('doing', 'Doing'),
  ('blocked', 'Blocked'),
  ('review', 'Review'),
  ('done', 'Done'),
  ('canceled', 'Canceled'),
];

/// The label a board status shows everywhere ('Doing' for `doing`, ...).
String statusWordOf(String? status) => statusWords
    .firstWhere(
      (e) => e.$1 == status,
      orElse: () => (status ?? '', status ?? ''),
    )
    .$2;

/// Priority as the three buckets the pickers offer (RFC 5545: 1-4 high,
/// 5 medium, 6-9 low, 0 or none).
String priorityBucket(int? p) => p == null || p <= 0
    ? 'none'
    : p <= 4
    ? 'high'
    : p == 5
    ? 'medium'
    : 'low';

/// The label a priority bucket shows ('High'); stored words stay lowercase.
String priorityText(String bucket) => bucket == 'none'
    ? Props.noPriority
    : bucket[0].toUpperCase() + bucket.substring(1);

int? priorityOfBucket(String? b) => switch (b) {
  'high' => 1,
  'medium' => 5,
  'low' => 9,
  _ => null,
};

/// The status choices of a task; `done` is off while [blocked] holds it back.
List<PickerOption<String>> taskStatusOptions({bool blocked = false}) => [
  for (final e in statusWords)
    PickerOption(e.$1, e.$2, dot: e.$1, enabled: !(e.$1 == 'done' && blocked)),
];

/// The status choices of a note (the board columns), without a "none" row.
List<PickerOption<String>> noteStatusOptions() => [
  for (final s in boardOrder) PickerOption(s, statusWordOf(s), dot: s),
];

/// The priority choices (high, medium, low) with each bucket mapped to the
/// picker's value type by [valueOf]; "none" is the picker's clear row.
List<PickerOption<T>> priorityOptions<T>(T Function(String bucket) valueOf) => [
  for (final b in const ['high', 'medium', 'low'])
    PickerOption(valueOf(b), priorityText(b), icon: Props.priority.icon),
];

/// The event status choices: none, confirmed, tentative, cancelled.
List<PickerOption<String>> eventStatusOptions() => [
  for (final (word, label) in eventStatusWords)
    PickerOption(
      word,
      label,
      icon: switch (word) {
        'CONFIRMED' => FLucideIcons.circleCheck,
        'TENTATIVE' => FLucideIcons.circleDot,
        'CANCELLED' => FLucideIcons.x,
        _ => FLucideIcons.circle,
      },
    ),
];
