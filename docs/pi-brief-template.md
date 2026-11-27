# Pi brief template (davdart)

Copy this into the brief and fill the top section. Keep it short: a worker
reads it once, then the code.

## Brief

- Repo/worktree: `~/bot-repos/davdart-<name>` on branch `<name>`
  (`git worktree add ../davdart-<name> -b <name> main`, skip if it exists).
- Baseline: the commit the branch starts from (`git rev-parse --short HEAD`),
  so the caller can diff the whole task.
- Setup: `cd apps/app && flutter pub get --offline`; PATH needs
  `~/bot-repos/davdart/dart-sdk/bin` and `.../flutter-sdk/bin`.
- Read first: `memory/components-and-tokens-rule.md` and the report the brief
  refers to.
- Do: the ordered steps, one small commit each.
- Touch only: `apps/app/lib/ui`, `apps/app/test` (existing files for the
  widgets in scope) and `docs`.

## Rules every brief carries

- Gates: no push, no deploy, no browser or dev-server check, no new services,
  no attribution of any kind (no Co-Authored-By, no "generated with") in
  commits, PRs or docs.
- Components: repeated UI is one shared parameterised component
  (`CardBox`, `Surface`, `CountBadge`, `EmptyState`, `SectionLabel`, ...),
  styled only from `tokensOf(context)`. A literal, or a hand-built copy of an
  existing piece, in a call site is a bug; fix the call site, never weaken
  `test/design_rules_test.dart`.
- Allowlists only shrink: when a private copy or a literal is removed, delete
  its entry in `test/design_rules_test.dart` (`_privateWidgets`, per-rule
  `allow` counts) in the same commit. A stale entry fails the test.
- Visual result unchanged except where the report says the old value was
  wrong; list every visible change in the report.
- Keep existing widget keys so tests keep passing; update tests only for a
  deliberate change, never delete coverage.
- Commit as you go: nothing may be left uncommitted when you report.

## What to run

- Per commit: `dart format lib test`, `flutter analyze`, and the tests touching
  the changed widgets (`flutter test test/<name>_test.dart ...`).
- Once at the end: `flutter test -j 1` (about 7 minutes) in the background.
- Report to the caller who sent the task (`hc`): under 250 words, commit
  hashes, visible changes, anything skipped and why.
