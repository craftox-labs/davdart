import 'note.dart';
import 'plan_item.dart';
import 'status.dart';
import 'task.dart';

/// One card of the unified Home Board: a note or a task with a status.
class BoardItem {
  BoardItem.note(Note n) : note = n, task = null;
  BoardItem.task(Task t) : task = t, note = null;

  final Note? note;
  final Task? task;

  bool get isTask => task != null;
  String get uid => isTask ? task!.uid : note!.uid;
  String get title => isTask ? task!.summary : note!.summary;

  /// High, medium, low or null; tasks are grouped from 1-9 for display and
  /// sorting only (1-4 high, 5 medium, 6-9 low, the existing buckets).
  String? get priorityWord => isTask
      ? priorityWordOf(task!.priority)
      : PlanItem.fromNote(note!).priorityWord;

  /// 0 high, 1 medium, 2 low, 3 unset.
  int get priorityRank => switch (priorityWord) {
    'high' => 0,
    'medium' => 1,
    'low' => 2,
    _ => 3,
  };

  /// The due wall-clock (tasks only; notes have none).
  DateTime? get due => task?.due?.localWall;

  /// Creation time; a missing CREATED is a fixed epoch, not DTSTAMP (which
  /// defaults to "now" on parse and would shuffle the order every sync).
  DateTime get created =>
      (isTask ? task!.created : note!.created) ?? DateTime.utc(1970);

  String get _uid => isTask ? task!.uid : note!.uid;

  DateTime? get lastModified =>
      isTask ? task!.lastModified : note!.lastModified;

  bool get canceled => isTask && task!.isCancelled;

  /// Manual order (X-DAVDART-RANK): a lower rank sorts first and ranked
  /// items sort before unranked ones.
  double? get rank => isTask ? task!.rank : note!.rank;
}

/// The order inside a column: manual rank, then priority
/// (high, medium, low, unset), then due date earliest first (undated after
/// dated), then creation oldest first, then title. Overdue does not jump the
/// queue. The done column is ordered by modified time in `boardCapped`.
int compareBoardItems(BoardItem a, BoardItem b) {
  final ra = a.rank, rb = b.rank;
  if (ra != null && rb != null) {
    final c = ra.compareTo(rb);
    if (c != 0) return c;
  } else if (ra != null) {
    return -1;
  } else if (rb != null) {
    return 1;
  }
  var c = a.priorityRank.compareTo(b.priorityRank);
  if (c != 0) return c;
  final da = a.due, db = b.due;
  if (da != null && db != null) {
    c = da.compareTo(db);
    if (c != 0) return c;
  } else if (da != null) {
    return -1;
  } else if (db != null) {
    return 1;
  }
  c = a.created.compareTo(b.created);
  if (c != 0) return c;
  c = a.title.compareTo(b.title);
  return c != 0 ? c : a._uid.compareTo(b._uid);
}
