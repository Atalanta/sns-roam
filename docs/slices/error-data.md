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

- Every failure is still loud, and every message the user sees starts with `sns-roam:` (AGENTS.md). The rest of the wording changes to the condition's message followed by its data, which the owner approved on 2026-11-11 in place of issue #16's "the message text stays as it is".
- A handler on `error` still catches every sns-roam failure, because `sns-roam-error` is a child of `error`.
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S21.1 A moved note and an unknown note get different answers
  Given a note whose file was renamed after the last sync, and an ID that names no note
  When the user asks Claude, through roam-fetch, about each
  Then Claude asks for `M-x org-roam-db-sync` for the moved note, and says no note has that ID for the other

Scenario: S21.2 A batch reports why each note failed
  Given two reference notes, the second with its newest history line, "2026-11-11: weekly check-in.", twice
  When the user asks Claude to add a history line dated 2026-11-12 to both
  Then Claude reports the second note's failure as `sns-roam-match-count` with the count 2, and offers nothing to apply

## Facts the builder needs

- Define the conditions with `define-error` in one place near the top of `src/roam-api.org`: a parent `sns-roam-error` (message `sns-roam: error`, parent `error`) and twelve children, each with a message starting `sns-roam: `. Each signals a plist that starts with `:kind`, the condition's symbol, has `:id` whenever the call had a node ID, then the facts: `unknown-id`; `missing-file` (`:path`); `malformed-note` (`:file`, `:missing`); `no-excerpt-container` (`:point`, `:file`); `match-count` (`:operation`, `:count`); `unsupported-element` (`:operation`, `:type`); `history-layout` (`:reason`, and `:dates` where two dates are out of order); `bad-date` (`:date`); `reparse-mismatch` (`:file`, `:planned`, `:actual`); `file-exists` (`:path`); `id-conflict` (`:registered`, `:path`); `index-failure` (`:expected`, `:actual`). Each name takes the `sns-roam-` prefix. Each plist also carries every value the current message names, such as `:anchor` for a duplicated history line. `:missing` is one of `section`, `property-drawer` or `roam-filename` (the rename refusal for a file not named `TIMESTAMP-SLUG.org`). `:reason` is one of `no-paragraphs`, `not-one-run` or `not-newest-first`. `:operation` is the public function's symbol, such as `sns-roam-insert-element`.
- `grep -n "(error " src/roam-api.org` lists every site, including the missing-file helper near line 474, which formats its message through `%s`. Each becomes `(signal 'sns-roam-KIND (list :kind 'sns-roam-KIND ...))`. The empty series name in `sns-roam-meeting-note` becomes a `user-error`, because only a person at `M-x` meets it.
- The skills' scripts catch `sns-roam-error` and write `(cdr err)`, the plist. Their missing-file lines in roam-fetch (near line 400) and roam-distill (near line 537), and the history flow's two `error-message-string` calls (near lines 162 and 194), switch to `:kind`.

## Questions to resolve

None.

## Done when

Every test that matched a message asserts `:kind` and the data instead. For every site that `grep -n "(error " src/roam-api.org` lists on `main`, a test makes the public function that reaches it raise its condition, such as `sns-roam-excerpt` at a headline for `sns-roam-no-excerpt-container` and `sns-roam-replace-element` with a two-match predicate for `sns-roam-match-count`, and asserts `:kind` and every key the Facts list for it. Where a site cannot be reached from outside without stubbing, the test says so and stubs only the call before it. A test signals each condition directly and shows `condition-case` on `error` catches it, `(plist-get (cdr err) :kind)` returns its symbol, and `error-message-string` starts with `sns-roam: `. `grep -n "(error " src/roam-api.org` finds no code, and `grep -n "does not exist\|error-message-string\|matched [0-9]" skills/*/SKILL.md` finds nothing. The builder runs S21.1 and S21.2 through `claude -p` against a separate Emacs server and shows Claude's replies, then rewords `sns-roam-missing-file`'s message in that server with `put` and shows the S21.1 reply unchanged. `mise run check` and `mise run test` pass.
