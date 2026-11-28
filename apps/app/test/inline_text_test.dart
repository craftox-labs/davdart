import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/property/inline_text.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Finder _k(String k) => find.byKey(Key(k));

Finder get _field => _k('inline-text-field');

const _tokens = Tokens.light;

/// A host for one InlineText: the commits it made and the controller.
class _Host {
  _Host(this.text, {this.multiline = false, bool Function(String)? accept})
    : controller = TextEditingController(text: text) {
    accept = accept ?? (_) => true;
    this.accept = accept;
  }
  final String text;
  final bool multiline;
  final TextEditingController controller;
  late final bool Function(String) accept;
  final commits = <String>[];

  Future<bool> commit(String text) async {
    if (!accept(text)) return false;
    commits.add(text);
    return true;
  }

  Widget widget() => InlineText(
    key: const Key('subject'),
    controller: controller,
    onCommit: commit,
    multiline: multiline,
    placeholder: 'Nothing here',
  );
}

Future<_Host> _pump(
  WidgetTester t, {
  String text = 'Alpha',
  bool multiline = false,
  bool Function(String)? accept,
  double width = 1000,
}) async {
  final h = _Host(text, multiline: multiline, accept: accept);
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
            child: SizedBox(width: width, child: h.widget()),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return h;
}

/// Taps the value so the field opens.
Future<void> _open(WidgetTester t) async {
  await t.tap(_k('subject'));
  await t.pumpAndSettle();
}

void main() {
  group('InlineText', () {
    testWidgets('the value is plain text until it is tapped', (t) async {
      await _pump(t);
      expect(find.text('Alpha'), findsOneWidget);
      expect(_field, findsNothing);
      await _open(t);
      expect(_field, findsOneWidget);
      // The field holds what the value showed.
      expect(t.widget<EditableText>(_field).controller.text, 'Alpha');
    });

    testWidgets('typing commits after the 800 ms pause, not before', (t) async {
      final h = await _pump(t);
      await _open(t);
      await t.enterText(_field, 'Alpha 2');
      await t.pump(const Duration(milliseconds: 700));
      expect(h.commits, isEmpty);
      await t.pump(const Duration(milliseconds: 200));
      await t.pumpAndSettle();
      expect(h.commits, ['Alpha 2']);
    });

    testWidgets('a blur commits at once', (t) async {
      final h = await _pump(t);
      await _open(t);
      await t.enterText(_field, 'Beta');
      // Focus goes to the other field: the first commits its text.
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      expect(h.commits, ['Beta']);
      expect(_field, findsNothing);
    });

    testWidgets('Esc reverts the field to the last saved text', (t) async {
      final h = await _pump(t);
      await _open(t);
      await t.enterText(_field, 'Half typed');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(h.commits, isEmpty);
      expect(h.controller.text, 'Alpha');
      expect(find.text('Alpha'), findsOneWidget);
      expect(_field, findsNothing);
    });

    testWidgets('Esc after a commit reverts to what was saved', (t) async {
      final h = await _pump(t);
      await _open(t);
      await t.enterText(_field, 'Saved once');
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(h.commits, ['Saved once']);
      await t.enterText(_field, 'Saved once, then more');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(h.commits, ['Saved once']);
      expect(h.controller.text, 'Saved once');
    });

    testWidgets('Enter commits a one-line value and closes the field', (
      t,
    ) async {
      final h = await _pump(t);
      await _open(t);
      await t.enterText(_field, 'Entered');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(h.commits, ['Entered']);
      expect(_field, findsNothing);
    });

    testWidgets('a commit that fails puts the saved text back', (t) async {
      final h = await _pump(t, accept: (_) => false);
      await _open(t);
      await t.enterText(_field, 'Not allowed');
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(h.commits, isEmpty);
      // The field is still open, showing the saved text in the error colour.
      expect(h.controller.text, 'Alpha');
      expect(t.widget<EditableText>(_field).style.color, _tokens.error);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
    });

    testWidgets('an empty value shows the muted placeholder', (t) async {
      await _pump(t, text: '');
      final text = t.widget<Text>(find.text('Nothing here'));
      expect(text.style!.color, _tokens.muted);
    });

    testWidgets('a sync change while the field is closed shows, not commits', (
      t,
    ) async {
      final h = await _pump(t);
      h.controller.text = 'From the server';
      await t.pumpAndSettle();
      expect(find.text('From the server'), findsOneWidget);
      expect(h.commits, isEmpty);
    });

    testWidgets('multiline keeps Enter as a new line and uses the preview', (
      t,
    ) async {
      final h = await _pump(t, text: 'Body', multiline: true);
      // Unfocused: a preview builder draws the value.
      expect(find.text('Body'), findsOneWidget);
      await _open(t);
      await t.enterText(_field, 'Line one\nLine two');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(h.commits, isEmpty);
      expect(_field, findsOneWidget);
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(h.commits, ['Line one\nLine two']);
    });

    testWidgets('a read-only value never becomes a field', (t) async {
      t.view.physicalSize = const Size(1000, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final controller = TextEditingController(text: 'Fixed');
      addTearDown(controller.dispose);
      await t.pumpWidget(
        FTheme(
          data: buildTheme(Brightness.light, touch: false),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: InlineText(
                key: const Key('subject'),
                controller: controller,
                readOnly: true,
                onCommit: (_) async => true,
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(_k('subject'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(_field, findsNothing);
      expect(find.text('Fixed'), findsOneWidget);
    });
  });
}
