import 'popover_track.dart';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'theme.dart';

/// The when-fields of an event form: an all-day switch, the start date and
/// time, the end date and time (no times while all day). Used by the new
/// event dialog and the editor; both keep the values (wall-clock fields,
/// UTC-flagged; for all day the end is the last day) and get the changes
/// through the callbacks. Keys are `<keys>-allday`, `-start-date`,
/// `-start-time`, `-end-date`, `-end-time`.
class EventWhenFields extends StatelessWidget {
  const EventWhenFields({
    super.key,
    required this.keys,
    required this.allDay,
    required this.start,
    required this.end,
    required this.onAllDay,
    required this.onStart,
    required this.onEnd,
    this.error,
    this.groupId,
  });
  final String keys;
  final bool allDay;
  final DateTime start, end;
  final ValueChanged<bool> onAllDay;

  /// A changed date and/or time of day in minutes (the other stays).
  final void Function(DateTime? date, int? minutes) onStart, onEnd;
  final String? error;

  /// The tap region of the popover this form sits in, so its own date, time
  /// and select popovers do not count as taps outside it.
  final Object? groupId;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    Widget date(
      String id,
      String label,
      DateTime v,
      ValueChanged<DateTime> set,
    ) {
      final day = DateTime.utc(v.year, v.month, v.day);
      return TrackPopover(
        builder: (_, pc) => FDateField.calendar(
          popoverControl: pc,
          key: Key('$keys-$id-date'),
          label: Text(label),
          calendar: FDateFieldGridCalendarProperties(groupId: groupId),
          selectionControl: FDateSelectionControl.liftedSingle(
            value: day,
            onChange: (d) {
              if (d == null) return;
              final picked = DateTime.utc(d.year, d.month, d.day);
              if (picked != day) set(picked);
            },
          ),
        ),
      );
    }

    Widget time(String id, String label, DateTime v, ValueChanged<int> set) =>
        FTimeField.picker(
          key: Key('$keys-$id-time'),
          label: Text(label),
          hour24: true,
          groupId: groupId,
          control: FTimeFieldControl.lifted(
            time: FTime(v.hour, v.minute),
            onChange: (x) {
              if (x == null) return;
              final mins = x.hour * 60 + x.minute;
              if (mins != v.hour * 60 + v.minute) set(mins);
            },
          ),
        );

    Widget pair(Widget a, Widget? b) => LayoutBuilder(
      builder: (context, c) {
        if (b == null) return a;
        if (c.maxWidth < t.sizes.dialogSm) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space.lg,
            children: [a, b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: t.space.lg,
          children: [
            Expanded(child: a),
            Expanded(child: b),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: t.space.lg,
      children: [
        FCheckbox(
          key: Key('$keys-allday'),
          label: const Text('All day'),
          semanticsLabel: 'All day',
          value: allDay,
          onChange: onAllDay,
        ),
        pair(
          date('start', 'Start', start, (d) => onStart(d, null)),
          allDay
              ? null
              : time('start', 'Start time', start, (m) => onStart(null, m)),
        ),
        pair(
          date('end', allDay ? 'Last day' : 'End', end, (d) => onEnd(d, null)),
          allDay ? null : time('end', 'End time', end, (m) => onEnd(null, m)),
        ),
        if (error != null)
          Text(
            error!,
            key: Key('$keys-error'),
            style: t.type.captionStyle.copyWith(color: t.error),
          ),
      ],
    );
  }
}
