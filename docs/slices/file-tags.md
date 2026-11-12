# Slice 26: Claude tags a note, and the tags sit under its title

## Goal

When the owner asks Claude to tag a note, new or existing, the note gets one `#+filetags:` line directly under its `#+title:`, and roam-fetch finds the note by those tags.

## Who uses it the day it lands

The owner, through roam-distill, the next time they tag a note; the owner tags notes now and hit this on 2026-11-12 (issue #19).

## Stakes

Tagging today goes through `sns-roam-set-keyword` with `FILETAGS`, which appends `#+filetags:` after the body because `sns-roam--upsert-keyword` adds a missing keyword at the end of the section. org-roam still indexes the tags, but the line is not where a reader looks, and `sns-roam-create-node` cannot take tags, so a new tagged note needs a second write (issue #19).

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Tags on headings, and adding or removing one tag at a time; `sns-roam-set-tags` sets the whole list.
- Any change to `sns-roam-set-keyword` for other keys.

## Invariants

- Edits stay AST-based and go through `sns-roam--update-section`, which writes only what changed and returns `:diff` (AGENTS.md; slices 14 and 24).
- A tag org would not read as a tag is refused before anything is written (AGENTS.md: failure is loud).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S26.1 Tagging a note with a body
  Given a note with a title and two paragraphs, and no tags
  When the owner asks Claude to tag it `tech_leadership`
  Then the line after `#+title:` is `#+filetags: :tech_leadership:`, and roam-fetch finds the note when asked about `tech_leadership`

Scenario: S26.2 Retagging a note whose tags sit after its body
  Given a note whose only `#+filetags: :old:` line is after its body, as `sns-roam-set-keyword` left it
  When the owner asks Claude to tag it `new`
  Then the note has one `#+filetags: :new:` line, directly under `#+title:`, and the diff shows the old line removed

Scenario: S26.3 A tag org does not allow is refused
  Given a note with no tags
  When the owner asks Claude to tag it `tech-leadership`
  Then Claude reports that `tech-leadership` is not a valid tag, and the note's file is unchanged

## Facts the builder needs

- New `sns-roam-set-tags ID TAGS`, TAGS a list of strings, returning `(:id :file :diff)`. It writes `#+filetags: :t1:t2:` as the keyword right after the `TITLE` keyword, removes any other `FILETAGS` keyword in the section, and with TAGS empty removes the line.
- A valid tag matches org's `org-tag-re`, `[[:alnum:]_@#%]+`, in full. An invalid one raises a new kind declared with `sns-roam-define-error`, carrying `:tag` (slice 22).
- `sns-roam-create-node` (near line 2134) gains an optional TAGS argument after SLUG-SOURCE, validated the same way, writing the same line in the header.
- `sns-roam-find-by-metadata` already matches org-roam's node tags, which org-roam reads from `#+filetags:`.
- In `skills/roam-distill/SKILL.md`, the Write list gains `sns-roam-set-tags`, and `sns-roam-create-node`'s entry gains TAGS.

## Questions to resolve

None.

## Done when

`test/sns-roam-test.el` has tests for S26.1, S26.2 and S26.3, asserting the file text after `#+title:` and, for S26.3, the error's `:tag` and unchanged bytes. Tests show setting tags twice leaves one line, `sns-roam-create-node` with TAGS `("tech_leadership")` writes the line under `#+title:`, and `sns-roam-find-by-metadata "tech_leadership"` finds the tagged note. The builder runs S26.1 through `claude -p` against a separate Emacs server. `mise run check` and `mise run test` pass.
