# Slice 21: Claude tells one kind of sns-roam failure from another without reading the message

## Goal

Every sns-roam failure says which kind it is and carries its facts as data, so the skills act on the kind, such as asking for a sync when a note's file is missing, and never on the wording of a message.

## Who uses it the day it lands

The owner and the second user, through roam-fetch and roam-distill, the next time a call fails; and anyone calling the API from their own Lisp.

## Stakes

All 26 `sns-roam:` errors are plain `error`s whose facts exist only in a sentence (issue #16). The reviews of slices 9, 11, 12, 13 and 20 raised this. The skills now find the missing-file case by matching its text, and 33 test assertions match exact wording, so rewording a message breaks Claude's behaviour silently.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- New failure cases, and any change to when an error is raised.
- Errors from org-roam, org-ml or Emacs itself, which pass through unchanged.

## Invariants

- Every failure is still loud, and every message the user sees starts with `sns-roam:` (AGENTS.md: failure is loud, with the `sns-roam:` prefix).
- A handler on `error` still catches every sns-roam failure, because `sns-roam-error` is a child of `error`.
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S21.1 A moved note and an unknown note get different answers
  Given a note whose file was renamed after the last sync, and an ID that names no note
  When the user asks Claude, through roam-fetch, about each
  Then Claude asks for `M-x org-roam-db-sync` for the moved note, and says no note has that ID for the other

Scenario: S21.2 A batch reports why each note failed
  Given two reference notes, the second with its newest history line twice
  When the user asks Claude to add a history line to both
  Then Claude reports the second note's failure as `sns-roam-match-count` with the count 2, and offers nothing to apply

## Facts the builder needs

- Define the conditions with `define-error` in one place in `src/roam-api.org`, near the top: a parent `sns-roam-error` with message `sns-roam: error`, and eleven children, each with a message starting `sns-roam: `. They are, with their data in order: `unknown-id` (id); `missing-file` (id, path); `malformed-note` (file, what is missing); `match-count` (operation, count); `unsupported-element` (operation, type); `history-layout` (reason); `bad-date` (date); `reparse-mismatch` (file); `file-exists` (path); `id-conflict` (id, registered path, new path); `index-failure` (id, paths). Each name takes the `sns-roam-` prefix.
- `grep -n '(error "sns-roam' src/roam-api.org` lists the 26 sites. Each becomes `(signal 'sns-roam-KIND (list ...))`. The empty series name in `sns-roam-meeting-note` becomes a `user-error`, because only a person at `M-x` meets it.
- Emacs prints a child condition as its message, a colon, then its data, so `error-message-string` gives, for example, `sns-roam: note's file does not exist: "ID", "/path"`.
- The skills' scripts catch `sns-roam-error` and write `(:kind (car err) :data (cdr err))`. Their missing-file lines in roam-fetch (near line 400) and roam-distill (near line 537), and the history flow's two `error-message-string` calls (near lines 162 and 194), switch to `:kind`.

## Questions to resolve

None.

## Done when

Every test that matched a message asserts the condition and its data instead, and `grep -c "string-match-p\|cadr err" test/sns-roam-test.el` counts only assertions on data. A test signals each of the eleven conditions and shows `condition-case` on `error` catches it and `error-message-string` starts with `sns-roam: `. The builder runs S21.1 and S21.2 through `claude -p` against a separate Emacs server, and shows Claude's replies. `grep -n '(error "sns-roam' src/roam-api.org` finds nothing. `mise run check` and `mise run test` pass.
