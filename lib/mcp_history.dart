/// Append-only JSONL history of MCP writes. Needs `dart:io`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// One JSON object per line. Every write tool call adds an entry (time, tool,
/// collection, item, writer, arguments and a BEFORE snapshot of the item as
/// ICS). Nothing here ever sees the bearer token or the CalDAV password.
class HistoryLog {
  HistoryLog(
    this.path, {
    DateTime Function()? now,
    this.maxLine = 262144,
    this.maxBefore = 100000,
    this.maxArg = 4000,
  }) : _now = now ?? DateTime.now;

  final String path;
  final DateTime Function() _now;

  /// Largest line written, in characters (bodies are cut to fit).
  final int maxLine;

  /// Largest BEFORE snapshot kept per item, in characters.
  final int maxBefore;

  /// Longest string argument kept, in characters.
  final int maxArg;

  static final _rand = Random.secure();

  /// Checks the file can be appended to (creating it, mode 600).
  void ensureWritable() {
    final f = File(path);
    if (!f.existsSync()) {
      f.createSync(recursive: true);
      _chmod600();
    }
    f.openSync(mode: FileMode.append).closeSync();
  }

  void _chmod600() {
    try {
      Process.runSync('chmod', ['600', path]);
    } catch (_) {}
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}...[+${s.length - max}]';

  /// Arguments with long strings clipped and secret-looking keys dropped.
  Map<String, Object?> cleanArgs(Map<String, dynamic> args) {
    final out = <String, Object?>{};
    args.forEach((k, v) {
      if (RegExp(
        r'token|password|secret|authorization',
        caseSensitive: false,
      ).hasMatch(k)) {
        return;
      }
      out[k] = v is String ? _clip(v, maxArg) : v;
    });
    return out;
  }

  /// Appends one entry and returns its `id`. Adds `time` and `id`; `before`
  /// is a list of ICS texts, each clipped. Throws when the file cannot be
  /// written: the caller must then refuse the write.
  String append(Map<String, Object?> entry) {
    final id =
        '${_now().toUtc().microsecondsSinceEpoch.toRadixString(36)}'
        '${_rand.nextInt(1 << 20).toRadixString(36)}';
    final e = <String, Object?>{
      'id': id,
      'time': _now().toUtc().toIso8601String(),
      ...entry,
    };
    final before = e['before'];
    if (before is List) {
      e['before'] = [
        for (final b in before) b is String ? _clip(b, maxBefore) : b,
      ];
    }
    var line = jsonEncode(e);
    if (line.length > maxLine) {
      // Squeeze: shorter snapshots, then no argument bodies.
      if (e['before'] is List) {
        e['before'] = [
          for (final b in e['before'] as List)
            b is String ? _clip(b, maxLine ~/ 4) : b,
        ];
      }
      line = jsonEncode(e);
      if (line.length > maxLine && e['args'] is Map) {
        e['args'] = {
          for (final en in (e['args'] as Map).entries)
            en.key: en.value is String
                ? _clip(en.value as String, 200)
                : en.value,
        };
        line = jsonEncode(e);
      }
      if (line.length > maxLine) {
        e['before'] = [
          for (final b in (e['before'] as List? ?? const []))
            b is String ? _clip(b, 2000) : b,
        ];
        e['truncated'] = true;
        line = jsonEncode(e);
      }
    }
    final f = File(path);
    final fresh = !f.existsSync();
    f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    if (fresh) _chmod600();
    return id;
  }

  /// Recent entries, newest first, optionally only those about [collection]
  /// and [item] (uid, href or exact title, case-insensitive). Bodies (the
  /// BEFORE snapshots and long arguments) are left out unless [bodies].
  List<Map<String, Object?>> read({
    String? collection,
    String? item,
    int limit = 20,
    bool bodies = false,
  }) {
    final f = File(path);
    if (!f.existsSync()) return [];
    const tail = 16 * 1024 * 1024;
    final len = f.lengthSync();
    final raf = f.openSync();
    String text;
    try {
      final start = len > tail ? len - tail : 0;
      raf.setPositionSync(start);
      text = utf8.decode(raf.readSync(len - start), allowMalformed: true);
      if (start > 0) text = text.substring(text.indexOf('\n') + 1);
    } finally {
      raf.closeSync();
    }
    final low = item?.toLowerCase();
    final out = <Map<String, Object?>>[];
    for (final l in text.split('\n').reversed) {
      if (l.trim().isEmpty) continue;
      Map<String, dynamic> m;
      try {
        m = jsonDecode(l) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (collection != null && m['collection'] != collection) continue;
      if (low != null &&
          !{
            m['uid'],
            m['href'],
            m['title'],
          }.any((v) => v is String && v.toLowerCase() == low) &&
          !((m['children'] as List?) ?? const []).any(
            (c) => c is Map && '${c['uid']}'.toLowerCase() == low,
          )) {
        continue;
      }
      if (!bodies) {
        final b = m.remove('before');
        if (b is List) m['beforeCount'] = b.length;
        final args = m['args'];
        if (args is Map) {
          m['args'] = {
            for (final en in args.entries)
              en.key: en.value is String && (en.value as String).length > 200
                  ? '${(en.value as String).substring(0, 200)}...'
                  : en.value,
          };
        }
      }
      out.add(m);
      if (out.length >= limit) break;
    }
    return out;
  }
}
