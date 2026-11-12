# Slice 24: Claude shows exactly what an edit changed in a note

## Goal

After Claude edits a note through sns-roam, it shows the user a diff of the note's file before and after, so a lost or changed line is visible at once instead of being found later by hand.

## Who uses it the day it lands

The owner and the second user, in roam-distill's verify steps, after the next edit, link, rename or history line.

## Stakes

On 2026-11-10 `sns-roam-replace-element` replaced a two-line paragraph with a one-line paragraph, returned success, and only a manual `diff` against a saved copy showed the lost "History, newest first:" line (issue #10). Edits happen several times a week, and each one today returns only `(:id :file)`.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- A diff for `sns-roam-create-node`, whose file did not exist before.
- Showing the diff before the write; the skills already show the planned change and ask first.

## Invariants

- Each primitive's existing return keys keep their values; `:diff` is added (issue #10). `sns-roam-set-property` and `sns-roam-set-keyword` return `t` today, and now return `(:id :file :diff)`, which a caller testing for success still reads as true.
- An edit refused before it writes returns no diff and writes nothing, as now (slice 14). `sns-roam-rename` keeps its documented order: when the new filename exists, the new title stays saved and the `sns-roam-file-exists` error is raised, with no diff.
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S24.1 A replaced paragraph that lost a line shows the loss
  Given a note whose paragraph reads "Open: renewal date." then "History, newest first:" on the next line
  When Claude replaces that paragraph with "Open: renewal date." alone
  Then the user sees a diff with the line "-History, newest first:"

Scenario: S24.2 An edit that changes nothing shows no diff
  Given a note whose `KIND` property is "reference"
  When Claude sets `KIND` to "reference"
  Then Claude reports that the note did not change, and `:diff` is the empty string

## Facts the builder needs

- `:diff` goes on the plists of `sns-roam-set-body`, `sns-roam-replace-element`, `sns-roam-insert-element`, `sns-roam-append-link`, `sns-roam-set-property`, `sns-roam-set-keyword` and `sns-roam-rename`. The first six write through `sns-roam--update-section`, which already holds the widened text before the edits and, in `sns-roam--check-edits`, the text after them on a copy. `sns-roam-rename` calls `sns-roam-set-keyword`, then renames the file; its `:diff` is the title change.
- The diff comes from the system `diff -u`, run with `call-process` on two temporary files and `--label` set to the note's file name, so the output names the note, not the temporary files. Exit status 0 gives "", 1 gives the output, and anything else raises an `sns-roam:` error declared with `sns-roam-define-error` (slice 22).
- `diff` is on macOS and Linux. The README's requirements line names it.
- In `skills/roam-distill/SKILL.md`, each VERIFY step that follows one of the seven primitives shows `:diff` to the user, and says "no change" when it is empty. The draft pipeline's VERIFY after `sns-roam-create-node` is unchanged.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has a test for S24.1 that asserts `:diff` holds "-History, newest first:" and names the note's file, and one for S24.2 asserting `:diff` is "". Each of the seven primitives has a test showing its other keys unchanged and `:diff` holding the lines its change added or removed, such as the new link paragraph for `sns-roam-append-link` and the new `#+title:` line for `sns-roam-rename`. The builder runs S24.1 through `claude -p` against a separate Emacs server and shows Claude's reply with the diff. `mise run check` and `mise run test` pass.
