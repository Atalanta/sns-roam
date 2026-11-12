# Slice 25: the literate source explains the code as it is, not how it got there

## Goal

Someone about to change sns-roam, the owner or a coding agent, opens `src/roam-api.org` at a function's section and reads what the code does, its contract and the rules it keeps, without reading the history of how it came to be.

## Who uses it the day it lands

The owner and the turnstile worker, the next time either changes a primitive.

## Stakes

The prose is 907 lines beside 1,244 lines of code, with 4 dates, 8 issue numbers, 2 slice numbers, 76 em dashes and discipline notes that argue against designs no longer in the file (counted 2026-11-12). Every worker round reads it before an edit, so stale or historical prose costs each change, and a superseded rule can mislead one.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Moving sections to group them by purpose. Org tangles code in document order, so moving one would reorder `lisp/`; that is a later slice.
- Any change inside a source block, docstrings and comments included.

## Invariants

- Every source block is unchanged, character for character, so `mise run tangle` leaves `lisp/sns-roam-api.el` byte-identical (AGENTS.md: edit `src/`, never `lisp/`).
- The history stays recoverable in git and `docs/slices/` (AGENTS.md layout).

## Scenarios

Scenario: S25.1 A section describes its function as it is now
  Given the rewritten section on `sns-roam-insert-element`
  When the owner reads it
  Then it states what the function does, its arguments and return plist, the `sns-roam-` error kinds it raises, and its spacing rule, with no date, issue number or slice number

Scenario: S25.2 The prose follows the writing rules
  Given the prose outside every source block in `src/roam-api.org`
  When the owner runs `plain-style lint` on it
  Then the linter reports no banned term

## Facts the builder needs

- Headings and prose may change; headings keep their order and level, so each source block stays under its section. Each section keeps a Contract with inputs, output and the error kinds from `sns-roam-define-error` that it raises, and keeps a "Discipline notes" list only for rules the current code keeps.
- Remove dates, incident accounts, issue and slice numbers, and notes about designs the code no longer has. The current rule a past incident led to stays, stated as a rule.
- `/tmp/s25-prose-before.txt` holds the prose as it is now, outside source blocks, for comparison.

## Questions to resolve

None.

## Done when

A script extracts every source block from `src/roam-api.org` on `main` and on the branch and shows the two lists identical, and `git diff main -- lisp/` is empty after `mise run tangle`. The builder shows `plain-style lint` passing on the extracted prose, and `grep -nE "20[0-9]{2}-[0-9]{2}-[0-9]{2}|issue #|[Ss]lice [0-9]"` finding nothing in it. The owner reads the sections on `sns-roam--update-section` and `sns-roam-insert-element`. `mise run check` and `mise run test` pass.
