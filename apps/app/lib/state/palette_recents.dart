import 'dart:convert';

import '../data/key_value_storage.dart';

/// The last few action ids run from the palette, newest first, kept in the
/// prefs like other per-viewer choices.
class PaletteRecents {
  PaletteRecents(this.prefs);
  final KeyValueStorage? prefs;

  static const key = 'davdart.palette.recent.v1';
  static const max = 5;

  List<String> read() {
    final raw = prefs?.read(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final v in jsonDecode(raw) as List<dynamic>)
          if (v is String) v,
      ].take(max).toList();
    } catch (_) {
      return const [];
    }
  }

  void add(String id) {
    final p = prefs;
    if (p == null) return;
    final next = [id, ...read().where((e) => e != id)].take(max).toList();
    p.write(key, jsonEncode(next));
  }
}
