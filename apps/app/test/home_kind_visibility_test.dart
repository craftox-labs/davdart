import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_helper.dart';

class _NoTasks extends FlagState {
  _NoTasks(super.source);
  @override
  bool get supportsTasks => false;
}

class _NoNotes extends FlagState {
  _NoNotes(super.source);
  @override
  bool get supportsNotes => false;
}

Finder _k(String k) => find.byKey(Key(k));

Future<AppState> _pump(
  WidgetTester t,
  AppState Function(NoteSource src) make,
) async {
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  AppState.debugDefaultFocus = HomeFocus.board;
  addTearDown(() => AppState.debugDefaultFocus = HomeFocus.day);
  final space = Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final s = make(SpaceNoteSource(space, seed: SeedNotes(const [])));
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('a Space with notes and tasks shows the kind filter', (t) async {
    await _pump(t, (src) => FlagState(src));
    expect(_k('home-kind'), findsOneWidget);
  });

  testWidgets('a Space without notes has no kind filter', (t) async {
    final s = await _pump(t, (src) => _NoNotes(src));
    expect(_k('home-kind'), findsNothing);
    expect(s.homeKind, HomeKind.all);
  });

  testWidgets('a Space without tasks has no kind filter', (t) async {
    final s = await _pump(t, (src) => _NoTasks(src));
    expect(_k('home-kind'), findsNothing);
    expect(s.homeKind, HomeKind.all);
  });
}
