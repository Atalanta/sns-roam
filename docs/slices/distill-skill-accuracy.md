# Slice 4: roam-distill tells Claude what the primitives do

## Goal

When the owner asks Claude to promote a fleeting note, `roam-distill` sets the `KIND` property, and it tells Claude that `sns-roam-set-body` rewrites only the text before the first heading.

## Who uses it the day it lands

The owner, whenever they have Claude distil a braindump and promote or rewrite an existing note.

## Stakes

`turnstile review` on slice 3 raised two findings against `skills/roam-distill/SKILL.md`, and a batch Emacs reproduced both on 2026-11-08. Promotion calls `sns-roam-set-keyword`, which adds `#+kind: permanent` and leaves `:KIND: fleeting` in the drawer, and the call reports success. `sns-roam-set-body` keeps every existing heading, so a rewrite that adds sections leaves the old ones in place. `sns-roam-replace-element` also reaches only the text before the first heading.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Changing the elisp primitives. Editing headings through them is a later slice.
- Wording in the skills unrelated to `KIND` and to what `set-body` and `replace-element` reach, and `roam-fetch`.

## Invariants

- Both skills keep their frontmatter `name` and `description`, so Claude Code keeps offering them.

## Scenarios

Scenario: S4.1 The owner promotes a fleeting note
  Given a test note whose drawer holds `:KIND: fleeting` and a section headed `* Evidence`
  When the owner asks Claude to promote it to permanent and approves the proposal
  Then the drawer holds `:KIND: permanent` and the file has no `#+kind:` line

Scenario: S4.2 The owner asks for a rewrite that changes a heading
  Given the same test note
  When the owner asks Claude to rewrite the note with a different `* Evidence` section
  Then Claude proposes no `set-body` or `replace-element` call for the heading, and tells the owner to edit that section by hand

## Facts the builder needs

- `skills/roam-distill/SKILL.md` line 300 says `set-keyword` KIND. Lines 121 to 123 and 271 to 279 say `set-body` rewrites the whole body, and line 326 repeats it. Line 129 lists `set-keyword`. Checked on 2026-11-08.
- `sns-roam-set-property` (`src/roam-api.org`) writes the drawer. `sns-roam-set-body` replaces the text before the first heading and keeps headings. `sns-roam--update-section` hands `replace-element` only that leading section, so a predicate for a heading matches zero elements. The first two were run in batch Emacs on 2026-11-08; the third is from the code.

## Questions to resolve

None.

## Done when

Step 2 of "Promote a fleeting note" names `set-property`, and `grep -n 'set-keyword' skills/roam-distill/SKILL.md` shows no step that sets `KIND`. Every place that describes `set-body` or `replace-element` (the primitive list, the transform flow, the anti-patterns) agrees that they reach only the text before the first heading, and says headings are edited by hand. In a batch Emacs, the promotion steps run on a temporary note holding `:KIND: fleeting` print `:KIND: permanent` with no `#+kind:` line. Before the change, the same run printed both. After the owner returns, they make the requests in S4.1 and S4.2 to Claude on a test note and see the stated result, then delete the note. `mise run check` and `mise run test` pass.
