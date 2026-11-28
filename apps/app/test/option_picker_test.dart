import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/popover_track.dart';
import 'package:davdart_app/ui/chips.dart';
import 'package:davdart_app/ui/property/option_picker.dart';
import 'package:davdart_app/ui/property/property_trigger.dart';
import 'package:davdart_app/ui/property/property_row.dart';
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
          child: Navigator(
            onGenerateRoute: (settings) => PageRouteBuilder<void>(
              pageBuilder: (context, _, _) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// A status picker for a task in the given state.
Widget _statusPicker({String? value, ValueChanged<String?>? onPick}) =>
    OptionPicker<String>(
      id: 'status',
      value: value,
      onPick: onPick ?? (_) {},
      options: const [
        PickerOption('backlog', 'backlog', dot: 'backlog'),
        PickerOption('todo', 'needs-action', dot: 'todo'),
        PickerOption('done', 'completed', dot: 'done', enabled: false),
      ],
    );

void main() {
  group('OptionPicker', () {
    testWidgets('one 44 high row per option, a check on the selected one', (
      t,
    ) async {
      await _pump(t, _statusPicker(value: 'todo'));
      expect(_k('property-option-status-backlog'), findsOneWidget);
      expect(_k('property-option-status-todo'), findsOneWidget);
      expect(
        t.getSize(_k('property-option-status-todo')).height,
        _tokens.sizes.touchTarget,
      );
      expect(find.text('needs-action'), findsOneWidget);
      // The check sits on the selected row only.
      expect(
        find.descendant(
          of: _k('property-option-status-todo'),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _k('property-option-status-backlog'),
          matching: find.byIcon(FLucideIcons.check),
        ),
        findsNothing,
      );
      // Every row carries its status dot.
      expect(find.byType(StatusDot), findsNWidgets(3));
    });

    testWidgets('a row picks its value; a disabled row does not', (t) async {
      final picked = <String?>[];
      await _pump(t, _statusPicker(value: 'todo', onPick: picked.add));
      await t.tap(_k('property-option-status-backlog'));
      await t.pumpAndSettle();
      expect(picked, ['backlog']);
      await t.tap(_k('property-option-status-done'));
      await t.pumpAndSettle();
      expect(picked, ['backlog']);
    });

    testWidgets('clearable adds a Clear row that picks null', (t) async {
      final picked = <String?>[];
      await _pump(
        t,
        OptionPicker<String>(
          id: 'priority',
          value: 'high',
          onPick: picked.add,
          clearable: true,
          options: const [
            PickerOption('high', 'high'),
            PickerOption('low', 'low'),
          ],
        ),
      );
      expect(_k('property-option-priority-clear'), findsOneWidget);
      await t.tap(_k('property-option-priority-clear'));
      await t.pumpAndSettle();
      expect(picked, [null]);
    });
  });

  group('PropertyTrigger', () {
    testWidgets('a row opens the picker and a pick closes it', (t) async {
      final picked = <String?>[];
      await _pump(
        t,
        PropertyTrigger(
          sheetKey: Key('property-sheet-status'),
          picker: (context, control) => OptionPicker<String>(
            id: 'status',
            value: 'todo',
            onPick: (v) {
              control.hide();
              picked.add(v);
            },
            options: const [
              PickerOption('todo', 'needs-action'),
              PickerOption('doing', 'in-process'),
            ],
          ),
          child: const PropertyRow(
            key: Key('property-status'),
            icon: FLucideIcons.circleDot,
            label: 'status',
            text: 'needs-action',
            interactive: true,
          ),
        ),
      );
      expect(_k('property-option-status-doing'), findsNothing);
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      expect(_k('property-option-status-doing'), findsOneWidget);
      await t.tap(_k('property-option-status-doing'));
      await t.pumpAndSettle();
      expect(picked, ['doing']);
      expect(_k('property-option-status-doing'), findsNothing);
    });

    testWidgets('Esc closes the picker, not the page', (t) async {
      await _pump(
        t,
        PropertyTrigger(
          picker: (context, control) => _statusPicker(value: 'todo'),
          child: const PropertyRow(
            key: Key('property-status'),
            icon: FLucideIcons.circleDot,
            label: 'status',
            text: 'needs-action',
            interactive: true,
          ),
        ),
      );
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      expect(find.byType(OptionPicker<String>), findsOneWidget);
      // Tracked, so the app's Esc (PopoverTracker.dismiss) closes it first.
      expect(popoverOpen(), isTrue);
      expect(PopoverTracker.instance.dismiss(), isTrue);
      await t.pumpAndSettle();
      expect(find.byType(OptionPicker<String>), findsNothing);
      expect(popoverOpen(), isFalse);
      expect(_k('property-status'), findsOneWidget);
    });

    testWidgets('narrow: the same picker shows in a sheet', (t) async {
      await _pump(
        t,
        PropertyTrigger(
          sheetKey: Key('property-sheet-status'),
          picker: (context, control) => _statusPicker(value: 'todo'),
          child: const PropertyRow(
            key: Key('property-status'),
            icon: FLucideIcons.circleDot,
            label: 'status',
            text: 'needs-action',
            interactive: true,
          ),
        ),
        width: 390,
      );
      await t.tap(_k('property-status'));
      await t.pumpAndSettle();
      expect(_k('property-sheet-status'), findsOneWidget);
      // The sheet holds the same rows.
      expect(_k('property-option-status-todo'), findsOneWidget);
    });
  });
}
