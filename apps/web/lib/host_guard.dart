import 'package:shelf/shelf.dart';

/// Host names served by default: loopback plus the tailnet name this board
/// is published under. Override with DAVDART_ALLOWED_HOSTS.
const defaultAllowedHosts = [
  'localhost',
  '127.0.0.1',
  '[::1]',
  'tm-serve.tailf6fba0.ts.net',
];

/// Parses a comma-separated host list (port and case ignored).
List<String> parseAllowedHosts(String? env) {
  if (env == null || env.trim().isEmpty) return defaultAllowedHosts;
  return [
    for (final h in env.split(','))
      if (h.trim().isNotEmpty) _hostOnly(h.trim()),
  ];
}

String _hostOnly(String hostPort) {
  final h = hostPort.toLowerCase();
  if (h.startsWith('[')) {
    final end = h.indexOf(']');
    return end < 0 ? h : h.substring(0, end + 1);
  }
  final i = h.indexOf(':');
  return i < 0 ? h : h.substring(0, i);
}

/// Refuses requests whose Host header (or Origin, when sent) names a host
/// outside [allowed]. Stops DNS rebinding: a page on an attacker's name that
/// resolves to 127.0.0.1 still sends the attacker's name as Host.
Middleware hostGuard(Iterable<String> allowed) {
  final ok = {for (final h in allowed) _hostOnly(h)};
  return (inner) => (req) {
        final host = req.headers['host'];
        if (host == null || !ok.contains(_hostOnly(host))) {
          return Response(421, body: 'unknown host');
        }
        final origin = req.headers['origin'];
        if (origin != null && origin != 'null') {
          final u = Uri.tryParse(origin);
          final oh = u == null || u.host.isEmpty
              ? null
              : (u.host.contains(':') ? '[${u.host}]' : u.host.toLowerCase());
          if (oh == null || !ok.contains(oh)) {
            return Response(403, body: 'foreign origin');
          }
        }
        return inner(req);
      };
}
