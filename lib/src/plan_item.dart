import 'note.dart';
import 'status.dart';

final _headerLine = RegExp(r'^([a-z][a-z0-9_]*):[ \t]*(.*)$');

/// A planning item: a [Note] whose body opens with `key: value` header lines
/// (item_id, status, owner, decided_by, github_ref, created, updated), a blank
/// line, then free text. Notes without such a header are still valid items
/// with no fields.
///
/// Header order and unknown keys are preserved on [toDescription].
class PlanItem {
  PlanItem._(this.note, this.fields, this.text);

  /// Reads the header out of [note].description. The note is not modified
  /// until [apply] is called.
  factory PlanItem.fromNote(Note note) {
    final lines = note.description.split('\n');
    final fields = <String, String>{};
    var i = 0;
    while (i < lines.length) {
      final m = _headerLine.firstMatch(lines[i]);
      if (m == null) break;
      fields[m.group(1)!] = m.group(2)!.trimRight();
      i++;
    }
    // A header only counts when it ends at a blank line or the end of the body.
    final valid =
        fields.isNotEmpty && (i == lines.length || lines[i].trim().isEmpty);
    if (!valid) return PlanItem._(note, <String, String>{}, note.description);
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    return PlanItem._(note, fields, lines.sublist(i).join('\n'));
  }

  final Note note;

  /// Header fields in file order.
  final Map<String, String> fields;

  /// Free text after the header.
  String text;

  String? get itemId => fields['item_id'];
  String? get owner => fields['owner'];
  String? get decidedBy => fields['decided_by'];
  String? get githubRef => fields['github_ref'];
  String? get created => fields['created'];
  String? get updated => fields['updated'];

  /// Priority word (`high`, `medium`, `low`) of the `priority` field, or null.
  String? get priorityWord {
    final v = fields['priority']?.trim().split(RegExp(r'[\s(;,]')).first;
    final w = v?.toLowerCase();
    return notePriorities.containsKey(w) ? w : null;
  }

  /// The priority as a task-style number (1, 5 or 9), or null.
  int? get priority => notePriorities[priorityWord];

  /// Sets the `priority` field to [word] (`high`, `medium`, `low`); null
  /// removes it.
  void setPriority(String? word) {
    if (word == null) {
      fields.remove('priority');
    } else {
      fields['priority'] = word;
    }
  }

  /// Raw status line, for example `backlog (proposed; tm's go moves it)`.
  String? get statusLine => fields['status'];

  /// Status word: the first token of the `status` field, else the value of a
  /// `status-*` category tag, else null.
  String? get status {
    final line = statusLine;
    if (line != null && line.trim().isNotEmpty) {
      return line.trim().split(RegExp(r'[\s(;,]')).first.toLowerCase();
    }
    for (final c in note.categories) {
      if (c.startsWith('status-')) return c.substring(7);
    }
    return null;
  }

  String get title => note.summary;
  List<String> get tags => note.categories;

  void setField(String key, String value) => fields[key] = value;

  /// Sets the status field and keeps the `status-*` tag in step.
  void setStatus(String value) {
    fields['status'] = value;
    final word = value.trim().split(RegExp(r'[\s(;,]')).first.toLowerCase();
    note.categories
      ..removeWhere((c) => c.startsWith('status-'))
      ..add('status-$word');
  }

  /// Removes the status field and every `status-*` tag.
  void clearStatus() {
    fields.remove('status');
    note.categories.removeWhere((c) => c.startsWith('status-'));
  }

  /// The body text: header lines, a blank line, then [text].
  String toDescription() {
    if (fields.isEmpty) return text;
    final head = fields.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return text.isEmpty ? head : '$head\n\n$text';
  }

  /// Writes [toDescription] back to the note and returns it.
  Note apply() {
    note.description = toDescription();
    return note;
  }
}
