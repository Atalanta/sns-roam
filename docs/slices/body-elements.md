# Slice 11: Claude reads a note's body through the API before editing part of it

## Goal

When the owner asks Claude to change part of a note, Claude shows the note's current paragraphs from one `sns-roam-*` call, not from reading the note's file directly.

## Who uses it the day it lands

The owner, through Claude's roam-distill transform flow, the next time they update a reference note or retighten a claim.

## Stakes

On 2026-11-09 updating two reference notes needed their existing paragraphs. The only way to get them was `insert-file-contents` and splitting on blank lines, which the roam-distill skill forbids (issue #7). The owner meets this several times a week, and a body read wrongly leads straight to an edit that replaces the wrong paragraph.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Reading the content under a headline (issues #1 and #2).
- The reference-note update flow and its other steps (issue #9).

## Invariants

- Reading a body writes nothing: the note's file keeps its bytes and its modification time. A read that saved could reformat a note the owner never asked to change (AGENTS.md: edits to a body go through `sns-roam--update-section`).
- An unknown ID raises an error with the `sns-roam:` prefix (AGENTS.md: failure is loud).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S11.1 Claude shows a reference note's paragraphs before an edit
  Given a note with a drawer, `#+title`, `#+filetags`, three paragraphs, then a headline "History" with a paragraph
  When the owner asks Claude to change the second paragraph
  Then Claude shows the three paragraphs, in order, as the before text, with no header line and nothing from "History"

Scenario: S11.2 Unsaved edits in Emacs are what Claude shows
  Given the owner has the note open in Emacs and has changed "£100" to "£120" in a paragraph without saving
  When the owner asks Claude to change that paragraph
  Then Claude shows the paragraph with "£120", the text the edit will replace

Scenario: S11.3 A note with no body
  Given a note with only a drawer and `#+title`
  When the owner asks Claude to change its body
  Then Claude reports that the note has no paragraphs before its first headline

## Facts the builder needs

- The new public function is `sns-roam-body-elements ID`, in `src/roam-api.org`, returning `(:id ID :file FILE :elements NODES)`, with `:elements` nil for an empty body. Issue #7 says it returns the elements, and AGENTS.md says functions return plists, so the plist wins.
- `sns-roam--update-section` (near line 628) resolves the ID with `sns-roam--node-file-or-error` and parses `find-file-noselect`'s buffer, which holds unsaved edits when the note is open. The read parses that same buffer, so Claude shows the text the following edit acts on. `sns-roam--section-header-p` (line 591) picks out the drawer and `#+` keywords.
- In `skills/roam-distill/SKILL.md`, the Read list under "The primitives this skill composes" gains the function, and step 1 of "The transform flow" names it as the way to fetch the body and show it with `org-ml-to-trimmed-string`, and to tell the owner the note has no paragraphs before its first headline when `:elements` is nil.

## Questions to resolve

None.

## Done when

The builder adds ert tests to `test/sns-roam-test.el` for the three paragraphs of S11.1, the unsaved "£120" of S11.2, and the nil `:elements` of S11.3. The S11.1 and S11.2 tests show the file's bytes and modification time equal before and after the call, and the S11.2 test shows the buffer still modified and holding "£120" afterwards. Further tests show a note built by `sns-roam-create-node` from a paragraph and a list coming back as the same two strings, and the `sns-roam:` error on an unknown ID. The builder runs a file-and-load script, as the skill's step 1 describes, on a note in a temporary slipbox and shows the three paragraphs it prints, then on a header-only note and shows `:elements nil`, which step 1 tells Claude to report as no paragraphs. `mise run check` and `mise run test` pass.
