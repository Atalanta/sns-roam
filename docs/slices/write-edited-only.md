# Slice 14: an edit through the API changes only the elements it was asked to change

## Goal

When Claude edits a note through the API, every element the edit did not change keeps its exact text. Hand-typed tables, lists and source blocks stay as the owner typed them.

## Who uses it the day it lands

The owner, through Claude's roam-distill flows, on the next edit, link or rename in any note with a table or list.

## Stakes

On 2026-11-11 `sns-roam-replace-element` on a note's intro paragraph also rewrote `|a|b|` as `| a | b |`, `+  item one` as `- item one`, and a table under an untouched `* Notes` headline (issue #14). Every edit and every rename does this, several times a week. The owner sees changes in notes they never asked to change, and a diff of any edit (issue #10) would be full of them.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Keeping the typed form of an element the edit does change. A changed table or a paragraph whose blank lines changed is written in org's form.
- A fix in org-ml itself (ndwarshuis/org-ml#64), and narrowed buffers (issue #12).

## Invariants

- Edits stay AST-based: org-ml parses the note, the edit transforms nodes, and the only text written is `org-ml-to-string` of nodes placed at positions the parse gave. No step edits the note as raw text (owner's decision, 2026-11-11).
- Each primitive writes through one shared function in `src/roam-api.org`, and the slice 12 reparse check still refuses a mismatch (AGENTS.md write boundary).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S14.1 Replacing a paragraph leaves a typed table and list alone
  Given a note with "Intro.", `|a|b|`, `+  item one`, then `* Notes` with `|c|d|` under it
  When the owner asks Claude to replace "Intro." with "New intro."
  Then a `diff` of the file before and after shows only the "Intro." line changed

Scenario: S14.2 Linking a note leaves the rest alone
  Given the note from S14.1
  When the owner asks Claude to link it to another note
  Then a `diff` shows only the new link paragraph and its blank line added

Scenario: S14.3 Renaming a note changes only its title line
  Given the note from S14.1
  When the owner asks Claude to rename it
  Then a `diff` shows only the `#+title:` line changed, and the file has its new name

## Facts the builder needs

- `sns-roam--update-section` (line 628) calls `org-ml-update-this-buffer`, which writes all of the tree with `org-element-interpret-data` and applies a text diff, so every non-canonical element changes. `sns-roam-set-property` (near line 500) and `sns-roam-set-keyword` (near line 1215) `erase-buffer` and insert all of the tree. `sns-roam-rename` calls `sns-roam-set-keyword`.
- After a transform, untouched children are copies, not `eq` to the parsed nodes, but they keep the parse's begin and end positions (checked 2026-11-11: a table's copy kept 9 and 16).
- The rule: compare each new section child with the parsed child at the same begin position by `org-ml-to-string`. Equal means unchanged and nothing is written there. For each run of changed, new or removed children, replace the buffer between the run's old bounds with `org-ml-to-string` of its new nodes, working from the end of the buffer back. Headlines after the section are never written.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has a test per scenario that compares the file text after the edit with the text before, with only the expected lines changed. Further tests do the same for `sns-roam-set-body`, `sns-roam-insert-element` and `sns-roam-set-property` on a note with `|a|b|`, `+  item one` and a source block. The builder shows the S14.1 test failing on `main` with `| a | b |` in the file. `grep -n "erase-buffer\|org-ml-update-this-buffer" src/roam-api.org` shows no code match. The owner reads the shared function and sees that the only text it inserts is `org-ml-to-string` output, at bounds from the parse, and that each edit primitive and `sns-roam-set-keyword` call it. `mise run check` and `mise run test` pass.
