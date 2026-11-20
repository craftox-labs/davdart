import 'note.dart';
import 'plan_item.dart';
import 'task.dart';

/// One place where both sides changed the same lines (or the same scalar) to
/// different values. The merge picked [chosen]; the other side is kept here so
/// callers can store it as a revision instead of making a duplicate note.
class MergeConflict {
  MergeConflict(this.what, this.local, this.remote, this.chosen);
  final String what;
  final String local;
  final String remote;
  final String chosen;
  @override
  String toString() => 'MergeConflict($what)';
}

class _Hunk {
  _Hunk(this.start, this.end, this.lines);
  final int start; // base lines [start, end) are replaced by [lines]
  final int end;
  final List<String> lines;
}

/// Longest-common-subsequence diff of [a] to [b] as change hunks over [a].
List<_Hunk> _diff(List<String> a, List<String> b) {
  final n = a.length, m = b.length;
  final lcs = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final hunks = <_Hunk>[];
  var i = 0, j = 0;
  int? hs;
  final added = <String>[];
  void close(int end) {
    if (hs != null) {
      hunks.add(_Hunk(hs!, end, List.of(added)));
      hs = null;
      added.clear();
    }
  }

  while (i < n || j < m) {
    if (i < n && j < m && a[i] == b[j]) {
      close(i);
      i++;
      j++;
    } else if (j < m && (i == n || lcs[i][j + 1] >= lcs[i + 1][j])) {
      hs ??= i;
      added.add(b[j++]);
    } else {
      hs ??= i;
      i++;
    }
  }
  close(i);
  return hunks;
}

List<String> _apply(List<String> base, List<_Hunk> hunks, int from, int to) {
  final out = <String>[];
  var pos = from;
  for (final h in hunks.where((h) => h.start >= from && h.end <= to)) {
    out.addAll(base.sublist(pos, h.start));
    out.addAll(h.lines);
    pos = h.end;
  }
  out.addAll(base.sublist(pos, to));
  return out;
}

/// Result of a three-way text merge.
class TextMerge {
  TextMerge(this.text, this.conflicts);
  final String text;
  final List<MergeConflict> conflicts;
}

/// Three-way line merge of [local] and [remote] against their common [base].
/// Non-overlapping edits combine. Where both sides changed the same lines to
/// different text, [preferLocal] picks the winner for that stretch only.
TextMerge mergeText(String base, String local, String remote,
    {required bool preferLocal}) {
  if (local == remote) return TextMerge(local, []);
  if (local == base) return TextMerge(remote, []);
  if (remote == base) return TextMerge(local, []);
  final b = base.split('\n');
  final lh = _diff(b, local.split('\n'));
  final rh = _diff(b, remote.split('\n'));
  final all = [
    ...lh.map((h) => (h, true)),
    ...rh.map((h) => (h, false)),
  ]..sort((x, y) =>
      x.$1.start != y.$1.start ? x.$1.start - y.$1.start : x.$1.end - y.$1.end);
  final out = <String>[];
  final conflicts = <MergeConflict>[];
  var pos = 0;
  var k = 0;
  while (k < all.length) {
    var start = all[k].$1.start, end = all[k].$1.end;
    var l = [if (all[k].$2) all[k].$1], r = [if (!all[k].$2) all[k].$1];
    k++;
    var grew = true;
    while (grew) {
      grew = false;
      while (k < all.length && all[k].$1.start <= end) {
        final h = all[k];
        if (h.$1.end > end) end = h.$1.end;
        (h.$2 ? l : r).add(h.$1);
        k++;
        grew = true;
      }
    }
    out.addAll(b.sublist(pos, start));
    if (l.isEmpty || r.isEmpty) {
      out.addAll(_apply(b, l.isEmpty ? r : l, start, end));
    } else {
      final lt = _apply(b, l, start, end), rt = _apply(b, r, start, end);
      if (lt.join('\n') == rt.join('\n')) {
        out.addAll(lt);
      } else {
        final win = preferLocal ? lt : rt;
        conflicts.add(MergeConflict(
            'text', lt.join('\n'), rt.join('\n'), win.join('\n')));
        out.addAll(win);
      }
    }
    pos = end;
  }
  out.addAll(b.sublist(pos));
  return TextMerge(out.join('\n'), conflicts);
}

/// Merged note plus what had to be decided.
bool _sameMap(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

class NoteMerge {
  NoteMerge(this.note, this.conflicts);
  final Note note;
  final List<MergeConflict> conflicts;
  bool get hadConflict => conflicts.isNotEmpty;
}

/// Three-way merge of two edited copies of one note against [base], the copy
/// last synced. Merges title, tags (as sets), status, header fields (per key)
/// and body text (per line). On a true conflict the side with the later
/// lastModified wins that value only (ties go to [remote]); the losing value
/// is reported in [NoteMerge.conflicts] so it can be kept as a revision.
/// The result keeps [remote]'s href and etag, ready to PUT.
NoteMerge mergeNotes(Note base, Note local, Note remote) {
  final conflicts = <MergeConflict>[];
  final lm = local.lastModified, rm = remote.lastModified;
  final preferLocal = lm != null && (rm == null || lm.isAfter(rm));

  String scalar(String what, String b, String l, String r) {
    if (l == r) return l;
    if (l == b) return r;
    if (r == b) return l;
    final win = preferLocal ? l : r;
    conflicts.add(MergeConflict(what, l, r, win));
    return win;
  }

  String? nullable(String what, String? b, String? l, String? r) {
    if (l == r) return l;
    if (l == b) return r;
    if (r == b) return l;
    final win = preferLocal ? l : r;
    conflicts.add(MergeConflict(what, l ?? '', r ?? '', win ?? ''));
    return win;
  }

  bool sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  final bi = PlanItem.fromNote(base),
      li = PlanItem.fromNote(local),
      ri = PlanItem.fromNote(remote);

  final merged = remote.copyWith();
  merged.summary = scalar('title', base.summary, local.summary, remote.summary);
  merged.status = nullable('status', base.status, local.status, remote.status);
  merged.parentUid =
      nullable('parent', base.parentUid, local.parentUid, remote.parentUid);

  // Raw lines this core does not model: take the side that changed them; if
  // both did, the winner's copy.
  if (!sameList(local.extraLines, remote.extraLines)) {
    final pick = sameList(local.extraLines, base.extraLines)
        ? remote.extraLines
        : sameList(remote.extraLines, base.extraLines) || preferLocal
            ? local.extraLines
            : remote.extraLines;
    final copy = List.of(pick);
    merged.extraLines
      ..clear()
      ..addAll(copy);
  }
  if (!_sameMap(local.propertyParams, remote.propertyParams)) {
    final pick = _sameMap(local.propertyParams, base.propertyParams)
        ? remote.propertyParams
        : _sameMap(remote.propertyParams, base.propertyParams) || preferLocal
            ? local.propertyParams
            : remote.propertyParams;
    final copy = Map.of(pick);
    merged.propertyParams
      ..clear()
      ..addAll(copy);
  }

  // Tags as sets: a side's additions and removals both apply.
  final cats = <String>{...remote.categories};
  for (final c in local.categories) {
    if (!base.categories.contains(c)) cats.add(c);
  }
  for (final c in base.categories) {
    if (!local.categories.contains(c)) cats.remove(c);
  }
  merged.categories = [
    for (final c in [...remote.categories, ...local.categories])
      if (cats.remove(c)) c
  ];

  final fields = <String, String>{};
  final keys = {...ri.fields.keys, ...li.fields.keys, ...bi.fields.keys};
  for (final key in keys) {
    final b = bi.fields[key], l = li.fields[key], r = ri.fields[key];
    final String? v;
    if (l == r) {
      v = l;
    } else if (l == b) {
      v = r;
    } else if (r == b) {
      v = l;
    } else {
      v = preferLocal ? l : r;
      conflicts.add(MergeConflict('field:$key', l ?? '', r ?? '', v ?? ''));
    }
    if (v != null) fields[key] = v;
  }
  // Keep remote's key order, then keys only local added.
  final ordered = <String, String>{
    for (final k in [...ri.fields.keys, ...li.fields.keys])
      if (fields.containsKey(k)) k: fields[k]!,
  };

  final text = mergeText(bi.text, li.text, ri.text, preferLocal: preferLocal);
  conflicts.addAll(text.conflicts);

  final item = PlanItem.fromNote(merged);
  item.fields
    ..clear()
    ..addAll(ordered);
  item.text = text.text;
  item.apply();
  merged.lastModified = [lm, rm]
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, d) => a == null || d.isAfter(a) ? d : a);
  return NoteMerge(merged, conflicts);
}

/// Merged task plus what had to be decided.
class TaskMerge {
  TaskMerge(this.task, this.conflicts);
  final Task task;
  final List<MergeConflict> conflicts;
  bool get hadConflict => conflicts.isNotEmpty;
}

/// Three-way merge of two edited copies of one task against [base], the copy
/// last synced. Same policy as [mergeNotes]: each field (title, status,
/// percent, priority, due, start, completed, recurrence rule, parent) merges
/// on its own, tags as sets, the description per line. On a true conflict the
/// side with the later lastModified wins that field only (ties go to
/// [remote]) and the losing value is reported. Completion is kept consistent:
/// if the merged status is not COMPLETED, a COMPLETED timestamp is dropped.
/// The result keeps [remote]'s href and etag, ready to PUT.
TaskMerge mergeTasks(Task base, Task local, Task remote) {
  final conflicts = <MergeConflict>[];
  final lm = local.lastModified, rm = remote.lastModified;
  final preferLocal = lm != null && (rm == null || lm.isAfter(rm));

  T? pick<T>(String what, T? b, T? l, T? r, [String Function(T?)? show]) {
    if (l == r) return l;
    if (l == b) return r;
    if (r == b) return l;
    final win = preferLocal ? l : r;
    String s(T? v) => show != null ? show(v) : (v?.toString() ?? '');
    conflicts.add(MergeConflict(what, s(l), s(r), s(win)));
    return win;
  }

  bool sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

  final merged = remote.copyWith();
  merged.summary = pick('title', base.summary, local.summary, remote.summary)!;
  merged.status = pick('status', base.status, local.status, remote.status);
  merged.percentComplete = pick('percent', base.percentComplete,
      local.percentComplete, remote.percentComplete);
  merged.priority =
      pick('priority', base.priority, local.priority, remote.priority);
  merged.due = pick('due', base.due, local.due, remote.due);
  merged.dtstart = pick('start', base.dtstart, local.dtstart, remote.dtstart);
  merged.completed =
      pick('completed', base.completed, local.completed, remote.completed);
  merged.rrule = pick('repeat', base.rrule, local.rrule, remote.rrule);
  merged.parentUid =
      pick('parent', base.parentUid, local.parentUid, remote.parentUid);
  if (merged.status != 'COMPLETED') merged.completed = null;

  if (!sameList(local.extraLines, remote.extraLines)) {
    final src = sameList(local.extraLines, base.extraLines)
        ? remote.extraLines
        : sameList(remote.extraLines, base.extraLines) || preferLocal
            ? local.extraLines
            : remote.extraLines;
    final copy = List.of(src);
    merged.extraLines
      ..clear()
      ..addAll(copy);
  }
  if (!_sameMap(local.propertyParams, remote.propertyParams)) {
    final src = _sameMap(local.propertyParams, base.propertyParams)
        ? remote.propertyParams
        : _sameMap(remote.propertyParams, base.propertyParams) || preferLocal
            ? local.propertyParams
            : remote.propertyParams;
    final copy = Map.of(src);
    merged.propertyParams
      ..clear()
      ..addAll(copy);
  }

  final cats = <String>{...remote.categories};
  for (final c in local.categories) {
    if (!base.categories.contains(c)) cats.add(c);
  }
  for (final c in base.categories) {
    if (!local.categories.contains(c)) cats.remove(c);
  }
  merged.categories = [
    for (final c in [...remote.categories, ...local.categories])
      if (cats.remove(c)) c
  ];

  final text = mergeText(
      base.description, local.description, remote.description,
      preferLocal: preferLocal);
  conflicts.addAll(text.conflicts);
  merged.description = text.text;
  merged.lastModified = [lm, rm]
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, d) => a == null || d.isAfter(a) ? d : a);
  return TaskMerge(merged, conflicts);
}
