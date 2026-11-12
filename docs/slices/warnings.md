# Slice 27: reading notes and running skill scripts print no Emacs warnings

## Goal

When Claude searches the owner's notes or runs a skill's script in their Emacs, Emacs prints no warning about a non-Org buffer or a missing lexical-binding cookie.

## Who uses it the day it lands

The owner, whose `*Warnings*` buffer fills on every body search, every `sns-roam-set-body` and every skill script Claude loads (issues #3 and #4).

## Stakes

On 2026-11-12 `sns-roam-body-search` printed "`org-element-at-point' cannot be used in non-Org buffer", and loading a script without a cookie printed "Missing `lexical-binding' cookie". Claude runs both several times in a session, and each warning buries the ones that matter.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Warnings from org-roam, org-ml or other packages, and scripts Claude writes that are not in a skill template.

## Invariants

- Search and parse results are the same as before, value for value (AGENTS.md: functions keep their contracts).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S27.1 Searching notes prints no warning
  Given a slipbox with a note whose body says "Tide tables"
  When Claude runs `sns-roam-body-search` for "tide"
  Then the search returns that note's line, and Emacs prints no org-element warning

Scenario: S27.2 Rewriting a body prints no warning
  Given the same note
  When Claude runs `sns-roam-set-body` on it with "Tide tables, revised."
  Then the note's body is "Tide tables, revised.", and Emacs prints no org-element warning

Scenario: S27.3 A skill script loads without a warning
  Given any Lisp script template in `skills/roam-fetch/SKILL.md` or `skills/roam-distill/SKILL.md`
  When Claude writes it to a file and loads it with `load-file`
  Then Emacs prints no lexical-binding warning

## Facts the builder needs

- `sns-roam--search-file` (near line 314) and `sns-roam--parse-body-elements` (near line 830) parse text in a `with-temp-buffer` left in `fundamental-mode`. Each calls `(delay-mode-hooks (org-mode))` after inserting the text, as `sns-roam-expand` and `sns-roam-excerpt` already do.
- The script templates without a cookie are in `skills/roam-fetch/SKILL.md` near lines 209, 261, 275 and 290. Each starts with `;;; -*- lexical-binding: t; -*-`, as roam-distill's two do. The `package-vc-install` lines and the `with-temp-file` fragment are not scripts.
- The file-and-load section of each skill states that every script starts with the cookie.
- Emacs 31.1 prints the cookie warning when it loads a file without one, and nothing when the cookie is the first line (checked 2026-11-12).

## Questions to resolve

None.

## Done when

A test captures `*Warnings*` and `*Messages*` while it runs `sns-roam-body-search`, `sns-roam-set-body` and `sns-roam--parse-body-elements`, and shows no org-element warning, with the builder showing that test failing on `main`. A test writes each Lisp script template in both skills to a file, loads it, and shows no lexical-binding warning. Before the change, the builder records `sns-roam-body-search` results for three queries over a slipbox where several notes and lines match, and `sns-roam--parse-body-elements` results for three bodies; afterwards a test shows each equal to its record. `git diff main -- skills` adds only the cookie lines and the file-and-load sentence. The existing search and body tests pass unchanged. `mise run check` and `mise run test` pass.
