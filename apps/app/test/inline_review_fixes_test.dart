import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/theme/tokens.dart';
import 'package:davdart_app/ui/note_inline.dart';
import 'package:davdart_app/ui/property/tag_property_picker.dart';
import 'package:davdart_app/ui/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'tasks_helper.dart' show SeedNotes;

Finder _k(String k) => find.byKey(Key(k));

Finder get _field => _k('inline-text-field');

const _tokens = Tokens.light;

/// A note source whose saves wait for [gate] and can [fail]: a write in
/// flight, and one that does not go through.
class _GatedSource extends SpaceNoteSource {
  _GatedSource(super.space, {super.seed});
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<Note> save(Note note) async {
    await gate?.future;
    if (fail) throw StateError('offline');
    return super.save(note);
  }
}

/// A loaded state over one note [uid] whose body is [text].
Future<(AppState, _GatedSource)> _state({
  String uid = 'p',
  String text = 'Alpha',
}) async {
  final src = _GatedSource(
    Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore()),
    seed: SeedNotes([
      Note(uid: uid, summary: 'Alpha project', description: text),
    ]),
  );
  final s = AppState(src);
  await s.load();
  return (s, src);
}

/// Pumps the project About field of note [uid], rebuilding as the state does.
Future<void> _pumpAbout(
  WidgetTester t,
  AppState s, {
  String uid = 'p',
  bool focusAtTop = false,
}) async {
  t.view.physicalSize = const Size(1000, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    FTheme(
      data: buildTheme(Brightness.light, touch: false),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(1000, 800)),
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) => Align(
              alignment: .topLeft,
              child: SizedBox(
                width: 1000,
                child: NoteInlineText(
                  key: const Key('about'),
                  state: s,
                  uid: uid,
                  multiline: true,
                  textKey: const Key('about-text'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  if (focusAtTop) {
    await t.tap(_k('about'));
    await t.pumpAndSettle();
  }
}

String _body(AppState s, String uid) =>
    PlanItem.fromNote(s.tree.find(uid)!.note).text;

void main() {
  group('a note field typed in place', () {
    testWidgets('a change from elsewhere leaves what is being typed', (
      t,
    ) async {
      final (s, _) = await _state();
      await _pumpAbout(t, s, focusAtTop: true);
      await t.enterText(_field, 'Typed here');
      await t.pump();
      // A sync brings a merged body while the field is being typed in.
      await t.runAsync(() => s.updateNote('p', text: 'Merged elsewhere'));
      await t.pump();
      expect(t.widget<EditableText>(_field).controller.text, 'Typed here');
      // The pause writes what was typed, not what the merge brought.
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(_body(s, 'p'), 'Typed here');
      expect(t.widget<EditableText>(_field).controller.text, 'Typed here');
    });

    testWidgets('text typed during a write survives the reload it causes', (
      t,
    ) async {
      final (s, src) = await _state();
      await _pumpAbout(t, s, focusAtTop: true);
      // The write of the first text is held in flight.
      src.gate = Completer<void>();
      await t.enterText(_field, 'First');
      await t.pump(const Duration(milliseconds: 900));
      await t.enterText(_field, 'First, then more');
      await t.pump();
      // The reload the write causes puts its own text in the note: the field
      // keeps the newer text instead of taking it.
      src.gate!.complete();
      src.gate = null;
      await t.pump();
      await t.pump();
      expect(
        t.widget<EditableText>(_field).controller.text,
        'First, then more',
      );
      await t.pump(const Duration(milliseconds: 900));
      await t.pumpAndSettle();
      expect(_body(s, 'p'), 'First, then more');
    });

    testWidgets('a closed field follows the note', (t) async {
      final (s, _) = await _state();
      await _pumpAbout(t, s);
      expect(t.widget<Text>(_k('about-text')).data, 'Alpha');
      await t.runAsync(() => s.updateNote('p', text: 'From a sync'));
      await t.pumpAndSettle();
      expect(t.widget<Text>(_k('about-text')).data, 'From a sync');
    });
  });

  group('a note write that fails', () {
    test('setNoteText says so', () async {
      final (s, src) = await _state();
      src.fail = true;
      expect(await s.setNoteText('p', 'Nope'), isFalse);
      expect(s.error, isNotNull);
      expect(_body(s, 'p'), 'Alpha');
    });

    test('setNoteField says so', () async {
      final (s, src) = await _state();
      src.fail = true;
      expect(await s.setNoteField('p', 'lead', 'tm'), isFalse);
      expect(s.error, isNotNull);
      expect(s.tree.find('p')!.note.description, 'Alpha');
    });

    test('and a write that goes through says nothing', () async {
      final (s, _) = await _state();
      expect(await s.setNoteText('p', 'Written'), isTrue);
      expect(s.error, isNull);
      expect(_body(s, 'p'), 'Written');
    });

    testWidgets('a failed write keeps text typed while it ran', (t) async {
      final (s, src) = await _state();
      await _pumpAbout(t, s, focusAtTop: true);
      src.gate = Completer<void>();
      await t.enterText(_field, 'Nope');
      await t.pump(const Duration(milliseconds: 900));
      // Typed while the write runs, then the write does not go through.
      await t.enterText(_field, 'Nope, then more');
      src.fail = true;
      src.gate!.complete();
      await t.pumpAndSettle();
      expect(_body(s, 'p'), 'Alpha');
      // What was typed is kept, coloured as the failure it is.
      expect(t.widget<EditableText>(_field).controller.text, 'Nope, then more');
      expect(t.widget<EditableText>(_field).style.color, _tokens.error);
    });
  });

  group('the labels picker', () {
    testWidgets('two quick toggles both land', (t) async {
      final picks = <List<String>>[];
      final gate = Completer<bool>();
      t.view.physicalSize = const Size(500, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        FTheme(
          data: buildTheme(Brightness.light, touch: false),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: const MediaQueryData(size: Size(500, 800)),
              child: Align(
                alignment: .topLeft,
                child: SizedBox(
                  width: 500,
                  child: TagPropertyPicker(
                    id: 'tags',
                    value: const ['home'],
                    suggestions: const ['bills'],
                    onPick: (tags) {
                      picks.add(tags);
                      // The first pick is still being written when the second
                      // tap lands.
                      return picks.length == 1
                          ? gate.future
                          : Future.value(true);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(_k('property-tag-tags-home'));
      await t.pump();
      await t.tap(_k('property-tag-tags-bills'));
      await t.pump();
      // The second toggle builds on the first, not on the labels the item
      // still shows: home goes, bills comes in.
      expect(picks, [
        <String>[],
        ['bills'],
      ]);
      gate.complete(true);
      await t.pumpAndSettle();
    });
  });
}
