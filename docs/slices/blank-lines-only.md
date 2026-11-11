# Slice 19: linking a note no longer rewrites the note's last element

## Goal

When Claude links a note or adds a line beside an element, an element whose only change is the blank lines after it keeps the text the owner typed, and only those blank lines change.

## Who uses it the day it lands

The owner and the second user, through roam-distill, on the next link to a note that ends in a typed table, list or source block.

## Stakes

`sns-roam-append-link` adds a blank line after the last body element on every call, so that element counts as changed and is written in org's form (issue #17). In the slice 14 tests on 2026-11-11 a note ending in `#+BEGIN_SRC sh` came back as `#+begin_src sh` with its body indented. Linking happens several times a week, and each time the owner sees a change in text they never asked to touch.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- An element whose content changes as well as its blank lines. It is still written in org's form.
- Fixing this in org-ml (ndwarshuis/org-ml#64).

## Invariants

- Edits stay AST-based. The text written for a blank-line change is the blank lines `org-ml-to-string` prints for the new `:post-blank`, at the end of the element's span from the parse; nothing else is written for that element (owner's decision, 2026-11-11; slice 14).
- `sns-roam--check-edits` still parses a copy before any write and refuses a mismatch (slice 14).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S19.1 Linking a note that ends in a typed source block
  Given a note whose body ends in `#+BEGIN_SRC sh`, `echo hi`, `#+END_SRC` with no blank line after it
  When the owner asks Claude to link the note to another note
  Then a `diff` of the file shows only a blank line and the new link paragraph added, and the three block lines are byte-identical

Scenario: S19.2 Adding a line after a typed table
  Given a note whose body is "Intro." then the table `|a|b|` with no blank line after it, then "Outro."
  When the owner asks Claude to add the paragraph "New." after the table
  Then a `diff` shows only "New." added with a blank line before and after it, and `|a|b|` and "Outro." are byte-identical

## Facts the builder needs

- `sns-roam--kept-index` (near line 728) keeps a child only when its `org-ml-to-string` text equals the parsed child's. The change: also keep a child whose text matches after setting its `:post-blank` to the parsed child's, and emit an edit that replaces only the blank lines at the end of that child's span with those for the new `:post-blank`.
- `sns-roam--section-edits` and `sns-roam--run-edit` are pure and see no buffer. Where the blank lines begin is a buffer fact, so the edit can carry the child's `:end` and its old and new `:post-blank`, and `sns-roam--apply-edits` can find the blank lines' start there. The edits still run last in the buffer first.
- `sns-roam--insert-beside` (near line 1103) is what sets `:post-blank` on the anchor and the new element.
- The slice 14 test `sns-roam-append-link-after-an-unterminated-source-block` expects the block in org's form today; it changes to expect the typed text.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has a test per scenario that compares the file text before and after with `sns-roam-test--changed-lines`, and the builder shows both failing on `main`. A test of an element whose content and blank lines both change shows it still written in org's form. A test calls `sns-roam--section-edits` on a spacing-only change and shows that its edit's text is only newlines and that the edit starts after the element's last non-blank character. The existing tests pass, including slice 14's. `mise run check` and `mise run test` pass.
