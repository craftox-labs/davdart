# davdart

Notes and planning over CalDAV, local-first with sync. Notes are stored as iCalendar `VJOURNAL` resources, so any CalDAV server (for example Radicale) holds them and any client can read them.

Status: v0, in development. APIs, note formats and the UI will still change.

## What works today

- A UI-free Dart core: notes, plan items, folders, saved views, a CalDAV client and a sync engine.
- A Flutter web app (built on forui 0.28.0): icon rail with Files, Views, Search, Spaces, Account and Settings; a tab strip; a full-page note view with in-place editing; board and list views; an optional mirrored layout; a token-driven theme.
- Spaces: each Space is a CalDAV collection or a local-only store. Folders and saved views sync as ordinary notes.
- A small board server that serves the app and proxies CalDAV to the upstream server.
- A CLI for listing, creating, moving and exporting notes.

## Planned

Real colours, a command palette, tables, and desktop and phone builds. The planning collection is the source of truth for the roadmap; this list is only a summary.

## Architecture

- Core package (repo root, plain Dart, no Flutter): `Note` (uid, summary, description, categories, status, timestamps; unmodelled properties such as `ATTACH` are kept so a round trip loses nothing), `PlanItem`, `NoteTree`, `Space`, `SyncEngine`, `CalDavClient` (REPORT, get, put, delete with ETag preconditions; `ConflictException` on 412) and RFC 5545 parsing and serialising for `VJOURNAL`.
- `apps/app`: the Flutter web app. Theme tokens live in `lib/theme/tokens.dart`.
- Logo: `assets/logo/davdart.svg` (the app draws it from the same path data in `apps/app/lib/ui/logo.dart`).
- `apps/web`: a Shelf server for the board, serving the built app at `/app/` and proxying `/dav/` to the CalDAV upstream.

## Getting started

Prerequisites: a Dart SDK (3.5 or newer) and, for the app, a Flutter SDK matching `apps/app/pubspec.yaml`. Local SDK copies under `dart-sdk/` and `flutter-sdk/` are gitignored.

Tests and analysis:

    dart pub get && dart test && dart analyze
    (cd apps/web && dart pub get && dart test && dart analyze)
    (cd apps/app && flutter pub get && flutter test && flutter analyze)

Build and serve the app:

    (cd apps/app && flutter build web --release --base-href /app/)
    (cd apps/web && dart run bin/server.dart 8810)

Set `DAVDART_DAV_UPSTREAM` to the CalDAV server's base URL to enable the `/dav/` proxy the app uses for sync. The server also needs the connection settings below.

CLI: `dart run bin/davdart.dart <command>`. Commands: `list [--status S] [--tag T]`, `board`, `show TEXT`, `add TITLE [BODY]`, `new TITLE [...]`, `set-status MATCH STATUS`, `append MATCH`, `folder TITLE [--under MATCH]`, `move MATCH TARGET|top`, `export DIR`, `rm UID`. Run it without arguments for the full usage line.

## Configuration

The CLI and board server read `url`, `user` and `password` from a key=value file (`~/.config/davdart/credentials`, or the path in `DAVDART_CONFIG`). `DAVDART_URL`, `DAVDART_USER` and `DAVDART_PASSWORD` override each key.

## Note formats

- Folder: a note tagged `kind-folder`. Notes point at their parent by uid; a note whose parent is missing shows at the top level.
- Saved view: a note tagged `kind-view`. The title is the view name; the body is `key: value` lines: `mode` (`board` or `list`), `search`, `tags` (comma separated), `folder` (uid of a folder to scope to). Unknown keys are kept.

Folders and saved views are hidden from boards and lists.

## Project layout

- `lib/`, `bin/davdart.dart`, `test/`: core package and CLI.
- `apps/app/`: Flutter web app.
- `apps/web/`: board server and CalDAV proxy.

## Licence

AGPL-3.0-or-later. See `LICENSE` and `NOTICE`.
