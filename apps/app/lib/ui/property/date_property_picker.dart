import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../state/event_rules.dart' show dayLabel;
import '../task_parts.dart' show dayFromToday;
import '../theme.dart';
import 'option_picker.dart';

/// A date in a picker: the relative days first (same wording as [dayLabel]),
/// then the next week, then a calendar, then Clear.
class DatePropertyPicker extends StatelessWidget {
  const DatePropertyPicker({
    super.key,
    required this.id,
    this.value,
    required this.onPick,
    this.now,
  });

  /// Names the rows' keys (`property-date-<id>-...`).
  final String id;

  /// The picked day (a UTC date at midnight), or null.
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  /// The day "today" means; the real clock by default.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final clock = now ?? DateTime.now();
    final picked = value == null ? null : dayFromToday(0, value);
    Widget day(int days, String label, {String? key}) => PickerRow(
      key: Key('property-date-$id-${key ?? days}'),
      label: label,
      icon: FLucideIcons.calendar,
      selected: picked != null && picked == dayFromToday(days, clock),
      onPress: () => onPick(dayFromToday(days, clock)),
    );
    return Padding(
      padding: EdgeInsets.all(t.property.pickerPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          day(-1, 'Yesterday', key: 'yesterday'),
          day(0, 'Today', key: 'today'),
          day(1, 'Tomorrow', key: 'tomorrow'),
          for (var d = 2; d <= 8; d++)
            day(d, dayLabel(dayFromToday(d, clock), clock)),
          Container(
            height: t.property.dividerThickness,
            margin: EdgeInsets.symmetric(
              vertical: t.property.pickerDividerMargin,
            ),
            color: t.divider,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: t.property.pickerListMaxHeight,
            ),
            child: SingleChildScrollView(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: t.property.datePickerWidth,
                  child: FCalendar.grid(
                    key: Key('property-date-$id-calendar'),
                    selectionControl: FDateSelectionControl.managedSingle(
                      initial: value,
                      onChange: (d) {
                        if (d != null) {
                          onPick(DateTime.utc(d.year, d.month, d.day));
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          PickerRow(
            key: Key('property-date-$id-clear'),
            label: 'Clear',
            icon: FLucideIcons.x,
            selected: value == null,
            onPress: () => onPick(null),
          ),
        ],
      ),
    );
  }
}
