/// Manual order inside a board column: a fractional rank kept as the
/// extension property `X-DAVDART-RANK` on notes and tasks. Stored as a raw
/// line in `extraLines`, so every copy, round trip and other client keeps it;
/// [Note.rank] and [Task.rank] read and write it.
const rankProperty = 'X-DAVDART-RANK';

bool _isRankLine(String l) {
  final u = l.toUpperCase();
  return u.startsWith('$rankProperty:') || u.startsWith('$rankProperty;');
}

/// The rank in [lines], or null if absent or not a finite number.
double? rankOfLines(List<String> lines) {
  for (final l in lines) {
    if (_isRankLine(l)) {
      final v = double.tryParse(l.substring(l.indexOf(':') + 1).trim());
      return v != null && v.isFinite ? v : null;
    }
  }
  return null;
}

/// Sets (or, for null, removes) the rank line in [lines].
void setRankInLines(List<String> lines, double? rank) {
  lines.removeWhere(_isRankLine);
  if (rank != null && rank.isFinite) lines.add('$rankProperty:$rank');
}

/// [lines] without the rank line.
List<String> linesWithoutRank(List<String> lines) => [
  for (final l in lines)
    if (!_isRankLine(l)) l,
];

/// The ranks to write when one card is dropped into a column.
///
/// [others] is the column's current order without the moved card ([uid],
/// rank or null); [index] is the insertion point, 0..length. Normally the
/// result is one entry, the moved card, with a rank strictly between its new
/// neighbours. Ranked items sort before unranked ones, so when the card above
/// the drop is unranked, the unranked cards above it get ranks first; and when
/// the neighbours are equal or the gap is too small to split, the whole column
/// is re-spread to 1, 2, 3, ... (only the changed entries are returned).
Map<String, double> planRanks(
  List<(String, double?)> others,
  int index,
  String moved,
) {
  final at = index.clamp(0, others.length);
  Map<String, double> spread() {
    final order = [
      for (var i = 0; i < others.length; i++) ...[
        if (i == at) (moved, null),
        others[i],
      ],
      if (at == others.length) (moved, null),
    ];
    final out = <String, double>{};
    for (var i = 0; i < order.length; i++) {
      final want = (i + 1).toDouble();
      if (order[i].$1 == moved || order[i].$2 != want) {
        out[order[i].$1] = want;
      }
    }
    return out;
  }

  final out = <String, double>{};
  double? lo;
  if (at > 0) {
    // Give every unranked card above the drop a rank after the last ranked.
    var last = 0.0;
    for (var i = 0; i < at; i++) {
      final r = others[i].$2;
      if (r != null) {
        last = r;
      } else {
        last += 1;
        out[others[i].$1] = last;
      }
    }
    lo = last;
  }
  final hi = at < others.length ? others[at].$2 : null;
  final double v;
  if (lo == null && hi == null) {
    v = 0;
  } else if (lo == null) {
    v = hi! - 1;
  } else if (hi == null) {
    v = lo + 1;
  } else {
    v = (lo + hi) / 2;
    if (!(v > lo && v < hi) || hi - lo < 1e-9) return spread();
  }
  out[moved] = v;
  return out;
}
