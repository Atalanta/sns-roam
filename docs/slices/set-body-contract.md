# Slice 5: set-body's documented contract matches what it does

## Goal

The docstring and literate source of `sns-roam-set-body` say it replaces the text before the first heading and keeps every heading, and a test fails if that stops being true.

## Who uses it the day it lands

The owner, or Claude reading the source, when changing how notes with headings are edited.

## Stakes

`turnstile review` raised this as CLJARCH-1 on slice 4. `src/roam-api.org` says `set-body` rewrites "through end-of-buffer" and "replaces the entire body", and the docstring says the same. The skill now says headings stay. A later change that trusts the source could delete headings without any test failing.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Changing what `set-body` does, or making any primitive edit headings.
- The `Output: t` line in the contract, which already differs from the returned plist. It is a separate fix.

## Invariants

- The tangled `lisp/sns-roam-api.el` stays in step with `src/roam-api.org`, which `mise run check` enforces.

## Scenarios

Scenario: S5.1 A rewrite keeps the headings
  Given a temporary note with a `#+filetags:` line, two intro paragraphs, then `* Old section` with a paragraph under it
  When `sns-roam-set-body` replaces the body with "New intro."
  Then the file holds "New intro.", the `#+filetags:` line and `* Old section` with its paragraph, and neither old intro paragraph

Scenario: S5.2 Reading the contract gives the real boundary
  Given the owner or Claude is about to change how notes with headings are edited
  When they read the `set-body` docstring and the contract in `src/roam-api.org`
  Then both say that headings and their content stay, and what is replaced and what is kept before the first heading

## Facts the builder needs

- The block at `src/roam-api.org` line 636 and the section at lines 532 to 556 carry the wording. A batch Emacs on 2026-11-08 showed `set-body` replacing the intro and keeping `* Old section`.
- Tests live in `test/sns-roam-test.el` and use `sns-roam-test--with-roam-dir`. `set-body` finds the file through `sns-roam--node-file-or-error`, which needs the org-roam database.

## Questions to resolve

None.

## Done when

The `set-body` docstring and the contract in `src/roam-api.org` each say that the paragraphs and other body elements before the first heading are replaced, and that property drawers, `#+` keywords such as `#+title:` and `#+filetags:`, and every existing heading with its content stay. The builder prints both passages. `grep -n -i -E 'end-of-buffer|entire body|everything after' src/roam-api.org lisp/sns-roam-api.el` prints no line about `set-body`. S5.2 holds for the two passages. The new ert test passes (S5.1) as regression evidence. A control run replaces `sns-roam-set-body` with a stub that writes only the new text over the whole file; the test then fails on the missing heading, and the builder shows that run. `mise run check` and `mise run test` pass.
