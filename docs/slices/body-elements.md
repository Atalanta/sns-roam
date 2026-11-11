# Slice 11: a batch can read a note's body through the API

## Goal

Claude reads the elements of a note's body before its first headline with one `sns-roam-*` call. An edit to part of a body no longer starts by reading the note's file directly.

## Who uses it the day it lands

The owner, through Claude, the next time a batch updates a reference note and needs its current paragraphs.

## Stakes

On 2026-11-09 updating two reference notes needed their existing paragraphs. The only way to get them was `insert-file-contents` and splitting on blank lines, which the roam-distill skill forbids (issue #7). Reference notes change with each event they record, so the owner meets this several times a week. A body read wrongly leads straight to an edit that replaces the wrong paragraph.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Reading the content under a headline (issues #1 and #2).
- Documenting the new primitive in the roam-distill skill (issue #9).
- Notes whose ID is on a headline, not at the top of the file.

## Invariants

- Reading a body writes nothing: the note's file keeps its bytes and its modification time. A read that saved the buffer could reformat a note the owner never asked to change (AGENTS.md: edits to a body go through `sns-roam--update-section`).
- An unknown ID raises an error with the `sns-roam:` prefix, and the call returns nothing for it (AGENTS.md: failure is loud).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S11.1 A reference note's body comes back without its header or headlines
  Given a note with a property drawer, `#+title`, `#+filetags`, three paragraphs, then a headline "History" with one paragraph under it
  When the owner's batch calls `sns-roam-body-elements` on the note's ID
  Then `:elements` holds three elements, which `org-ml-to-trimmed-string` turns into the three paragraphs, in order

Scenario: S11.2 A created note's body comes back as it was built
  Given a note created with `sns-roam-create-node` from a paragraph and a plain list of two items
  When the owner's batch calls `sns-roam-body-elements` on the returned ID
  Then `org-ml-to-trimmed-string` turns the two returned elements into the same strings as the two built elements

Scenario: S11.3 A note with no body
  Given a note with only a property drawer and `#+title`
  When the owner's batch calls `sns-roam-body-elements` on its ID
  Then the call returns the note's `:id` and `:file`, and `:elements` is nil

## Facts the builder needs

- The function is public, `sns-roam-body-elements ID`, in `src/roam-api.org` with the other read primitives. It returns `(:id ID :file FILE :elements NODES)`. Issue #7 says it returns the elements, and AGENTS.md says functions return plists, so the plist wins.
- `sns-roam--update-section` (near line 628) resolves the ID with `sns-roam--node-file-or-error`, then parses the visited file with `org-ml-update-this-buffer`, taking the first child as the top-level section. `sns-roam--section-header-p` (line 591) picks out the drawer and the `#+` keywords that `sns-roam-set-body` keeps.
- The slice 9 tests in `test/sns-roam-test.el` show how to create notes against a temporary database.

## Questions to resolve

None.

## Done when

The builder adds ert tests for S11.1, S11.2 and S11.3 to `test/sns-roam-test.el`. The S11.1 test records the file's bytes and modification time before the call and shows them equal after it. A fourth test calls the function with an unknown ID and shows the `sns-roam:` error. `mise run check` and `mise run test` pass.
