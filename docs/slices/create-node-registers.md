# Slice 9: a note created in a batch can be edited and linked in the same batch

## Goal

A note that `sns-roam-create-node` creates can be edited, expanded and found through its links straight away, with no `org-roam-db-sync` first.

## Who uses it the day it lands

The owner, through Claude, in the next roam-distill batch that creates notes and then edits them.

## Stakes

On 2026-11-09 a batch called `sns-roam-set-body` on each node straight after creating it, and failed seven times with `sns-roam: no roam node with id "…"` (issue #6). Each failure stops the batch partway, with some notes written and others not. The owner runs such batches several times a week for as long as the slipbox is in use.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Updating the database after `sns-roam-append-link`, `sns-roam-set-body` or the other edits. A link they add still needs `org-roam-db-sync` to show as a backlink.
- Removing the `org-roam-db-sync` steps from the roam-distill skill, and the temporary instructions issue #9 proposes.
- Blank lines between body elements (issue #5).

## Invariants

- `sns-roam-create-node` still refuses to overwrite an existing file, leaves that file and its database rows as they were, and adds no row when it refuses. A row for a file that was not written would make a later lookup of that ID resolve to the wrong note (AGENTS.md: failure is loud, no code path guesses).
- No test reads or writes the owner's slipbox or its database. The test macro's docstring states this for the slipbox, and the database at `~/.emacs.d/org-roam.db` is part of it.
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S9.1 A new note can be edited at once
  Given a slipbox whose database holds no note titled "Batch claim"
  When the owner's batch creates "Batch claim" and calls `sns-roam-set-body` on the returned ID
  Then `sns-roam-set-body` returns the note's file, and the file holds the new body under the original `#+title`

Scenario: S9.2 A new note's links show as backlinks at once
  Given a slipbox with an existing note "Hub", already in the database
  When the owner's batch creates "Spoke" with a body that links to "Hub"
  Then `sns-roam-expand` on "Hub" returns a backward edge from "Spoke"

## Facts the builder needs

- `sns-roam-create-node` is in `src/roam-api.org` near line 1080. It writes the file with `write-region` and returns `(:id :title :file)`.
- Every edit primitive resolves the ID through `sns-roam--node-file-or-error` (line 460), which calls `org-roam-node-from-id`, which reads the database.
- `org-roam-db-update-file FILE-PATH` is at `~/.emacs.d/elpa/org-roam-20260425.1623/org-roam-db.el` line 559. It indexes the file's nodes and links.
- The database file is `org-roam-db-location`, by default `~/.emacs.d/org-roam.db`. `mise run test` starts Emacs with `--quick`, so `test/sns-roam-test.el` is the first code to load org-roam. Today the test file does not set the location. Setting it to a temporary path before `(require 'org-roam)` keeps the default from ever being the value, because `defcustom` keeps a value set before it runs. Each test closes the connection with `org-roam-db--close`.
- `sns-roam-meeting-note` calls `sns-roam-create-node`, so its notes become registered too.

## Questions to resolve

None.

## Done when

The builder adds ert tests for S9.1 and S9.2 to `test/sns-roam-test.el`, runs them before the change and shows S9.1 failing with `sns-roam: no roam node with id`, then shows both passing after it. A third test registers an existing note, creates a note at the same path, and sees the overwrite error. It then shows the existing file byte-identical, the rows of every database table equal to those before the call, and no row for the ID it passed. A fourth test shows `org-roam-db-location` is the temporary path the test file set before loading org-roam, so nothing in the run, setup included, could open the owner's database. The owner's `~/.emacs.d/org-roam.db` modification time is the same before and after `mise run test`. `mise run check` and `mise run test` pass.
