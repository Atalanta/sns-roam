# Slice 29: Claude adds a paragraph under a heading, and the rest of the note stays as typed

## Goal

When the owner asks Claude to add a paragraph under a heading, Claude adds it at the end of that heading's own text, before any child heading, and every other line of the note stays as the owner typed it.

## Who uses it the day it lands

The owner, through roam-distill, the next time they add to a section of one of the 21 notes with headings; today the skill tells them to edit those by hand.

## Stakes

The write boundary stops at the first heading, so no edit can reach content under one (issue #2). Writing under a heading through org-ml's own update rewrites the subtree: a `1)` list came back as `1.` on 2026-11-09. The owner chose edits that change only the touched elements (slice 14).

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Replacing or inserting next to a chosen element under a heading, setting a body under a heading, and editing a heading's own title line.

## Invariants

- The edit goes through the write boundary's rules, extended to a heading's own section: only changed elements are written, the edit is checked on a copy before writing, and `:diff` is returned (slices 14, 19, 24).
- An outline path that matches no heading, or more than one, raises an `sns-roam-` error with the path, and the file is unchanged (AGENTS.md: failure is loud, no code path guesses).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S29.1 Adding under a heading with a typed list
  Given a note whose `* Projects` section holds the list `1) Alpha` and `2) Beta`
  When the owner asks Claude to add "Gamma starts in December." under Projects
  Then the diff adds only that paragraph and its blank line, after the list, and both list lines keep `1)` and `2)`

Scenario: S29.2 Adding under a heading that has child headings
  Given a note whose `* Projects` has its own paragraph and then `** Tickets`
  When the owner asks Claude to add "Gamma starts in December." under Projects
  Then the paragraph sits after Projects' own paragraph and before `** Tickets`, and `** Tickets` is unchanged

Scenario: S29.3 A path that names two headings is refused
  Given a note with two `* Notes` headings
  When the owner asks Claude to add a paragraph under Notes
  Then Claude reports that the path matched 2 headings, and the file is unchanged

## Facts the builder needs

- New `sns-roam-add-under-heading ID OUTLINE-PATH NEW-ELEMENT` takes a path of heading titles such as `("Projects" "Tickets")` and a paragraph node, and returns `(:id :file :point :diff)`, `:point` being where the paragraph starts. It refuses a non-paragraph as `sns-roam-insert-element` does.
- `sns-roam--update-section` (near line 993) works on the first section only: `sns-roam--edit-section` takes the parse's first child, and `sns-roam--check-edits` (near line 1316) compares the first section's children. Both need to target a chosen heading's own section instead, including one that is empty.
- In `skills/roam-distill/SKILL.md`, the Write list gains the function, and the lines near 272, 448 and 519 that send heading edits to the owner say that adding a paragraph under a heading now goes through it. The transform flow's step 1 reads a heading's section with `sns-roam-subtree`, at the point `sns-roam-body-search` gives for the heading's title, when the change is under a heading, instead of stopping at an empty `sns-roam-body-elements`.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has tests for S29.1, S29.2 and S29.3, comparing the file before and after with `sns-roam-test--changed-lines`, plus a heading with an empty section, a path that matches nothing, and a nested path `("Projects" "Tickets")`. A test forces a heading edit that would read back as merged paragraphs and shows it refused with `sns-roam-reparse-mismatch`, the file unchanged, and the visiting buffer's text unchanged and unmodified. The builder shows S29.1 on `main` impossible through the API, and runs S29.1 through `claude -p` against a separate Emacs server, on a note with no text before its first heading. `mise run check` and `mise run test` pass.
