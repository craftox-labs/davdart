import 'note.dart';

class ICalException implements Exception {
  ICalException(this.message);
  final String message;
  @override
  String toString() => 'ICalException: $message';
}

const _prodId = '-//davdart//EN';

/// Splits [text] into logical lines, undoing RFC 5545 folding.
List<String> unfold(String text) {
  final out = <String>[];
  for (final raw in text.split(RegExp(r'\r\n|\n|\r'))) {
    if (raw.isNotEmpty && (raw[0] == ' ' || raw[0] == '\t') && out.isNotEmpty) {
      out[out.length - 1] += raw.substring(1);
    } else {
      out.add(raw);
    }
  }
  return out.where((l) => l.isNotEmpty).toList();
}

/// Folds one logical line at 75 octets, never splitting a UTF-8 character.
String fold(String line) {
  final buf = StringBuffer();
  var octets = 0;
  var first = true;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = ch.codeUnits.length == 1 && rune < 0x80
        ? 1
        : rune < 0x800
            ? 2
            : rune < 0x10000
                ? 3
                : 4;
    final limit = first ? 75 : 74; // continuation lines start with a space
    if (octets + n > limit) {
      buf.write('\r\n ');
      octets = 0;
      first = false;
    }
    buf.write(ch);
    octets += n;
  }
  return buf.toString();
}

String escapeText(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(RegExp(r'\r\n|\n|\r'), r'\n');

String unescapeText(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final n = s[++i];
      b.write(n == 'n' || n == 'N' ? '\n' : n);
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

/// Splits a category list on unescaped commas.
List<String> _splitCommas(String s) {
  final parts = <String>[];
  final cur = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      cur
        ..write(c)
        ..write(s[++i]);
    } else if (c == ',') {
      parts.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  parts.add(cur.toString());
  return parts;
}

class _Prop {
  _Prop(this.name, this.params, this.value);
  final String name;
  final String params; // raw ";KEY=VAL..." text, may be empty
  final String value;
}

_Prop? _parseLine(String line) {
  // Name and params end at the first colon outside double quotes.
  var inQuote = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQuote = !inQuote;
    if (c == ':' && !inQuote) {
      colon = i;
      break;
    }
  }
  if (colon < 1) return null;
  final head = line.substring(0, colon);
  final semi = head.indexOf(';');
  final name = (semi < 0 ? head : head.substring(0, semi)).toUpperCase();
  final params = semi < 0 ? '' : head.substring(semi);
  return _Prop(name, params, line.substring(colon + 1));
}

DateTime _parseDateTime(String v) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$')
      .firstMatch(v.trim());
  if (m == null) throw ICalException('bad date-time "$v"');
  final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i) ?? '0')];
  return DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]);
}

String _formatDateTime(DateTime d) {
  final u = d.toUtc();
  String t(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${t(u.year, 4)}${t(u.month)}${t(u.day)}T'
      '${t(u.hour)}${t(u.minute)}${t(u.second)}Z';
}

final _utcStamp = RegExp(r'^\d{8}T\d{6}Z$');

class _Block {
  _Block(this.type, this.lines);
  final String type;
  final List<String> lines;
}

/// Top-level content of one VCALENDAR: its components and loose properties.
class _Calendar {
  final blocks = <_Block>[];
  final looseLines = <String>[]; // properties other than VERSION and PRODID
}

_Calendar _splitCalendar(String text) {
  final cal = _Calendar();
  var inCal = false;
  var depth = 0;
  _Block? cur;
  for (final line in unfold(text)) {
    final p = _parseLine(line);
    if (p == null) continue;
    if (depth == 0) {
      if (p.name == 'BEGIN') {
        final type = p.value.trim().toUpperCase();
        if (type == 'VCALENDAR' && !inCal) {
          inCal = true;
        } else if (inCal) {
          depth = 1;
          cur = _Block(type, [line]);
        }
      } else if (p.name == 'END') {
        if (p.value.trim().toUpperCase() == 'VCALENDAR') inCal = false;
      } else if (inCal && p.name != 'VERSION' && p.name != 'PRODID') {
        cal.looseLines.add(line);
      }
    } else {
      cur!.lines.add(line);
      if (p.name == 'BEGIN') depth++;
      if (p.name == 'END') {
        depth--;
        if (depth == 0) {
          cal.blocks.add(cur);
          cur = null;
        }
      }
    }
  }
  return cal;
}

/// Builds a Note from the lines of one VJOURNAL component (BEGIN..END).
Note _journalFromLines(List<String> lines) {
  String? uid, summary, description, status;
  DateTime? created, modified, stamp;
  final cats = <String>[];
  final extra = <String>[];
  final params = <String, String>{};
  var depth = 0;
  for (final line in lines.sublist(1, lines.length - 1)) {
    final p = _parseLine(line);
    if (p == null) continue;
    if (p.name == 'BEGIN') depth++;
    if (depth > 0) {
      extra.add(line);
      if (p.name == 'END') depth--;
      continue;
    }
    switch (p.name) {
      case 'UID':
        uid = p.value.trim();
      case 'SUMMARY':
        if (summary == null) {
          summary = unescapeText(p.value);
          if (p.params.isNotEmpty) params['SUMMARY'] = p.params;
        } else {
          extra.add(line);
        }
      case 'DESCRIPTION':
        if (description == null) {
          description = unescapeText(p.value);
          if (p.params.isNotEmpty) params['DESCRIPTION'] = p.params;
        } else {
          extra.add(line); // further DESCRIPTIONs stay as they were
        }
      case 'CATEGORIES':
        if (p.params.isNotEmpty) {
          extra.add(line);
        } else {
          for (final c in _splitCommas(p.value)) {
            final t = unescapeText(c).trim();
            if (t.isNotEmpty) cats.add(t);
          }
        }
      case 'STATUS':
        status = p.value.trim().toUpperCase();
      case 'CREATED' || 'LAST-MODIFIED':
        // Only plain UTC values are modelled. Anything else (TZID, floating,
        // date-only) is kept verbatim so a save cannot shift it.
        if (p.params.isEmpty && _utcStamp.hasMatch(p.value.trim())) {
          final d = _parseDateTime(p.value);
          if (p.name == 'CREATED') {
            created = d;
          } else {
            modified = d;
          }
        } else {
          extra.add(line);
        }
      case 'DTSTAMP':
        try {
          stamp = _parseDateTime(p.value);
        } on ICalException {
          // Malformed: a fresh stamp is written on save.
        }
      default:
        extra.add(line);
    }
  }
  if (uid == null || uid.isEmpty) throw ICalException('VJOURNAL without UID');
  return Note(
    uid: uid,
    summary: summary ?? '',
    description: description ?? '',
    categories: cats,
    status: status,
    created: created,
    lastModified: modified,
    dtstamp: stamp,
    extraLines: extra,
    propertyParams: params,
  );
}

/// Parses every VJOURNAL in an iCalendar document as its own Note. Other
/// components are ignored. Use [parseNote] for a CalDAV resource you intend to
/// write back.
List<Note> parseNotes(String text) => [
      for (final b in _splitCalendar(text).blocks)
        if (b.type == 'VJOURNAL') _journalFromLines(b.lines),
    ];

/// Parses one CalDAV resource into a single Note, keeping what a write-back
/// must not lose: other VJOURNALs of the same resource (recurrence overrides)
/// in [Note.siblingLines], and VTIMEZONE and other calendar-level content in
/// [Note.calendarLines]. The master is the first VJOURNAL without
/// RECURRENCE-ID. Throws if the resource holds no VJOURNAL.
Note parseNote(String text) {
  final cal = _splitCalendar(text);
  final journals = [
    for (final b in cal.blocks)
      if (b.type == 'VJOURNAL') b
  ];
  if (journals.isEmpty) throw ICalException('no VJOURNAL found');
  bool isOverride(_Block b) =>
      b.lines.any((l) => l.toUpperCase().startsWith('RECURRENCE-ID'));
  final master =
      journals.firstWhere((b) => !isOverride(b), orElse: () => journals.first);
  final note = _journalFromLines(master.lines);
  for (final b in cal.blocks) {
    if (identical(b, master)) continue;
    (b.type == 'VJOURNAL' ? note.siblingLines : note.calendarLines)
        .addAll(b.lines);
  }
  note.calendarLines.addAll(cal.looseLines);
  return note;
}

/// Serializes [notes] as one VCALENDAR with CRLF line endings.
String serializeNotes(Iterable<Note> notes) {
  final out = StringBuffer();
  void w(String l) => out.write('${fold(l)}\r\n');
  w('BEGIN:VCALENDAR');
  w('VERSION:2.0');
  w('PRODID:$_prodId');
  for (final n in notes) {
    n.calendarLines.forEach(w);
    w('BEGIN:VJOURNAL');
    w('UID:${n.uid}');
    w('DTSTAMP:${_formatDateTime(n.dtstamp)}');
    if (n.created != null) w('CREATED:${_formatDateTime(n.created!)}');
    if (n.lastModified != null) {
      w('LAST-MODIFIED:${_formatDateTime(n.lastModified!)}');
    }
    String params(String name) => n.propertyParams[name] ?? '';
    if (n.summary.isNotEmpty) {
      w('SUMMARY${params('SUMMARY')}:${escapeText(n.summary)}');
    }
    if (n.description.isNotEmpty) {
      w('DESCRIPTION${params('DESCRIPTION')}:${escapeText(n.description)}');
    }
    if (n.categories.isNotEmpty) {
      w('CATEGORIES:${n.categories.map(escapeText).join(',')}');
    }
    if (n.status != null && n.status!.isNotEmpty) w('STATUS:${n.status}');
    n.extraLines.forEach(w);
    w('END:VJOURNAL');
    n.siblingLines.forEach(w);
  }
  w('END:VCALENDAR');
  return out.toString();
}

String serializeNote(Note n) => serializeNotes([n]);
