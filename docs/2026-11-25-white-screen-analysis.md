# White screen on load: analysis (2026-11-25)

The deployed app (https://tm-serve.tailf6fba0.ts.net:10002/app/, user unit
`davdart-web` on 127.0.0.1:8810, files from `apps/app/build/web`) often shows
a white page on load and sometimes never paints, most of all on the phone.

Read-only investigation. Evidence: file sizes and mtimes in
`apps/app/build/web`, the server code in `apps/web`, `curl` against
127.0.0.1:8810 only (no browser, no headless run), `journalctl --user -u
davdart-web`, and the local Flutter SDK sources. No files were changed.

## What a cold load has to fetch

Measured from the served build, `curl -w` against 127.0.0.1:8810:

| file | bytes | compressed | from |
|---|---:|---|---|
| `main.dart.js` | 5,173,523 | no (`content-encoding` absent) | 127.0.0.1:8810 |
| `canvaskit/canvaskit.wasm` | 7,315,452 (local copy unused: cause 1) | no | **www.gstatic.com** |
| `canvaskit/canvaskit.js` | 87,031 | no | **www.gstatic.com** |
| `assets/packages/forui/.../Inter.ttf` | 874,708 | no | 127.0.0.1:8810 |
| `Inter-Italic.ttf` | 904,532 | no | 127.0.0.1:8810 |
| `lucide.ttf` | 25,952 | no | 127.0.0.1:8810 |
| `flutter_bootstrap.js` | 14,127 | no | 127.0.0.1:8810 |
| `index.html` | 2,091 | no | 127.0.0.1:8810 |

About 14 MB, uncompressed, per cold load, and the largest file comes from the
public internet rather than the tailnet. `du -sh apps/app/build/web` is 45 MB,
of which 37 MB is `canvaskit/` (six engine variants that are never requested,
see cause 1).

Nothing in `index.html` paints while all that loads: the body holds only
`<script src="flutter_bootstrap.js" async>` (index.html:56), so a white page
is exactly what a slow load looks like.

## 1. CanvasKit is fetched from the Google CDN, not from the local copy (most likely)

`flutter_bootstrap.js` ends with

```js
_flutter.buildConfig = {"engineRevision":"371f77202a…","wasmHashes":{…},
  "builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};
_flutter.loader.load({serviceWorkerSettings: {serviceWorkerVersion: "3022504006"}});
```

and nothing sets `useLocalCanvasKit` or `canvasKitBaseUrl`. The loader then
resolves the engine base as

```js
// flutter.js (same code in flutter-sdk/.../flutter_js/src/utils.js:51)
n.canvasKitBaseUrl ? n.canvasKitBaseUrl
  : e.engineRevision && !e.useLocalCanvasKit
      ? E("https://www.gstatic.com/flutter-canvaskit", e.engineRevision)
      : "canvaskit";
```

`useLocalCanvasKit` defaults to false (`flutter-sdk/packages/flutter_tools/
lib/src/build_info.dart:57`) and is only set by `--no-web-resources-cdn`
(`.../web/web_options.dart:61-65`). The build config above does not carry it,
so the browser loads CanvasKit from
`https://www.gstatic.com/flutter-canvaskit/371f77202a…/canvaskit.js` and
`…/canvaskit.wasm` (7.3 MB) — over the internet, from a CDN that a
tailnet-only or filtered phone cannot necessarily reach. While that fetch is
pending or blocked the engine never initialises and there is no first frame
at all: a permanent white page. The 37 MB local `canvaskit/` copy that ships
in the build is dead weight and never requested.

This also explains "especially on the phone": the desktop browser is likely to
have gstatic warm and fast; a phone on mobile data, or with an ad-blocking /
DNS filter that drops gstatic, has no path to it. On iOS Safari the extra
7.3 MB wasm on top of the 5.2 MB script is also a common source of tab
reloads and white flashes (memory pressure).

Fix: rebuild with `flutter build web --release --base-href /app/
--no-web-resources-cdn`, which sets `useLocalCanvasKit: true` so the wasm is
served from `/app/canvaskit/` (same origin, tailnet only). Alternatively keep
the default paths and pass `canvasKitBaseUrl: "canvaskit/"` in a custom
`flutter_bootstrap.js`. Trim the unused engine variants (`chromium/`,
`skwasm*`, `wimp*`, `webparagraph/`, `*.symbols`) from the deployed directory.

## 2. No compression and no cache policy on ~14 MB of assets

`apps/web/bin/server.dart:39` serves the build with a bare
`createStaticHandler(appDir.path, defaultDocument: 'index.html')`: shelf_static
sets `content-type`, `etag`, `last-modified` and `x-content-type-options`, and
nothing else. The response headers measured for `main.dart.js`:

```
HTTP/1.1 200 OK
content-length: 5173523
content-type: text/javascript
etag: W/"5173523-1795582304196"
last-modified: Wed, 25 Nov 2026 04:51:44 GMT
```

There is no `content-encoding`, even when the request sends
`Accept-Encoding: gzip, br`, and no `cache-control` at all. Tailscale serve is
a plain proxy on :10002 and adds no compression either. So the phone
downloads 5.2 MB of JavaScript, 0.9 + 0.9 MB of Inter and 7.3 MB of wasm
verbatim. Measured locally, `gzip -9` takes `main.dart.js` from 5,173,523 to
1,325,412 bytes (a quarter) and `Inter.ttf` from 874,708 to 456,749.

Conditional requests do work (measured: `If-None-Match` with the current etag
returns 304, and so does `If-Modified-Since`), so a revalidating reload is
cheap, but with no `cache-control` the browser decides heuristically, and
after every deploy the etag changes so the full 5.2 MB is fetched again.

Fix: gzip (or brotli) middleware in front of the static handler, or serve
precompressed files next to the originals; and set `cache-control:
public, max-age=31536000, immutable` for `main.dart.js`, `canvaskit/`,
`assets/`, and `no-cache` (must revalidate) for `index.html`,
`flutter_bootstrap.js` and `flutter_service_worker.js`.

## 3. Nothing is painted during the load, in the HTML or the app

`index.html` has an empty body (index.html:56) and the app has no loading
screen: `DavdartApp` fires `state.load()` from its constructor (app.dart:61)
and the board area returns an empty layout while loading — the "no notes"
text is guarded by `!state.loading` (home_board.dart:96), so with no columns
and `loading == true` the main pane renders nothing. The only progress cue is
a spinning icon in the top bar (app.dart:908), which is not visible at all
until Flutter has painted its first frame — which is after the 14 MB above.

Fix: a static splash in `index.html` (logo, "loading…", page background) with
an `onEntrypointLoaded` callback that removes it, so the page shows something
from the first byte.

## 4. Deploys build in place and restart the server, leaving windows with mixed or no files

The served directory *is* the build output (`../app/build/web`,
server.dart:37), and the unit restarts after each build. Evidence:

- mtimes in the current build are spread over ~90 s: `canvaskit/*` and
  `flutter.js` at 11:50:28, `index.html` / `main.dart.js` /
  `flutter_bootstrap.js` at 11:51:44 — a load in that window can pair a new
  `main.dart.js` with an old engine (or a half-written file).
- `journalctl --user -u davdart-web` today: 13 start/stop pairs (140/135 over
  the whole journal), all explicit restarts (`NRestarts=0`), so they follow
  deploys, roughly every half hour while the app is being worked on.
- Each start is 3 s of downtime: `Started … 11:51:44` →
  `dart[2736172]: davdart board on http://127.0.0.1:8810/` at 11:51:47. The
  unit runs `dart run bin/server.dart` (unit file), which compiles at start.
  During those 3 s the port is closed and every load fails (connection
  refused), not even a white page from our HTML.
- The same unit has failed outright on a broken tree before: `Nov 21
  14:52:42 … lib/src/zone.dart:70:32: Error: 'Location' isn't a type … Failed
  with result 'exit-code'`, and `Restart=on-failure` then cycles until fixed.

Fix: build into a staging directory and swap it in atomically (rename or
symlink switch) before restarting, or keep serving the previous directory
until the new build is complete; and precompile the server (`dart compile
exe` / `dart compile jit-snapshot`) so a restart is well under a second.

## 5. Service worker: one forced reload, then no caching at all

The build's `flutter_service_worker.js` (784 bytes) does nothing but
unregister itself on activate and force every client to reload:

```js
self.addEventListener('activate', (event) => { …
  await self.registration.unregister(); …
  clients.forEach((client) => client.navigate(client.url)); });
```

`flutter_bootstrap.js` still passes `serviceWorkerSettings`, and flutter.js
registers the worker only when a registration already exists
(`loadServiceWorker`: `serviceWorkerUrl != null ? register : getRegistration()
.then(t => t ? register : …)`), with a 4 s timeout. So a browser that ever had
an older, real Flutter service worker gets one extra full reload on the next
visit — a white flash, and on a phone another 14 MB if the reload is not from
cache. It cannot loop by itself (the registration is gone after the first
activate). Everything else is uncached by the app, so a stale
`main.dart.js` from an old deploy is not the mechanism here; the risk is the
opposite, always re-downloading.

Fix: either drop `serviceWorkerSettings` from the bootstrap (nothing is
cached anyway) or go back to a real precaching service worker with a version
check (`version.json` is already emitted) and a reload prompt instead of a
forced navigation.

## 6. Startup keeps the board empty on network work, with no timeouts

`state.load()` (app_state.dart:1402) runs sequentially: account connect on a
new Space, `_checkHeld`, notes, tasks, events, a views migration that reloads
the notes again, then `sync()` afterwards. Every step is a network call when
the Space is connected. Measured against the local server: `/api/notes`
(the first-run Planning feed) 0.19–0.26 s for 269 KB, and one `/dav/`
PROPFIND through the proxy 0.95 s (Radicale auth round trip). `CalDavClient`
sets no request timeout (`lib/src/caldav.dart:301`, `await _http.send(req)`);
the `/dav/` proxy gives up after 30 s (`apps/web/lib/dav_proxy.dart`,
`.timeout(const Duration(seconds: 30))`), so a stalled upstream holds the app
on an empty board for up to 30 s per request, several times over in one load.

Fix: show the shell and its first paint before the data arrives, add a request
timeout in `CalDavClient`, and fold the second full load after the views
migration into the first.

## Not the cause (checked)

- base href and the path: `index.html` sets `<base href="/app/">`
  (index.html:17), the server redirects `/app` → `/app/` and strips the `app/`
  prefix (server.dart:53-55), and `tailscale serve status` maps
  `https://tm-serve.tailf6fba0.ts.net:10002` → `http://127.0.0.1:8810` at `/`
  with no prefix, so asset URLs resolve correctly. Locally every asset
  returns 200 with the right `content-type` (`application/wasm`,
  `text/javascript`).
- The app's own startup code: `main()` does no awaits before `runApp`
  (apps/app/lib/main.dart), so nothing blocks the first frame in Dart.
- A binary asset 404: `AssetManifest.bin.json`, `FontManifest.json` and all
  three fonts answer 200; `assets/NOTICES` (1.4 MB) is bundled but never
  requested at runtime.

## Worth measuring next, with the phone in hand

The one thing this investigation cannot see is the browser's own network
panel on the failing phone. Open the app, then check, in this order: whether
`www.gstatic.com/.../canvaskit.wasm` is pending or failed (cause 1), the
transfer size and duration of `main.dart.js` (cause 2), and the console for a
`CanvasKit`/`WebAssembly` error. That single look confirms or rules out the
top two causes.
