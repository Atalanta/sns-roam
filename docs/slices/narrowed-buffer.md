# Slice 23: a note narrowed in Emacs reads and edits as if it were not narrowed

## Goal

When the user has a note narrowed in Emacs, Claude reads and edits all of the note through sns-roam, and the user's narrowing is still in place afterwards.

## Who uses it the day it lands

The owner, who works in Emacs and narrows notes to a subtree, the next time Claude reads or edits a note left narrowed.

## Stakes

On 2026-11-11 a note narrowed to its `* History` subtree read back with no paragraphs, and `sns-roam-set-body` refused it as a note with no top-level section (issue #12). Claude then tells the user something false about the note, or cannot edit it. Narrowing is ordinary Org use.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Narrowing in org-ml's own update functions, which sns-roam no longer calls (ndwarshuis/org-ml#65 covers them upstream).
- Moving point or changing anything else about the user's window.

## Invariants

- The user's narrowing covers the same text afterwards: the same subtree, extended or shortened only by what the edit inserted or removed inside it (issue #12).
- The slice 14 preflight check still parses a widened copy, and a refused edit leaves the buffer and its narrowing as they were (slice 14).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S23.1 Reading a note narrowed to a subtree
  Given a note with "Top paragraph." before `* History`, open in Emacs and narrowed to `* History`
  When the user asks Claude what the note says before its first heading
  Then Claude shows "Top paragraph.", and the buffer is still narrowed to `* History`

Scenario: S23.2 Editing a note narrowed to a subtree
  Given the same narrowed note
  When the user asks Claude to replace "Top paragraph." with "New top."
  Then the file holds "New top." before `* History`, and the buffer is still narrowed to `* History`

## Facts the builder needs

- Three functions parse the visited buffer and so see only the narrowed part: `sns-roam--update-section` (near line 797), `sns-roam-body-elements` (near line 1205) and `sns-roam-history-anchor` (near line 1555). Each parses with `org-ml-parse-this-buffer` inside `find-file-noselect`'s buffer. Each needs `(save-restriction (widen) ...)` around its parse, and around the edits for `sns-roam--update-section`.
- `sns-roam--check-edits` (near line 1049) already widens its copy.
- Org's own check for "the same subtree" is a fresh `org-narrow-to-subtree` on the heading: the org-ml fix for #56 compares the restored `(point-min) . (point-max)` with one.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has tests that narrow a note to `* History` and call `sns-roam-body-elements`, `sns-roam-set-body` and `sns-roam-replace-element`. A test narrows a reference note, which has no headings, to its last history line with `narrow-to-region`, and shows `sns-roam-history-anchor` still choosing its anchor from all of the history and the region unchanged afterwards. Each shows the text outside the narrowing read or edited, and `(point-min) . (point-max)` afterwards equal to a fresh `org-narrow-to-subtree` on `* History`. A test narrows to `* History`, calls `sns-roam-replace-element` with a predicate that matches two paragraphs, and shows the refusal with the buffer unmodified and still narrowed to `* History`. A test narrows to the top paragraph itself, edits it, and shows the narrowing still covers the new paragraph. The builder shows the read and edit tests failing on `main`. `mise run check` and `mise run test` pass.
