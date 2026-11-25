# Mobile layout audit (2026-11-25)

A sweep of every narrow screen at phone widths for overflow and for selector
rows that do not span the content width. The audit is
`apps/app/test/mobile_audit_test.dart` (new file; `apps/app/lib` untouched).

Run: `cd apps/app && flutter test test/mobile_audit_test.dart` — 52 tests,
all green.

## How it checks

Each screen is pumped at **320 × 800, 360 × 800 and 390 × 800** (device pixel
ratio 1) with realistic long data: note and task titles of 70+ characters,
eight tags on a card, nested folders, due dates, priorities, a status word
outside the fixed set and an event with a long summary and a location. Then,
after `pumpAndSettle`:

1. `tester.takeException()` must be null (a RenderFlex/overflow error, with
   its "overflowed by N pixels" text, ends up in the failure message).
2. Presence checks first — the card, row, field or dialog is really on
   screen, so a navigation miss cannot make the overflow check vacuous.
3. Where the app has a rule that a selector spans the content width, the
   control's rect is compared with a full-width neighbour's rect, within
   1 px.

The harness is proved by a self-check test: a 400 px `Row` in a 100 px box
must be reported by `takeException()`.

## Defects found

None. No overflow and no selector that fails to span, at any of the three
widths, on any of the screens below.

| screen | 320 px | 360 px | 390 px |
| --- | --- | --- | --- |
| Home board (accordion sections) | ok | ok | ok |
| Home day (calendar + cards) | ok | ok | ok |
| Notes tree (side menu) | ok | ok | ok |
| Notes list (saved view) | ok | ok | ok |
| Tasks panel (filters, folder selector) | ok | ok | ok |
| Events panel (agenda) | ok | ok | ok |
| Search (field + hits) | ok | ok | ok |
| Account | ok | ok | ok |
| Settings | ok | ok | ok |
| Note detail | ok | ok | ok |
| Task detail | ok | ok | ok |
| Event detail | ok | ok | ok |
| Space chip sheet | ok | ok | ok |
| Open-items grid (3 tabs) | ok | ok | ok |
| New note dialog | ok | ok | ok |
| New task dialog | ok | ok | ok |
| New event dialog | ok | ok | ok |

Measured for the only span rule the app states in code (the tasks panel's
filter segmented control and its folder selector both ask for
`double.infinity` at phone width, `tasks_panel.dart` `_Filters`):

| width | content width | segmented control | folder selector | difference |
| --- | --- | --- | --- | --- |
| 320 px | 296.0 px | 296.0 px | 296.0 px | 0.0 px |
| 360 px | 336.0 px | 336.0 px | 336.0 px | 0.0 px |
| 390 px | 366.0 px | 366.0 px | 366.0 px | 0.0 px |

Content width is the viewport minus the panel's 12 px padding on each side.
The accordion sections on the Home board are equal width at every phone
width too.

## Notes on what this does not cover

- Only the widths asked for; 280 px and landscape phones were not run.
- Only the listed screens. Edit modes (the note, task and event editors with
  their save bars), the command palette, the Vim help overlay and the long
  lists' scroll-extent behaviour were not part of this sweep.
- The layout is measured after one `pumpAndSettle` on the default state: a
  screen reached with a different filter, an empty list, or a very long tag
  list is a different layout, though the data here is deliberately extreme.
- Existing tests already cover a few of these screens at other widths
  (`mobile_item_test.dart`, `mobile_narrow_test.dart`, `board_card_test.dart`);
  this file adds the 320/360/390 sweep and the span rule.
