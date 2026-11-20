/// Fuzzy-ish matching for the command palette: every word of the query must
/// appear as a substring of the title or keywords. Pure, no UI.
library;

/// Words of [query], lower-cased.
List<String> queryWords(String query) => [
  for (final w in query.toLowerCase().split(RegExp(r'\s+')))
    if (w.isNotEmpty) w,
];

/// The score of [title] (with extra [keywords]) for [query], or null when a
/// word is missing. A word scores most at the start of the title, then at the
/// start of a title word, then inside the title, then in a keyword only.
/// An empty query matches everything with 0.
int? matchScore(
  String query,
  String title, [
  List<String> keywords = const [],
]) {
  final words = queryWords(query);
  if (words.isEmpty) return 0;
  final t = title.toLowerCase();
  final k = keywords.map((e) => e.toLowerCase()).toList();
  var total = 0;
  for (final w in words) {
    final i = t.indexOf(w);
    if (i == 0) {
      total += 100;
    } else if (i > 0 && RegExp(r'[\s\-_/:.]').hasMatch(t[i - 1])) {
      total += 60;
    } else if (i > 0) {
      total += 40;
    } else if (k.any((e) => e.startsWith(w))) {
      total += 25;
    } else if (k.any((e) => e.contains(w))) {
      total += 15;
    } else {
      return null;
    }
  }
  // Prefer a title that is mostly the query (shorter wins ties).
  return total * 10 - (t.length > 90 ? 90 : t.length) ~/ 10;
}

/// [items] that match [query], best first; equal scores keep their order.
List<T> rankBy<T>(
  String query,
  List<T> items,
  String Function(T) title, [
  List<String> Function(T)? keywords,
]) {
  final scored = <(int, int, T)>[];
  for (var i = 0; i < items.length; i++) {
    final s = matchScore(
      query,
      title(items[i]),
      keywords?.call(items[i]) ?? const [],
    );
    if (s != null) scored.add((s, i, items[i]));
  }
  scored.sort((a, b) {
    final c = b.$1.compareTo(a.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  return [for (final s in scored) s.$3];
}
