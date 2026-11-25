# The add button against the panel and grid adds (2026-11-25, step 7)

A read of the floating add button (`AddFab`, `bar-add`) against the other two
ways to add on a phone, after the drawer became a rail strip beside the panel.
No change was needed; this records what was checked.

## Where it sits

`AddFab` is the bar-sized circle in the body's bottom-right corner
(`apps/app/lib/ui/app.dart`, `Positioned(right: lg, bottom: lg)`), inside the
body, so it clears the bottom bar (a `FScaffold` footer) rather than floating
over it. It is mounted only when all of these hold: no menu and no grid
(`!_menuOpen && !_gridOpen`), no open note (`mainNote == null && !hasDetail`)
and no keyboard (`viewInsets.bottom == 0`).

## Against the panel's own + buttons

The panels only show on the phone inside the drawer, and the drawer hides the
button, so the panel's header actions (`new-project`, `new-note`, `new-task`,
`new-event`, the folder + and new-folder controls) never compete with it. On a
desktop the button does not exist at all.

## Against `grid-add`

The open-items grid covers the body and has its own add (`grid-add`, with its
own menu prefix `grid-` and its rows inserted before Done). The button is hidden
while the grid is open, so the two never show together.

## Against scrolling content

Everything that scrolls under the button reserves room for it: the list view,
the board columns, the Home day focus and the phone's single Home scroll end
with `fabInset(context)` (`t.sizes.fabClearance`) of bottom padding, so the
last row, card or column end is reachable rather than sitting under the circle.

## Not checked

Pointer-level dragging: a note dragged to the bottom-right corner passes near
the button. Rows are inset at the bottom only, so a drag can start under it,
but no reported gesture conflict exists and the button is not a drag target.
