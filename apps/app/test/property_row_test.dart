import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/card_box.dart';
import 'package:davdart_app/ui/property/property_row.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/gestures.dart';
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
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  group('PropertyRow', () {
    testWidgets('wide: the property row height, label and value', (t) async {
      var taps = 0;
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(
              key: Key('row'),
              icon: FLucideIcons.calendar,
              label: 'due',
              text: 'Today',
              interactive: true,
              onTap: () => taps++,
            ),
          ],
        ),
      );
      expect(t.getSize(_k('row')).height, _tokens.sizes.propertyRow);
      expect(find.text('due'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.calendar), findsOneWidget);
      // The label column keeps the meta width every detail block has had.
      expect(
        t
            .getSize(
              find
                  .ancestor(
                    of: find.text('due'),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .width,
        _tokens.sizes.metaLabel,
      );
      await t.tap(_k('row'));
      await t.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('narrow: rows are touch tall', (t) async {
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(
              key: Key('row'),
              icon: FLucideIcons.calendar,
              label: 'due',
            ),
          ],
        ),
        width: 390,
      );
      expect(t.getSize(_k('row')).height, _tokens.sizes.touchTarget);
    });

    testWidgets('an empty value shows the muted placeholder', (t) async {
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(
              key: Key('row'),
              icon: FLucideIcons.calendar,
              label: 'due',
            ),
          ],
        ),
      );
      final text = t.widget<Text>(find.text('—'));
      expect(text.style!.color, _tokens.muted);
    });

    testWidgets('a plain value takes the body style and the error colour', (
      t,
    ) async {
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(
              key: Key('row'),
              icon: FLucideIcons.flag,
              label: 'priority',
              text: 'medium',
              error: true,
            ),
          ],
        ),
      );
      final text = t.widget<Text>(find.text('medium'));
      expect(text.style!.color, _tokens.error);
      expect(text.style!.fontSize, _tokens.type.body);
    });

    testWidgets('a read-only row takes no tap and no chevron', (t) async {
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(
              key: Key('row'),
              icon: FLucideIcons.repeat,
              label: 'repeats',
              text: 'FREQ=WEEKLY',
              interactive: true,
              readOnly: true,
              onTap: () {},
            ),
          ],
        ),
      );
      expect(
        find.descendant(of: _k('row'), matching: find.byType(FTappable)),
        findsNothing,
      );
      final g = await t.startGesture(
        t.getCenter(_k('row')),
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      await g.moveBy(const Offset(4, 0));
      await t.pump();
      expect(find.byIcon(FLucideIcons.chevronRight), findsNothing);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('an interactive row shows a chevron on hover only', (t) async {
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(
              key: Key('row'),
              icon: FLucideIcons.calendar,
              label: 'due',
              text: 'Today',
              onTap: () {},
            ),
          ],
        ),
      );
      expect(find.byIcon(FLucideIcons.chevronRight), findsNothing);
      final g = await t.startGesture(
        t.getCenter(_k('row')),
        kind: PointerDeviceKind.mouse,
      );
      await t.pump();
      await g.moveBy(const Offset(4, 0));
      await t.pump();
      expect(find.byIcon(FLucideIcons.chevronRight), findsOneWidget);
      await g.up();
      await t.pumpAndSettle();
    });

    testWidgets('the section is flat: no card, a divider between rows', (
      t,
    ) async {
      await _pump(
        t,
        PropertySection(
          rows: [
            PropertyRow(icon: FLucideIcons.circle, label: 'a', text: 'x'),
            PropertyRow(icon: FLucideIcons.circle, label: 'b', text: 'y'),
          ],
        ),
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      // Rows sit straight on the page: no card around them.
      expect(find.byType(CardBox), findsNothing);
      // One hairline between the two rows.
      expect(
        find.descendant(
          of: find.byType(PropertySection),
          matching: find.byType(PropertyDivider),
        ),
        findsOneWidget,
      );
    });
  });
}
