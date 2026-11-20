import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/key_value_storage.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:davdart_app/ui/app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class SeedNotes implements NoteSource {
  SeedNotes(this.notes);
  final List<Note> notes;
  @override
  Future<List<Note>> load() async => notes;
}

/// An app state whose tasks can be switched read-only.
class FlagState extends AppState {
  FlagState(super.source, {super.prefs, this.readOnly = false});
  bool readOnly;
  @override
  bool get tasksEditable => !readOnly && super.tasksEditable;
}

/// The ICalDate of the local day [days] from today.
ICalDate dueIn(int days) {
  final n = DateTime.now().add(Duration(days: days));
  return ICalDate.date(n.year, n.month, n.day);
}

Task mkTask(
  String uid, {
  String? summary,
  int? days,
  String? rrule,
  List<String> tags = const [],
  String? parent,
  String status = 'NEEDS-ACTION',
  int? priority,
  String description = '',
}) => Task(
  uid: uid,
  summary: summary ?? uid,
  due: days == null ? null : dueIn(days),
  rrule: rrule,
  categories: tags,
  parentUid: parent,
  status: status,
  priority: priority,
  description: description,
  lastModified: DateTime.now().toUtc(),
);

/// Pumps the app on a Space holding [notes] and [tasks].
Future<AppState> pumpTasksApp(
  WidgetTester t, {
  List<Note> notes = const [],
  List<Task> tasks = const [],
  Size size = const Size(1280, 900),
  MemoryStorage? prefs,
  bool readOnly = false,
  Space? into,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final space =
      into ?? Space(SpaceConfig(id: 's', name: 'S'), MemoryNoteStore());
  final src = SpaceNoteSource(space, seed: SeedNotes(notes));
  await t.runAsync(() async {
    for (final k in tasks) {
      await src.saveTask(k);
    }
  });
  final s = FlagState(src, prefs: prefs ?? MemoryStorage(), readOnly: readOnly);
  await t.pumpWidget(DavdartApp(state: s));
  await t.pumpAndSettle();
  return s;
}
