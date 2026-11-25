import 'open_link_stub.dart'
    if (dart.library.js_interop) 'open_link_web.dart'
    as impl;

/// Opens [url] outside the app: a new browser tab on the web build, which is
/// the only target. Nothing happens on a non-web build (no launcher is
/// bundled).
void openExternalUrl(String url) => impl.openExternalUrl(url);
