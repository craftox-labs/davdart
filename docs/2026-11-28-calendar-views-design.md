# Calendar views: Day, Week, Year (design note, 2026-11-28)

One `CalendarView` (apps/app/lib/ui/calendar_view.dart:141) grows three sibling
scales beside Month. The scale switcher lives in the calendar's own toolbar
row, not the page header: `_grid`'s `PaneHeaderRow` already holds the month
title, prev/next and Today (calendar_view.dart:475), so the pill sits there as
a `Segmented<CalendarScale>` (apps/app/lib/ui/segmented.dart:23, `iconsOnly` on
narrow), and home_page.dart:428 / project_overview.dart stay untouched.

## 1. State

- `enum CalendarScale { day, week, month, year }`; `_month` (calendar_view
  .dart:180) becomes `_anchor`, any day inside the shown period. `_selected`
  (the picked day) stays separate, so the pinned day panel keeps working in every
  scale.
- Derived, never stored: month = `_monthOf(anchor)`; week start = anchor minus
  `(anchor.weekday - firstWeekday(context) + 7) % 7` (the lead math at
  calendar_view.dart:392); day = anchor.
- `_showMonth` (calendar_view.dart:362) becomes `_showPeriod`: same "pull the
  selection into view" rule, stepping 1 month, 7 days, 1 day, 1 year. Today sets
  anchor and selection to today.
- Default Month; persisting the scale per Space beside `davdart.home.view.v1.*`
  (apps/app/lib/state/app_state.dart:1574) is one line and matches how Home
  remembers its view — open question 7.3.

## 2. Week and Day time grid

- Day is Week with one column: one `_timeGrid(columns: n)`, `n` = 1 or 7.
- Top strip, all-day and multi-day bars: reuse `_spans`
  (calendar_view.dart:219) over `[weekStart, weekStart + days)` and `layOutWeek`
  / `LaneGeometry` (calendar_lanes.dart:114, :186). `layOutWeek` hardcodes 7
  days; add a `days` parameter (default 7) so Day passes 1 — the month path is
  unchanged and apps/app/test/calendar_lanes_test.dart covers the change.
- Single-day items in that strip keep the month cell's chips (`_chip`,
  calendar_view.dart:1043), an all-day task included.
- Below it the timed area: hour pitch, a column per day, blocks placed by wall
  minutes from midnight. The fields are already wall-clock and a written END wins
  over start+length across DST (`Event.endWall`, lib/src/event.dart:126;
  `EventOccurrence.start/end` are those fields). Height = end − start, floored at
  one row, clipped to the day.
- Overlap: sweep each column into clusters (a cluster grows while the next start
  is before its max end); a block's width is its share of the concurrent count,
  its left index × width. Pure data, no widgets, in a new
  `apps/app/lib/ui/calendar_timegrid.dart` with its own unit test — the shape of
  calendar_lanes.dart.
- Drag-to-create: press captures the slot (15-minute snap), vertical drag to the
  end slot, release opens `showNewEventDialog`
  (apps/app/lib/ui/event_menu.dart:285) with a new `start`/`end` pair landing in
  `_NewEventForm.setStart/setEnd` (event_menu.dart:257, :267) as minutes. A drag
  starting on a block or a bar is left alone; no horizontal range in v1 (7.4).
- A task with a due time stays a chip in the strip, not a block: nothing
  pretends a due moment has a length (open question 7.2).

## 3. Year

- Twelve mini-months, three across on wide, one across on the phone, each seven
  columns of untouched day squares; no date numbers, no cells to press
  individually.
- Density: a day with items takes one `StatusDot` per kind at `calendarDot`
  size — the dot rule the narrow month cell already uses
  (calendar_view.dart:921) — so no new tone enters the palette.
- Press a day square → Day view on that day; press a month name → Month view on
  that month; arrows step a year; Today returns to today's month.

## 4. Carries over unchanged

The plus and its tracked popover (`_addButton`, calendar_view.dart:1121), chips
(`_chip`), bars (`_bar`, calendar_view.dart:732), the pinned day panel and its
press rule (`_select`/`_openItem`, calendar_view.dart:245, :267), the agenda in
events_panel.dart, `bucketByDay` (lib/src/calendar_days.dart:87),
`firstWeekday`, and the source filters (`_events`/`_tasks`,
calendar_view.dart:197, :207) — `scoped`, `isMine`, `inProjectsLayer`,
`supportsEvents/Tasks` are untouched. Existing keys (`calendar-month`,
`calendar-prev/next/today`, `calendar-day-*`, `calendar-chip-*`,
`calendar-bar-*`) keep their names on the Month path; new scales get prefixed
keys, so apps/app/test/calendar_view_test.dart keeps passing as written.

## 5. Phones

One column wide, same structure: icon-only switcher in the toolbar, Today as a
compact `IconAction` so the row fits 320, week still seven columns with
tone-only blocks, year one month per row inside the page scroll. The rule that
a touch drag is not a range (calendar_view.dart:612) holds: a press on an empty
slot opens the new-event dialog at that slot's time, no drag. The time grid gets
its own bounded height and scroll controller instead of the page's
`SingleChildScrollView` (calendar_view.dart:378) — the one structural change to
`build`.

## 6. Build order (one commit per step, each with its tests)

1. `calendar_timegrid.dart` + test: cluster/overlap geometry, minute snapping,
   block clamping, one-column case. No UI change.
2. `CalendarScale` + `_anchor` + `_showPeriod` + the toolbar `Segmented`, Month
   only wired; extend apps/app/test/calendar_view_test.dart with the switcher,
   per-scale prev/next/Today and anchor derivation.
3. Year view: mini-months, density dots, day→Day and month-name→Month presses,
   year arrows.
4. Week/Day skeleton: `days` parameter in `layOutWeek`, all-day strip from
   `_spans` + lanes, weekday header, Day = one column, selected-day behaviour.
5. Timed blocks and drag-to-create: block layout in the grid, now line, drag
   sets start/end in the dialog, phone press-to-create.

Each step runs only its own file (`flutter test` on calendar_view_test.dart,
calendar_lanes_test.dart, calendar_days_test.dart, plus the new one); never the
full suite.

## 7. Risks and open questions

1. **Nested scrolling.** The page scrolls as a whole today; the timed area must
   scroll on its own. A bounded height inside the card is the fix, and it changes
   how `_grid` reports height to `calendarRowHeight`
   (apps/app/lib/theme/tokens.dart:620) for Month — decide before step 4, or
   land 4 and 5 together.
2. **Timed tasks** stay chips (proposed); a one-row block at the due time reads
   better in Day but invents a duration.
3. **Scale persistence:** widget state (resets on Space switch, like the
   `ValueKey`s) or per-Space prefs like `homeView` (app_state.dart:1574)?
4. **Horizontal drag** in Week: a day range or a cross-day event. Left out of v1;
   it collides with the existing all-day range drag.
5. **Late-night events.** `_multiDay` (calendar_view.dart:114) makes any two-day
   occurrence a bar, so 22:00–02:00 shows as a strip bar, not blocks. Consistent
   with Month; keep it and say so in the view's doc comment.
6. **Strip overflow.** `layOutWeek` hides bars past `maxLanes` (reported as
   `hidden`, calendar_lanes.dart:114) and the strip cannot shrink; "+N more"
   should open Day view on that column.
7. **Hour pitch.** No existing size fits an hour: derive it from the viewport
   like `calendarRowHeight` (a function, not a stored colour or type token). A
   constant, if needed, sits beside the other calendar sizes (tokens.dart:302).
