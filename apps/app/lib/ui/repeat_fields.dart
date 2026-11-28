import 'popover_track.dart';

import 'package:davdart/davdart.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../state/event_rules.dart' show repeatFrequencies;
import 'theme.dart';

const _unit = {
  'DAILY': 'day(s)',
  'WEEKLY': 'week(s)',
  'MONTHLY': 'month(s)',
  'YEARLY': 'year(s)',
};
const _dayLetters = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/// The repeat section of an event form: frequency, interval, weekdays (weekly)
/// and end (never, after N times, on a date). Shows and writes the simple
/// rules of [RepeatRule]; any other rule is shown as a "custom" rule that is
/// kept until a frequency is picked. Keys are `<keys>-repeat`, `-interval`,
/// `-weekday-N`, `-end`, `-count`, `-until`, `-custom`.
class RepeatFields extends StatelessWidget {
  const RepeatFields({
    super.key,
    required this.keys,
    required this.rrule,
    required this.start,
    required this.allDay,
    required this.onChange,
    this.groupId,
  });
  final String keys;

  /// The raw RRULE value, or null.
  final String? rrule;

  /// The event's first day, for the default weekday and end date.
  final DateTime start;

  /// All-day events write a date UNTIL, timed ones a date-time.
  final bool allDay;
  final ValueChanged<String?> onChange;

  /// The tap region of the popover this section sits in, so its own select
  /// popovers do not count as taps outside it.
  final Object? groupId;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final rule = RepeatRule.parse(rrule);
    final custom = rule == null && rrule != null && rrule!.isNotEmpty;
    final freq = rule?.freq ?? (custom ? 'CUSTOM' : '');

    void set(RepeatRule r) => onChange(r.toRrule());

    Widget stepper(Key key, int value, int min, ValueChanged<int> on) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      spacing: t.space.sm,
      children: [
        FButton.icon(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          onPress: value > min ? () => on(value - 1) : null,
          child: const Icon(FLucideIcons.minus),
        ),
        Text('$value', style: t.type.bodyStyle),
        FButton.icon(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          onPress: () => on(value + 1),
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );

    final end = rule == null
        ? ''
        : rule.count != null
        ? 'count'
        : rule.until != null
        ? 'until'
        : '';
    final startDay = DateTime.utc(start.year, start.month, start.day);
    // A weekly rule without BYDAY repeats on the start's weekday.
    final weekdays = rule == null || rule.weekdays.isNotEmpty
        ? rule?.weekdays ?? const <int>[]
        : [startDay.weekday];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: t.space.md,
      children: [
        TrackPopover(
          builder: (_, pc) => FSelect<String>.rich(
            popoverControl: pc,
            key: Key('$keys-repeat'),
            contentGroupId: groupId,
            label: const Text('Repeat'),
            format: (v) => v == 'CUSTOM'
                ? 'Custom'
                : repeatFrequencies.firstWhere((e) => e.$1 == v).$2,
            control: FSelectControl.lifted(
              value: freq,
              onChange: (v) {
                if (v == null || v == freq || v == 'CUSTOM') return;
                if (v.isEmpty) return onChange(null);
                // Keep the interval and the end when the frequency changes.
                set(
                  (rule ?? const RepeatRule(freq: 'DAILY')).copyWith(
                    freq: v,
                    weekdays: v == 'WEEKLY' ? [startDay.weekday] : const [],
                  ),
                );
              },
            ),
            children: [
              for (final e in repeatFrequencies)
                FSelectItem<String>(title: Text(e.$2), value: e.$1),
              if (custom)
                const FSelectItem<String>(
                  title: Text('Custom'),
                  value: 'CUSTOM',
                ),
            ],
          ),
        ),
        if (custom)
          Text(
            'Custom rule, kept as it is: $rrule. Pick a frequency to replace it.',
            key: Key('$keys-custom'),
            style: t.type.captionStyle.copyWith(color: t.muted),
          ),
        if (rule != null) ...[
          Wrap(
            spacing: t.space.md,
            runSpacing: t.space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Every', style: t.type.bodyStyle),
              stepper(
                Key('$keys-interval'),
                rule.interval,
                1,
                (v) => set(rule.copyWith(interval: v)),
              ),
              Text(_unit[rule.freq]!, style: t.type.bodyStyle),
            ],
          ),
          if (rule.freq == 'WEEKLY')
            Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.sm,
              children: [
                for (var d = 1; d <= 7; d++)
                  FButton(
                    key: Key('$keys-weekday-$d'),
                    variant: weekdays.contains(d)
                        ? FButtonVariant.primary
                        : FButtonVariant.outline,
                    size: FButtonSizeVariant.sm,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () {
                      final w = weekdays.toSet();
                      // Keep at least one weekday.
                      if (!w.remove(d)) {
                        w.add(d);
                      } else if (w.isEmpty) {
                        return;
                      }
                      set(rule.copyWith(weekdays: w.toList()..sort()));
                    },
                    child: Text(_dayLetters[d - 1]),
                  ),
              ],
            ),
          TrackPopover(
            builder: (_, pc) => FSelect<String>.rich(
              popoverControl: pc,
              key: Key('$keys-end'),
              label: const Text('Ends'),
              format: (v) => switch (v) {
                'count' => 'After a number of times',
                'until' => 'On a date',
                _ => 'Never',
              },
              control: FSelectControl.lifted(
                value: end,
                onChange: (v) {
                  if (v == null || v == end) return;
                  final base = rule.copyWith(clearEnd: true);
                  set(switch (v) {
                    'count' => base.copyWith(count: 10),
                    'until' => base.copyWith(
                      until: startDay.add(const Duration(days: 30)),
                      untilTimed: !allDay,
                    ),
                    _ => base,
                  });
                },
              ),
              children: const [
                FSelectItem<String>(title: Text('Never'), value: ''),
                FSelectItem<String>(
                  title: Text('After a number of times'),
                  value: 'count',
                ),
                FSelectItem<String>(title: Text('On a date'), value: 'until'),
              ],
            ),
          ),
          if (rule.count != null)
            Wrap(
              spacing: t.space.md,
              runSpacing: t.space.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('After', style: t.type.bodyStyle),
                stepper(
                  Key('$keys-count'),
                  rule.count!,
                  1,
                  (v) => set(rule.copyWith(count: v)),
                ),
                Text('time(s)', style: t.type.bodyStyle),
              ],
            ),
          if (rule.until != null)
            TrackPopover(
              builder: (_, pc) => FDateField.calendar(
                popoverControl: pc,
                key: Key('$keys-until'),
                label: const Text('Last day'),
                selectionControl: FDateSelectionControl.liftedSingle(
                  value: rule.until!,
                  onChange: (d) {
                    if (d == null) return;
                    final picked = DateTime.utc(d.year, d.month, d.day);
                    if (picked != rule.until) {
                      set(rule.copyWith(until: picked, untilTimed: !allDay));
                    }
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }
}
