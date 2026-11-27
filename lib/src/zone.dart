import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Time zone conversions for the core, backed by the `timezone` package's
/// bundled database (loaded on first use).
///
/// "Wall" values are UTC-flagged [DateTime]s that only carry clock fields.
/// The viewer's zone is the platform zone unless [LocalZone.use] sets one
/// (tests, or an app setting).
class LocalZone {
  LocalZone._();

  static bool _loaded = false;
  static tz.Location? _override;
  static final Map<String, tz.Location?> _cache = {};

  static void _init() {
    if (_loaded) return;
    tzdata.initializeTimeZones();
    _loaded = true;
  }

  /// Make [name] (an IANA name such as `Asia/Bangkok`) the viewer's zone, or
  /// restore the platform zone with null. Throws [ArgumentError] when the
  /// name is unknown.
  static void use(String? name) {
    if (name == null) {
      _override = null;
      return;
    }
    final l = location(name);
    if (l == null) throw ArgumentError.value(name, 'name', 'unknown zone');
    _override = l;
  }

  /// The IANA name of the zone set with [use], or null for the platform zone.
  static String? get overrideName => _override?.name;

  /// The zone for a TZID, or null when it is not in the database. Tolerates
  /// a path prefix such as `/mozilla.org/20050126_1/Europe/Berlin`.
  static tz.Location? location(String tzid) => _cache.putIfAbsent(tzid, () {
        _init();
        if (tzid.toUpperCase() == 'UTC') return tz.UTC;
        final parts = tzid.split('/').where((p) => p.isNotEmpty).toList();
        for (var i = 0; i < parts.length; i++) {
          try {
            return tz.getLocation(parts.sublist(i).join('/'));
          } catch (_) {}
        }
        return null;
      });

  /// The wall fields (UTC-flagged) of [instant] in the viewer's zone.
  static DateTime wallOf(DateTime instant) {
    final u = _plain(instant);
    final o = _override;
    final l = o == null ? u.toLocal() : tz.TZDateTime.from(u, o);
    return DateTime.utc(l.year, l.month, l.day, l.hour, l.minute, l.second);
  }

  /// The instant (UTC) of viewer-zone wall fields [w].
  static DateTime instantOf(DateTime w) {
    final o = _override;
    return o == null
        ? DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second).toUtc()
        : instantIn(o, w);
  }

  /// The instant (UTC) of wall fields [w] in zone [l].
  static DateTime instantIn(tz.Location l, DateTime w) => _plain(
        tz.TZDateTime(l, w.year, w.month, w.day, w.hour, w.minute, w.second),
      );

  // A plain UTC DateTime: a TZDateTime would `toLocal()` into the package's
  // own local location instead of the platform zone.
  static DateTime _plain(DateTime d) => DateTime.fromMicrosecondsSinceEpoch(
        d.microsecondsSinceEpoch,
        isUtc: true,
      );

  /// The wall fields (UTC-flagged) of [instant] in zone [l].
  static DateTime wallIn(tz.Location l, DateTime instant) {
    final d = tz.TZDateTime.from(instant.toUtc(), l);
    return DateTime.utc(d.year, d.month, d.day, d.hour, d.minute, d.second);
  }
}
