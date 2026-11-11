# Slice 20: a note whose file has moved gets a clear error, not an empty answer

## Goal

When a note's file has been moved or deleted since org-roam last synced, every sns-roam call on that note says the file is missing, and Claude tells the user to sync, instead of reporting an empty note or a malformed one.

## Who uses it the day it lands

The owner and the second user, through roam-fetch and roam-distill, the next time they ask about or edit a note they have just moved or renamed outside Emacs.

## Stakes

On 2026-11-11, with a note's file renamed, `sns-roam-body-elements` returned `:elements nil` as if the note were empty, and `sns-roam-set-body` and `sns-roam-set-property` raised `sns-roam: ... has no top-level section`, which names a malformed file (issue #13). Claude then tells the user something false about their note. A note's file changes path whenever the user reorganises the slipbox or pulls it from another machine.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Syncing the database automatically. The user decides when to sync.
- Closing a buffer the user already has open on the old path. It may hold unsaved edits.

## Invariants

- An unknown ID still raises `sns-roam: no roam node with id ...` (AGENTS.md: failure is loud).
- No call opens a new buffer on the missing path or creates a file there, and a buffer the user already has open there is left as it was (issue #13).

## Scenarios

Scenario: S20.1 Reading a moved note
  Given a note "Tide tables" whose file was moved after the last sync
  When the user asks Claude what the note says
  Then Claude reports that the note's file is missing at its old path and asks the user to run `M-x org-roam-db-sync`

Scenario: S20.2 Editing a moved note
  Given the same moved note
  When the user asks Claude to change one of its paragraphs
  Then the edit raises the same missing-file error, Claude reports it, and no file appears at the old path

## Facts the builder needs

- `sns-roam--node-file-or-error` (near line 461) checks only that `org-roam-node-from-id` finds the ID. Every primitive that opens a note's file resolves the ID through it: excerpt, set-property, `sns-roam--update-section`, append-link's target check, body-elements, history-anchor, set-keyword and rename. The new check, a `file-exists-p` with the error `sns-roam: node ID's file PATH does not exist`, goes there. `sns-roam-expand` reads the centre note's file in `sns-roam--forward-link-edges` (near line 234) with `insert-file-contents`, so it raises the same error before reading.
- The load step in both skills already tells the user to run `M-x org-roam-db-sync` when nothing is indexed. Each skill gains one line: on the missing-file error, report it and ask the user to sync.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has tests that rename a created note's file and call `sns-roam-body-elements`, `sns-roam-expand`, `sns-roam-set-body` and `sns-roam-set-property`. Each shows the missing-file error with the old path, no new buffer on it, and no file there afterwards. One test opens the note first, edits the buffer without saving, renames the file, and shows the buffer still modified and holding the edit after the error. The builder runs a roam-fetch question about the renamed note through `claude -p` against a separate Emacs server, and shows Claude's reply naming the missing file and asking for `M-x org-roam-db-sync`. The builder shows those tests failing on `main`. The owner reads the line each skill gains. `mise run check` and `mise run test` pass.
