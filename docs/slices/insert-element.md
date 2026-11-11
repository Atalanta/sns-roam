# Slice 12: Claude adds one paragraph to a note without rewriting the others

## Goal

Claude adds a history line to a reference note next to an existing paragraph, and every other paragraph stays exactly as it was.

## Who uses it the day it lands

The owner, through Claude's roam-distill transform flow, the next time an event adds a history line to a reference note.

## Stakes

Each event adds a history line, so the owner adds one several times a week. Today Claude can only rewrite the body with `sns-roam-set-body`, which the skill advises against for a one-element change (issue #8). On 2026-11-10 a rewrite of one paragraph dropped a line, and only a manual `diff` found it (issue #10).

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Inserting under a headline (issue #2), a diff in the return value (issue #10), and the full reference-note update flow (issue #9).

## Invariants

- Every body element other than the new one keeps its text, and the edit maps over the full child list through `sns-roam--update-section`. A call that rewrote a neighbour would repeat the 2026-11-10 loss (issue #10, AGENTS.md rules on the write boundary and parsed child lists).
- A predicate that matches no element or more than one raises an `sns-roam:` error and the file is unchanged (AGENTS.md: failure is loud, no code path guesses).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S12.1 A new history line goes in above the newest one
  Given a reference note whose body is "Edition: Pro.", "Open: renewal date." and "2026-10-24: offered terms."
  When the owner asks Claude to add "2026-11-11: signed a 2-year term." above the 2026-10-24 line
  Then the file shows the four paragraphs in that order, one blank line between each pair, the other three unchanged

Scenario: S12.2 A paragraph added after the last one ends the note
  Given the same note
  When the owner asks Claude to add "See also the vendor list." after the 2026-10-24 line
  Then the file ends with a blank line, then "See also the vendor list." and one newline

Scenario: S12.3 An anchor that matches two paragraphs is refused
  Given a note with two paragraphs that both contain "2026"
  When the owner asks Claude to add a paragraph after the one containing "2026"
  Then Claude shows the `sns-roam:` error saying the anchor matched 2 elements, and the file's bytes are as before

## Facts the builder needs

- The new public function is `sns-roam-insert-element ID PRED NEW-ELEMENT &optional AFTER` in `src/roam-api.org`, returning `(:id :file)` (issue #8). PRED sees only body elements, never the drawer or `#+` keywords (`sns-roam--section-header-p`, line 591).
- `sns-roam-replace-element` (near line 850) counts matches with `org-ml-match` and edits through `sns-roam--update-section`. `sns-roam--map-children` (line 596) explains why the child list must be filtered and mapped whole, never sliced.
- Spacing (`:post-blank`): at least one blank line separates the new element from each body element beside it, because org joins a paragraph to prose or a table that follows with no blank line. A gap that had more blank lines keeps them, as slice 10 keeps extra spacing, and none appears before the first headline. Two plain lists side by side still merge, because org ends a list only at two blank lines; this slice does not insert lists next to lists.
- In `skills/roam-distill/SKILL.md`, the Write list gains the function, and step 2 of "The transform flow" names it for adding one element.

## Questions to resolve

None.

## Done when

The builder adds ert tests to `test/sns-roam-test.el` for S12.1, S12.2 and S12.3, and one for inserting before the first body element. S12.1 and S12.2 compare the file text from `:END:` to the end. S12.3 and a test whose predicate matches nothing compare the file's bytes before and after and show the `sns-roam:` error. A test inserts after a paragraph with two blank lines after it and shows one blank line before the new paragraph and two after it. Tests insert a paragraph after a table that prose follows with no blank line, and before that table, and show `sns-roam-body-elements` returning the table, the new paragraph and the prose as separate elements. The builder runs S12.3 through a file-and-load script, as the skill describes, and shows the error text it writes to the `.out` file. The owner reads the skill's diff and sees the Write list entry and the step 2 choice for adding one element. `mise run check` and `mise run test` pass.
