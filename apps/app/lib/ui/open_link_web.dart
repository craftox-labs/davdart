import 'package:web/web.dart' as web;

/// Opens [url] in a new browser tab (http and https only). `noopener` keeps
/// the page from getting a handle on the app.
void openExternalUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https')) return;
  web.window.open(url, '_blank', 'noopener');
}
