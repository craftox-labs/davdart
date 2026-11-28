import 'package:davdart/davdart.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/property/date_property_picker.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Finder _k(String k) => find.byKey(Key(k));

const _tokens = Tokens.light;

Future<void> _pump(WidgetTester t, Widget child, {double width = 1000}) async {
  t.view.physicalSize = Size(width, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    FTheme(
      data: buildTheme(Brightness.light, touch: false),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

DateTime _day(int days) {
  final n = DateTime.now().add(Duration(days: days));
  return DateTime.utc(n.year, n.month, n.day);
}

void main() {
  setUp(() => LocalZone.use('Asia/Bangkok'));
  tearDown(() => LocalZone.use(null));

  group('DatePropertyPicker', () {
    testWidgets('the relative days, then the week, a calendar and Clear', (
      t,
    ) async {
      await _pump(t, DatePropertyPicker(id: 'due', onPick: (_) {}));
      for (final (key, label) in [
        ('yesterday', 'Yesterday'),
        ('today', 'Today'),
        ('tomorrow', 'Tomorrow'),
      ]) {
        expect(_k('property-date-due-$key'), findsOneWidget);
        expect(
          find.descendant(
            of: _k('property-date-due-$key'),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      // The next seven days, each worded like an event's day.
      for (var d = 2; d <= 8; d++) {
        expect(_k('property-date-due-$d'), findsOneWidget);
      }
      expect(_k('property-date-due-calendar'), findsOneWidget);
      expect(find.byType(FCalendar), findsOneWidget);
      expect(_k('property-date-due-clear'), findsOneWidget);
      t.takeException(); // the test font overflows the calendar header
    });

    testWidgets('a day row picks that day; Clear picks null', (t) async {
      final picked = <DateTime?>[];
      await _pump(t, DatePropertyPicker(id: 'due', onPick: picked.add));
      await t.tap(_k('property-date-due-tomorrow'));
      await t.pumpAndSettle();
      expect(picked, [_day(1)]);
      await t.tap(_k('property-date-due-clear'));
      await t.pumpAndSettle();
      expect(picked.last, isNull);
      t.takeException();
    });

    testWidgets('the picked day is checked', (t) async {
      await _pump(
        t,
        DatePropertyPicker(id: 'due', value: _day(0), onPick: (_) {}),
      );
      expect(
        find.descendant(
          of: _k('property-date-due-today'),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _k('property-date-due-tomorrow'),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsNothing,
      );
      t.takeException();
    });

    testWidgets('rows are touch tall', (t) async {
      await _pump(t, DatePropertyPicker(id: 'due', onPick: (_) {}));
      expect(
        t.getSize(_k('property-date-due-today')).height,
        _tokens.sizes.touchTarget,
      );
      t.takeException();
    });
  });
}
