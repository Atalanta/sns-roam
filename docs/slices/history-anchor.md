# Slice 13: Claude adds an event to a reference note's history in date order

## Goal

When the owner tells Claude about an event, Claude adds a dated history line to the subject's reference note at its place in date order. Every other paragraph stays as it was, and nothing is written until the owner has seen the change.

## Who uses it the day it lands

The owner, through Claude's roam-distill skill, the next time an email or a meeting adds to a reference note's history.

## Stakes

Each event adds a history line, several times a week. On 2026-11-09, with no documented flow, Claude read the note files directly and rewrote each body with `sns-roam-set-body` (issue #9). A first build of this slice put 14 functions and two global variables into `SKILL.md`, outside `src/` and the naming rule, so this plan puts the placement decision in the API.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Changing the "Current state:" or "Open:" paragraph, which the transform flow's `replace-element` step does as its own change, and notes in other layouts, which the new call refuses.

## Invariants

- Placement logic is in `src/roam-api.org` under a public `sns-roam-` name; the skill holds steps and short scripts, with no `defun` or `defvar` (AGENTS.md layout and naming rules).
- Finding the anchor writes nothing, and no write happens before the owner confirms (AGENTS.md write boundary; the skill's show, confirm, apply rule).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S13.1 An older event goes in between the newer and older lines
  Given a reference note whose history is "2026-11-09: ..." then "2026-11-06: ..."
  When the owner tells Claude about a meeting on 2026-11-08
  Then Claude shows the new line "2026-11-08: ..." between the 2026-11-09 and 2026-11-06 lines, and asks to apply

Scenario: S13.2 A note in another layout stops a batch before anything is offered
  Given two notes, and the second has its history under a `* History` heading
  When the owner asks Claude to add a 2026-11-12 event to both notes
  Then Claude reports that the second note's layout is not supported, offers nothing to apply, and neither file changes

Scenario: S13.3 The applied note keeps every other paragraph
  Given the note from S13.1 also holds "Related claims:" with a link, and the owner confirms
  When Claude applies the update
  Then the file shows the history as 2026-11-09, 2026-11-08, 2026-11-06, and every other paragraph, the link included, has the same text as before

## Facts the builder needs

- Supported layout, from the owner's reference notes since 2026-11-09: paragraphs only, no headings, tables or lists. A "Current state:" paragraph, an "Open:" paragraph, an optional "Related claims:" paragraph, then one paragraph per history line, newest first, each starting `YYYY-MM-DD:`. Fixtures are invented, never the owner's notes.
- New `sns-roam-history-anchor ID DATE`, read-only, returns `(:id :file :anchor TEXT :after BOOL)`. TEXT is the trimmed text of the first history line dated on or before DATE, with `:after` nil. With no such line, TEXT is the last paragraph's and `:after` is t. It parses all of the buffer that `sns-roam-body-elements` reads, headings included. It raises an `sns-roam:` error for a DATE that is not `YYYY-MM-DD`, a heading or non-paragraph element, an empty body, dated lines that are not one run at the end of the body, newest first (an undated paragraph after the first dated one breaks it), or a TEXT that appears twice.
- The skill's flow, in "Reference and person notes": call `sns-roam-history-anchor` for every note first, report every error and stop; otherwise show each change, confirm, and call `sns-roam-insert-element` with a predicate comparing `org-ml-to-trimmed-string` to TEXT.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` tests the new call for a middle date, a newest date, an oldest date and a date equal to an existing line. It also tests each refusal above, including an "Open:" paragraph after a dated line, and an unknown ID. One test shows the file's bytes and modification time unchanged after the call. The builder runs the flow's file-and-load scripts on invented notes in a temporary slipbox. It shows the `.out` text for S13.1 with the note's bytes equal before and after the preview, the `.out` text for S13.2 with both files' bytes unchanged, then the file text after S13.3. `grep -n "(defun\|(defvar" skills/roam-distill/SKILL.md` shows nothing new. `mise run check` and `mise run test` pass.
