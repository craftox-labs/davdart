# Property map, 2026-11-28

Every property has one definition: label, icon and option list in `apps/app/lib/ui/property/property_defs.dart` (`Props.*`, `statusWords`, `taskStatusOptions`, `noteStatusOptions`, `priorityOptions`, `eventStatusOptions`). Changing a label or icon is one edit there. `test/design_rules_test.dart` ("status, priority and due pickers are built once") fails when a menu or dialog hard-codes those labels or builds its own calendar or option rows.

Shared pieces (all in `lib/ui/property/`): `PropertyRow` (the line), `PropertyPicker` (row + write + failure flash) or `DraftPropertyRow` (row for an unsaved item in a dialog), `PropertyTrigger` (popover on desktop, sheet on phone), `OptionPicker`/`PickerRow`, `DatePropertyPicker`, `TagPropertyPicker`, `ParentPropertyPicker`, `optionMenuItem` (the menu form of an option property), `showMoveToParentDialog` and `showDateDialog` (pickers in a dialog from a menu).

Controlling tokens (`lib/theme/tokens.dart`): `sizes.propertyRow` (32), `sizes.touchTarget` (44, rows on narrow and picker rows), `sizes.metaLabel` (label column), `sizes.folderIndent` (parent tree indent), `sizes.dialogSm`/`dialog`/`dialogLg` (popover and dialog widths), `space.*` (row and picker padding), `radii.small` (hover fill), `icons.sm`/`md`, `type.bodyStyle`/`monoStyle`/`captionStyle`, `muted`, `faint`, `accent`, `error`, `hover`, `divider`, `borders.hairline`.

| Property | Definition | Component | Used in |
|---|---|---|---|
| status (task) | `Props.status`, `statusWords`, `taskStatusOptions` | `OptionPicker` | task page row, board card popover, task menu "Set status" (`optionMenuItem`), New task dialog |
| status (note) | `Props.status`, `noteStatusOptions` | `OptionPicker` (clearable) | note page row, card popover, note menu, project overview icon |
| status (event) | `Props.status`, `eventStatusOptions` | `OptionPicker` | event page row, New event dialog |
| priority | `Props.priority`, `priorityOptions`, `priorityBucket`/`priorityOfBucket` | `OptionPicker` (clearable) | task, note page rows, card popover, task and note menus, New task dialog |
| due | `Props.due` | `DatePropertyPicker` | task page row, card popover, task menu "Set due" (`showDateDialog`), New task dialog |
| start | `Props.start` | `DatePropertyPicker` | task page row, New task dialog, project overview icon |
| labels | `Props.labels` | `TagPropertyPicker` | task, note, event page rows, card popover, New task and New event dialogs |
| belongs to / move | `Props.parent`, `Props.moveLabel`, `Props.moveIcon` | `ParentPropertyPicker` | task, note, event page rows, New task and New event dialogs, "Move to project…" in task, note and event menus and the command palette (`showMoveToParentDialog`) |

Notes and limits: a note's "Move to project…" keeps its own dialog (`move_folder_dialog.dart`) for the Personal container and project rules; `showMoveToParentDialog` is the single entry that routes to it. Menus keep hover submenus for status and priority (same option lists and labels as the pickers); due and move open the shared picker in a dialog. A new task is created first, then status and start are applied by the same writes the page uses.
