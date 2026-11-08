# Slice 1: the owner can test the meeting note

## Goal

The owner runs `mise run test` and sees whether `sns-roam-meeting-note` still creates a dated meeting note, so a change that breaks it fails before it lands.

## Who uses it the day it lands

The owner, each time they change `src/roam-api.org`, which tangles to the code that Emacs and the Claude skills run.

## Stakes

The owner changes this code with Claude's help and has no test for it. On 2026-06-16 someone added `sns-roam-meeting-note` to the generated file by hand, and the org source lacked it until 2026-11-08, so a re-tangle would have deleted it with no error.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Tests for the other primitives.
- Pinning org-roam and org-ml in a flake or a CI image. The tests use the packages in `~/.emacs.d/elpa`.
- Two notes created in the same second, which the function refuses today.

## Invariants

- The tests write only to a temporary directory. Otherwise they would add notes to the owner's actual slipbox, which is the git repository `~/roam` (`sns-roam-directory` in `~/.emacs.d/README.org`).

## Scenarios

Scenario: S1.1 The meeting note carries today's date
  Given an empty org-roam directory
  When the owner starts a note for the series "alan-smithee-1-1"
  Then the directory holds one file, named with a timestamp and `alan_smithee_1_1`
  And the note is titled "alan-smithee-1-1" followed by today's date, with KIND "fleeting"

Scenario: S1.2 A blank series name fails
  Given an empty org-roam directory
  When the owner starts a note with a blank series name
  Then Emacs shows "sns-roam-meeting-note: empty series name"
  And the directory still holds no file, where S1.1 shows it would have held one

## Facts the builder needs

- `sns-roam-meeting-note` and `sns-roam--meeting-title` are in `lisp/sns-roam-api.el`, generated from `src/roam-api.org`. The function calls `sns-roam-create-node` with kind "fleeting" and then visits the new file.
- The file name uses `org-roam-node-slugify`, which turns hyphens into underscores. The note `~/roam/20260610110005-mikalai_1_1.org` is titled "mikalai-1-1".
- A batch Emacs finds org-roam and org-ml only after `package-user-dir` is set to `~/.emacs.d/elpa` and `package-initialize` runs. With the default load path, `(require 'sns-roam-api)` fails. Checked on 2026-11-08.
- `mise.toml` has a `check` task and no `test` task.

## Questions to resolve

None.

## Done when

The owner runs `mise run test` and sees `Ran 2 tests, 2 results as expected` (S1.1, S1.2). The owner then changes `sns-roam--meeting-title` in `src/roam-api.org` to drop the date, runs `mise run test`, and sees S1.1 fail with the title it found. The owner lists `~/roam` before and after a run and sees no new file. `mise run check` passes.
