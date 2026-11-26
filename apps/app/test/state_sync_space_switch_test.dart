import 'dart:async';

import 'package:davdart/davdart.dart';
import 'package:davdart_app/data/note_source.dart';
import 'package:davdart_app/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// A connected source whose task and event loads wait on a gate.
class _GatedSource extends SpaceNoteSource {
  _GatedSource(super.space);
  final taskGate = Completer<void>();
  final eventGate = Completer<void>();
  bool failTasks = false;
  @override
  bool get connected => true;
  @override
  Future<SyncReport?> sync() async => null;
  @override
  Future<SyncReport?> syncTasks() async => null;
  @override
  Future<SyncReport?> syncEvents() async => null;
  @override
  Future<List<Task>> loadTasks() async {
    await taskGate.future;
    if (failTasks) throw StateError('late failure');
    return [Task(uid: 'a-task', summary: 'From A')];
  }

  @override
  Future<List<Event>> loadEvents() async {
    await eventGate.future;
    return [
      Event(
        uid: 'a-event',
        summary: 'From A',
        dtstart: ICalDate('20261120T100000Z', ''),
      ),
    ];
  }
}

SpaceNoteSource _plain() =>
    SpaceNoteSource(Space(SpaceConfig(id: 'b', name: 'B'), MemoryNoteStore()));

void main() {
  test('a sync that finishes after a Space switch drops its results', () async {
    final a = _GatedSource(
      Space(SpaceConfig(id: 'a', name: 'A'), MemoryNoteStore()),
    );
    final s = AppState(a);
    final run = s.sync();
    await Future<void>.delayed(Duration.zero);
    final b = _plain();
    s.source = b;
    s.tasks = [];
    a.taskGate.complete();
    a.eventGate.complete();
    await run;
    expect(s.tasks, isEmpty);
    expect(s.events, isEmpty);
    expect(s.syncing, isTrue); // the abandoned run left B's state alone
  });

  test('a failed task read after a Space switch leaves B untouched', () async {
    final a = _GatedSource(
      Space(SpaceConfig(id: 'a', name: 'A'), MemoryNoteStore()),
    )..failTasks = true;
    final s = AppState(a);
    final run = s.sync();
    await Future<void>.delayed(Duration.zero);
    s.source = _plain();
    a.taskGate.complete();
    a.eventGate.complete();
    await run;
    expect(s.taskError, isNull);
    expect(s.tasks, isEmpty);
  });
}
