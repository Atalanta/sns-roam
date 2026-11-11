# Slice 10: a note created from several paragraphs keeps them as separate paragraphs

## Goal

A note that `sns-roam-create-node` creates from several paragraphs has one blank line between each pair of paragraphs, so it reads back as the paragraphs it was given, with no `sns-roam-set-body` repair.

## Who uses it the day it lands

The owner, through Claude, in the next roam-distill batch that creates notes with more than one paragraph.

## Stakes

On 2026-11-09 eight notes of two to five paragraphs came out with the paragraphs on consecutive lines, which org reads as one paragraph. Each note needed `sns-roam-set-body` afterwards (issue #5). The owner runs such batches several times a week. A note left unrepaired shows its claims run together and gives later edits by element the wrong paragraph to match.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- A blank line between `#+title` and the first paragraph, or before the first headline. `sns-roam-set-body` writes neither, and this slice matches it.
- Spacing inside headlines that ELEMENTS passes in.

## Invariants

- The property drawer and `#+title` are written as before, with no blank line between them. org-roam reads the note's ID from the drawer at the top of the file, and `sns-roam-set-body` keeps this layout, so the two primitives write the same header.
- `sns-roam-create-node` still adds the new note to the database before it returns, and still refuses an existing path or an ID another file holds (slice 9, `docs/slices/create-node-registers.md`).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S10.1 Three paragraphs stay three paragraphs
  Given three paragraphs, "One.", "Two." and "Three."
  When the owner's batch creates a note from them
  Then the file shows them under `#+title` with one blank line between each pair and one newline after "Three."
  And `sns-roam-excerpt` at the start of "Two." returns the text "Two." alone

Scenario: S10.2 Paragraphs before a headline
  Given two paragraphs, then a headline "Head" with the paragraph "Under."
  When the owner's batch creates a note from them
  Then the file shows "One.", a blank line, "Two.", then "* Head" on the next line and "Under." below it

Scenario: S10.3 A paragraph that already asks for more space keeps it
  Given a paragraph "One." built with two blank lines after it, then "Two."
  When the owner's batch creates a note from them
  Then the file shows two blank lines between "One." and "Two."

## Facts the builder needs

- `sns-roam-create-node` is in `src/roam-api.org` near line 1100. It builds the section from the drawer, the `#+title` keyword and the body elements before the first headline, and joins it with the headlines using `org-ml-to-string`. `org-ml-build-paragraph` returns a paragraph with `:post-blank` 0, which is why consecutive paragraphs share no blank line. `org-ml-set-property :post-blank N` sets it.
- A batch Emacs run on 2026-11-11 created "One.", "Two." and a headline, and wrote `#+title: Probe\nOne.\nTwo.\n* Head\nUnder.\n`. `sns-roam-set-body` on the same note wrote `One.\n\nTwo.\n* Head`.

## Questions to resolve

None.

## Done when

The builder adds ert tests for S10.1, S10.2 and S10.3 and a test for a single paragraph to `test/sns-roam-test.el`. It shows S10.1 failing before the change, because the file holds "One.\nTwo.", then all four passing after it. Each test compares the file text from `#+title` to the end, so it would see a blank line added after `#+title` or before "* Head". The slice 9 tests still pass. `mise run check` and `mise run test` pass.
