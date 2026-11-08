# Slice 6: two stale lines in the primitives' documentation

## Goal

The `sns-roam-set-body` contract states the plist it returns, and the `sns-roam-create-node` docstring has no stray half sentence.

## Who uses it the day it lands

The owner, or Claude reading the source, when calling these two primitives.

## Stakes

`src/roam-api.org` says `set-body` returns `t`, and the function returns `(:id :file)`. A caller that tests for `t` would treat success as failure. The `create-node` docstring repeats "same time value" in a fragment, so the text reads as damaged. `turnstile review` flagged the first on slice 5 as outside its scope.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Other `Output:` lines, and any change to what a function returns or does.

## Invariants

- The tangled `lisp/sns-roam-api.el` stays in step with `src/roam-api.org` (`mise run check`).

## Scenarios

Scenario: S6.1 Reading the set-body contract
  Given Claude is about to call `sns-roam-set-body`
  When it reads the contract in `src/roam-api.org`
  Then the Output line says it returns `(:id :file)`

Scenario: S6.2 Reading the create-node docstring
  Given Claude is about to call `sns-roam-create-node`
  When it reads the docstring
  Then the time paragraph ends in complete sentences and no half sentence remains

## Facts the builder needs

- The wrong line is `- *Output*: =t= on success.` at `src/roam-api.org` line 553. The fragment is "same time value via `format-time-string'. Returns" in the `create-node` docstring. Checked on 2026-11-08.
- `sns-roam-set-body` returns the plist from `sns-roam--update-section`.

## Questions to resolve

None.

## Done when

The builder prints the `set-body` Output line, which reads `(:id :file)` (S6.1), and prints the `create-node` docstring, which has no line starting "same time value via" and still ends with the complete sentences "Returns (:id :title :file). Errors if the destination already exists." (S6.2). A batch Emacs calls `sns-roam-set-body` on a temporary note and prints `(:id ... :file ...)`, the value the line now states. `git diff -- lisp/` shows only docstring text changed. `mise run check` and `mise run test` pass.
