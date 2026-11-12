# Slice 28: Claude reads a whole section of a note, not just one paragraph

## Goal

When the owner asks Claude about a section of a note, roam-fetch reads all of that section, child headings included, so a line under the heading is found even when it does not repeat the search words.

## Who uses it the day it lands

The owner, through roam-fetch, the next time they ask about something under a heading in one of the 21 of their 138 notes that have headings (counted 2026-11-12).

## Stakes

On 2026-11-09 roam-fetch missed a link in a journal entry: body search hit the section's heading and first line, and `sns-roam-excerpt` returned only the first paragraph, which ends before the line with the link (issue #1). The answer was wrong with no sign of it.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Finding a section by its outline path rather than a point, editing under a heading (issue #2, the next slice), and the stage 2 change issue #1 also proposes, searching every word of a question: in the 2026-11-09 miss, stage 2 found the heading, and reading the section is what failed.

## Invariants

- Reading writes nothing, and the returned text is the note's text as typed, not reprinted by org (AGENTS.md; slice 14's rule on typed text).
- A point that is not in any section raises an `sns-roam-` error declared with `sns-roam-define-error` (AGENTS.md: failure is loud; slice 22).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S28.1 A link under a heading is found from a hit on the heading
  Given a note with `* Dashboards`, whose first paragraph names the team and whose later list item holds a link without the word "dashboard"
  When the owner asks Claude, through roam-fetch, for the dashboards link
  Then Claude answers with that link and cites the note

Scenario: S28.2 An answer about a section includes its child headings
  Given a note with `* Projects` and, under it, `** Tickets` with the paragraph "Ticket triage happens on Mondays."
  When the owner asks Claude, through roam-fetch, what the note says about projects
  Then Claude's answer includes that ticket triage happens on Mondays, and cites the note

## Facts the builder needs

- New `sns-roam-subtree ID POINT` returns `(:id :file :point :text :outline)`, as `sns-roam-excerpt` (near line 554) does: `:text` is the buffer text from the innermost heading's start to its subtree's end, `:outline` the root-to-leaf heading titles. It reads the file the way `sns-roam-excerpt` does and finds the heading with `sns-roam--ancestry-at-point`.
- A POINT before the first heading raises a new kind, `sns-roam-no-heading`, carrying `:point` and `:file`.
- In `skills/roam-fetch/SKILL.md`, stage 4 uses `sns-roam-subtree` for a hit whose point is under a heading, and keeps `sns-roam-excerpt` for a hit before the first heading. The read primitives list gains the function.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` tests `sns-roam-subtree` at a point on a heading line, inside a nested list under it, and in a section with child headings, each asserting `:text` equal to the typed region and `:outline`; each fixture has a following heading at the same level, such as `* Next`, and the test shows its text absent from `:text`; a test shows `sns-roam-no-heading` for a point before the first heading, and one shows the file unchanged after a call. The builder runs S28.1 and S28.2 through `claude -p` against a separate Emacs server and shows both answers. `mise run check` and `mise run test` pass.
