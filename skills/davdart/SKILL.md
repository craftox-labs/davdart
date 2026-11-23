---
name: davdart
description: Read and organise a davdart Space (notes, tasks, events on a CalDAV server) with the davdart CLI. Use when asked to look at, add, move, tag, set status on or tidy items in the user's notes, tasks or calendar space, or to manage its collections.
---

# davdart CLI

Run `dart run bin/davdart.dart ...` from the repo (or the installed `davdart`). It reads the
connection from `~/.config/davdart/credentials` or `DAVDART_URL`, `DAVDART_USER`,
`DAVDART_PASSWORD`. Never print or copy those values. One credential per agent: the server's
rights are the real boundary, the flags below are a second guard.

## Start small

1. `overview` first: a compact tree (2 levels) plus counts by kind, status and tag. Use
   `--under FOLDER` to open one branch and `--depth N` for more.
2. `list` with filters, never a bare full listing: `--kind note|task|event|all`, `--tag T`,
   `--status S`, `--under FOLDER`, `--limit N --offset N`. Plain `list` means notes only.
3. `get ID` for one item with its body. ID is a uid, href or exact title (an unambiguous
   title fragment also works).

Add `--json` for machine output (stable keys: kind, uid, title, tags, status, parent, folder,
due, priority, start, end, body). Lists leave out bodies.

## Writing

- `create TITLE --kind note|task|event [--body T | --stdin] [--tags a,b] [--status S]
  [--under FOLDER] [--folder] [--due D] [--priority 0-9] [--start W --end W --location L]`
- `update ID [--title] [--body|--stdin] [--location --start --end]`
- `move ID TARGET|top` (refuses loops), `tag ID --add a,b --remove c --set a,b`,
  `status ID WORD|none`, `due ID DATE|none`, `priority ID N|none`, `delete ID [--no-adopt]`.
- Dates: `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM[:SS][Z]`.
- Put long text on stdin (`--stdin`), not in shell arguments.
- Preview any write first with `--dry-run`: it prints what would change and writes nothing.
- A write on an item the app changed meanwhile is merged and retried once, then fails with
  a conflict: re-read and retry.

## Conventions (follow them, do not invent new ones)

- Folders are notes tagged `kind-folder` (`create --folder`). They hold items of any kind.
- Parent links are the iCalendar RELATED-TO property; `--under` and `move` set it. Do not
  put structure in titles.
- Status is a word: `backlog`, `todo`, `doing`, `blocked`, `done` (others allowed, reuse
  existing ones, see `overview` byStatus). Notes and events carry it as a `status-<word>`
  tag; tasks also keep VTODO STATUS, percent and completion in step, so always use
  `status`, never edit the tag or STATUS by hand. Plan notes (body header `status:` line)
  are updated by the same command.
- Tags are free words without commas. `tag --set` keeps status and folder tags.
- Saved-view notes are hidden from listings; leave them alone.
- Search before creating: look for an existing item or folder first to avoid duplicates.
- Titles identify items for the user: keep them short and plain, no emoji.

## Safety flags

- `--read-only` (or `DAVDART_READ_ONLY=1`): every item write is refused (exit 3). Use it
  by default when the task is only to look.
- `--allow-admin`: required for `collections create`, `rename`, `delete`; also refused
  under `--read-only`. Never pass it unless the user asked for that collection change.
- `collections delete ID --confirm "<exact name>" [--non-empty] [--backup-dir D]`: needs the
  exact name, refuses a non-empty collection without `--non-empty`, and writes an ICS
  backup first (CalDAV has no trash); report the backup path. Run it with `--dry-run`
  first and show the plan to the user.
- `--collection HREF|NAME`: run an item command in another collection under the home instead of
  the configured one (names and hrefs from `collections list`; anything not listed is refused).
- `collections list`, `collections probe [ID]` (what the server supports, for example
  whether it accepts events or notes) are read-only and safe.
- Exit codes: 0 ok, 1 failed, 2 usage, 3 refused by a flag. Errors are plain text on stderr
  (a JSON `{"error":...}` with `--json`).

## When to ask a human

- Before any delete of more than one item, any `collections` change, or any move that
  reorganises a whole folder: show the `--dry-run` result and ask.
- When two items match an ID (the error lists them) and you cannot tell which one is meant.
- When a status word, folder or tag you would need does not exist yet.
- When the server refuses (rights, a collection that does not hold that kind): report it,
  do not work around it with another credential or another collection.
- Rights and sharing cannot be changed through CalDAV: tell the user to ask the server admin.

## Old commands

`board`, `show`, `add`, `new`, `set-status`, `append`, `task`, `folder`, `export`, `rm` still
work with their old output. Prefer the generic commands above.
