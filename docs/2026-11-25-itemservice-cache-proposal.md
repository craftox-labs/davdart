# ItemService read cache: proposal (2026-11-25)

`ItemService._load` (lib/src/item_service.dart:660) lists all three kinds
through `CalDavClient.listNotes/listTasks/listEvents` on every call: three
REPORTs, every body parsed, with no state kept between calls. From
docs/2026-11-25-load-test.md (2000 items, in-process fake): `list()` 339 ms,
`board()` 96.9 ms (it lists again internally), `list(under:)` 119.6 ms. A
CLI or MCP flow that reads two or three times pays all of it each time.

## Recommendation

Keep one parsed snapshot on the `ItemService` instance and validate it with
the collection's sync token plus per-href ETags, both obtained without
bodies.

- **Cache**: `_Load? _cache` on `ItemService`, holding `List<_Ref> refs`
  (the parsed Note/Task/Event objects, which is what `_Ref` already is),
  `String? token`, `Map<String, String> etags` (href → ETag), and a
  `DateTime at`.
- **Key**: the RFC 6578 sync token, checked with a REPORT that asks for
  `getetag` only (no `calendar-data`): token unchanged and no changed or
  deleted href → the snapshot is current. Token changed → GET only the
  hrefs that changed, drop the deleted ones, keep the rest; a changed ETag
  with the same token (servers that hand out a constant token) also forces
  a re-GET of that href. That needs one new method on `CalDavClient`
  (`syncEtags(syncToken)`, the same REPORT as `sync` with the data property
  swapped for `getetag`); `SyncTokenInvalid` falls back to a full read.
- **Fallback**: no sync-collection → PROPFIND depth 1 for ETags; if that is
  unsupported too, expire the snapshot after a short TTL (5 s, like the board
  server's own `apps/web/bin/server.dart` cache) and re-read.
- **Not in the store**: `NoteStore` is the `SyncEngine`'s merge base with
  its own lifecycle and per-Space ownership; the cache is a read-through
  convenience for one collection and one credential set, so it belongs to
  the `ItemService` instance and dies with it. No new global, no disk
  format, no cross-process sharing.

## Invalidation

- Writes: every ItemService write already returns the new `ItemData`/`_Ref`
  (`create`, `update`, `setStatus`, `setNotePriority`, `rankItem`, delete…).
  Replace that uid's entry in `refs` and its `etags[href]` from the result,
  leave the token alone (the next token check confirms it); a delete drops
  the entry and adds it to a `gone` set until the next check. Any write
  whose response cannot be trusted clears `_cache` outright.
- Sync merges elsewhere: another client, the app's `SyncEngine` or a
  `mergeNotes` round trip all write to the server, so the next token check
  sees them. A merge that happens *through* this ItemService goes through
  the write path above.
- A token check that errors (network, 5xx) serves the snapshot and marks it
  stale-after-TTL, so a read still works offline; the next call retries.

## Risks

- Stale reads on servers that ignore or do not bump tokens: bounds are the
  ETag pass and the TTL, so the worst case is one TTL window.
- Memory: the snapshot is the same objects one full read holds today, and
  the ICS text is not kept. The board server and MCP (one `ItemService` per
  process, lib/mcp_server.dart:178) pay it once; the CLI builds one per
  command (bin/davdart.dart:259) and gains nothing, so no disk cache.
- Races: today's read-then-write conflict is unchanged; the cache must never
  be used to build a PUT body that skips an ETag precondition, and a
  `dryRun` or failed write must not populate it.

## Gain

Warm reads replace 339 ms with one token REPORT of a few KB (a few ms
locally) and no parse: `list()` and `board()` → ~0–10 ms each (the board
stops re-listing), a list + board + scope pass ~536 ms → ~20 ms.

## Test plan

FakeCalDav, `test/item_service_cache_test.dart`: (1) two `list()` calls → one
REPORT in `fake.log`; (2) `fake.external(...)` between calls → the new
content, one extra GET; (3) `externalDelete` → the item is gone; (4)
`create`/`setStatus` then `list()` → the new value, no full REPORT; (5)
`rejectTokens = true` → full-read fallback, same results; (6) `board()`
after `list()` issues no second REPORT; (7) TTL expiry re-reads; (8) an
erroring token check still serves the snapshot. Then re-run
`dart run tool/load_test.dart` for the after numbers.
