import 'package:davdart/davdart.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/markdown_lite.dart';
import 'package:davdart_app/ui/parts.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart';

Finder _k(String key) => find.byKey(Key(key));

/// Every tappable link span in the tree, in order.
List<TextSpan> _links(WidgetTester t) {
  final found = <TextSpan>[];
  for (final w in t.widgetList<RichText>(find.byType(RichText))) {
    w.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) found.add(span);
      return true;
    });
  }
  return found;
}

/// Pumps [child] on its own, with the app's theme and tokens and the overlay
/// a selection region needs.
Future<void> _pump(WidgetTester t, Widget child) async {
  final tk = Tokens.light;
  await t.pumpWidget(
    FTheme(
      data: buildTheme(Brightness.light, touch: false, tokens: tk),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: TokensScope(
          tokens: tk,
          child: Overlay(
            initialEntries: [
              OverlayEntry(builder: (_) => SingleChildScrollView(child: child)),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('urlsIn', () {
    test('finds http and https links, in order', () {
      expect(urlsIn('see http://a.test/x and HTTPS://b.test/y?q=1 for more'), [
        'http://a.test/x',
        'HTTPS://b.test/y?q=1',
      ]);
    });

    test('drops trailing punctuation and an unopened bracket', () {
      expect(urlsIn('go to http://a.test/x.'), ['http://a.test/x']);
      expect(urlsIn('(see http://a.test/x)'), ['http://a.test/x']);
      expect(urlsIn('"http://a.test/x",'), ['http://a.test/x']);
      expect(urlsIn('http://a.test/x?a=1&b=2;'), ['http://a.test/x?a=1&b=2']);
    });

    test('keeps a bracket the link opens itself', () {
      expect(urlsIn('http://a.test/x_(y)'), ['http://a.test/x_(y)']);
      expect(urlsIn('http://a.test/x_(y)).'), ['http://a.test/x_(y)']);
    });

    test('ignores other schemes, a bare host and a scheme alone', () {
      expect(urlsIn('mailto:tm@a.test ftp://a.test/x a.test www.a.test'), []);
      expect(urlsIn('nothing to see'), []);
      expect(urlsIn('http://.'), []);
    });

    test('keeps a port and a fragment', () {
      expect(urlsIn('http://a.test:8080/x#frag'), [
        'http://a.test:8080/x#frag',
      ]);
    });
  });

  group('MarkdownLite', () {
    testWidgets('a link is underlined and opens outside the app', (t) async {
      final opened = <String>[];
      await _pump(
        t,
        MarkdownLite('read http://a.test/x.', onOpenUrl: opened.add),
      );
      final span = _links(t).single;
      expect(span.text, 'http://a.test/x');
      expect(span.style?.decoration, TextDecoration.underline);
      (span.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, ['http://a.test/x']);
    });

    testWidgets('plain text and a link stay one paragraph', (t) async {
      await _pump(t, MarkdownLite('before http://a.test/x after'));
      expect(
        find.text('before http://a.test/x after', findRichText: true),
        findsOneWidget,
      );
      expect(_links(t), hasLength(1));
    });

    testWidgets('no link span without a link', (t) async {
      await _pump(t, MarkdownLite('**bold** and `code` only'));
      expect(_links(t), isEmpty);
    });

    testWidgets('a link in **bold** or `code` stays plain text', (t) async {
      await _pump(t, MarkdownLite('**http://a.test/x** `http://b.test/y`'));
      expect(_links(t), isEmpty);
      expect(
        find.text('http://a.test/x http://b.test/y', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a heading and a list row keep their links', (t) async {
      await _pump(
        t,
        MarkdownLite('# Head http://a.test/h\n- row http://b.test/r'),
      );
      expect(_links(t).map((s) => s.text), [
        'http://a.test/h',
        'http://b.test/r',
      ]);
    });
  });

  group('SelectableBody', () {
    testWidgets('wraps text in a selection region when enabled', (t) async {
      await _pump(t, const SelectableBody(child: Text('words')));
      expect(find.byType(SelectableRegion), findsOneWidget);
    });

    testWidgets('leaves an editor alone when off', (t) async {
      await _pump(
        t,
        const SelectableBody(enabled: false, child: Text('words')),
      );
      expect(find.byType(SelectableRegion), findsNothing);
    });
  });

  group('read view', () {
    testWidgets('a note body is selectable and its link is a link', (t) async {
      final s = await pumpTasksApp(
        t,
        notes: [
          Note(
            uid: 'n',
            summary: 'A note',
            description: 'read http://a.test/x',
          ),
        ],
      );
      await s.openNote('n');
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.text('read http://a.test/x', findRichText: true),
          matching: find.byType(SelectableRegion),
        ),
        findsWidgets,
      );
      final link = _links(t).firstWhere((s) => s.text == 'http://a.test/x');
      expect(link.recognizer, isA<TapGestureRecognizer>());
      await t.tap(_k('edit-note'));
      await t.pumpAndSettle();
      // While editing, the body is a field: no selection region of ours.
      expect(
        find.ancestor(
          of: find.text('read http://a.test/x', findRichText: true),
          matching: find.byType(SelectableRegion),
        ),
        findsNothing,
      );
    });
  });
}
