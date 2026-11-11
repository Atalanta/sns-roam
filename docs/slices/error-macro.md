# Slice 22: each kind of sns-roam failure is declared once, with its fields

## Goal

A person adding or changing an sns-roam failure declares its kind, message and fields in one form, and the byte compiler warns when a call raises it with the wrong number of facts. What callers and Claude see does not change.

## Who uses it the day it lands

The owner, and any worker in a turnstile round, the next time they add a primitive or a refusal to `src/roam-api.org`.

## Stakes

Slice 21 wrote each failure's plist by hand at 26 call sites, so a site can leave out a fact such as `:count` and only that site's test would notice. The kind-to-fields mapping lives nowhere, and its plan took seven review rounds to pin down. The owner wants the interests an ML type declaration serves, met with Lisp's own means, not imitation types (owner, 2026-11-11).

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Checking field types at run time, or closing the set of kinds. Lisp offers neither natively, and the owner does not want them faked.
- Any change to a condition's name, message, data or the places that raise it.

## Invariants

- Every condition's data keeps the keys and values slice 21 gives it, with no key added or lost; only their order after `:kind` may change, which `plist-get` ignores (slice 21, `docs/slices/error-data.md`).
- `sns-roam--call-with-context` still adds `:id` or `:file` where the raising site cannot know it (slice 21).
- `lisp/*.el` stays in step with `src/*.org` (AGENTS.md, `mise run check`).

## Scenarios

Scenario: S22.1 A call that leaves out a fact is caught at compile time
  Given the declaration `(sns-roam-define-error match-count "the match is not exactly one element" (count &optional operation anchor))`
  When the owner writes `(sns-roam--signal-match-count)` with no arguments and byte-compiles the library
  Then the compiler warns that `sns-roam--signal-match-count` is called with 0 arguments but requires at least 1

Scenario: S22.2 The tests list every kind and fail when one is never raised
  Given the registry of declared kinds
  When the owner runs `mise run test` with a new kind declared and no test raising it
  Then a test fails and names the kind no test raises

## Facts the builder needs

- The twelve `define-error` forms are near line 92 of `src/roam-api.org`, under the parent `sns-roam-error`. The 26 `(signal 'sns-roam-KIND (list :kind ...))` sites follow slice 21.
- The macro `sns-roam-define-error KIND MESSAGE FIELDS` expands to the `define-error` for `sns-roam-KIND` with message `sns-roam: MESSAGE`; a function `sns-roam--signal-KIND` whose argument list is FIELDS, building the plist `:kind` first, then each field as a keyword, leaving out `&optional` fields that are nil; and an entry in `sns-roam--error-kinds`.
- Each kind's FIELDS are the keys its own sites pass today, required where every site passes them and `&optional` otherwise, and nothing else. The builder reads them from the sites; the context keys that `sns-roam--call-with-context` adds are not fields.
- The S22.2 test needs to know which kinds the tests raise; one way is an ert helper that the per-site tests call to record each kind they assert.

## Questions to resolve

None.

## Done when

`grep -n "(signal 'sns-roam-" src/roam-api.org` finds only the macro's expansion. Before changing any site, the builder records, for each of the 26 sites, the data its slice 21 test raises; afterwards a test raises each again and compares the two as sets of key and value pairs. Every slice 21 test passes unchanged. The builder shows S22.1's warning from `byte-compile-file` on a scratch copy with the bad call added, and S22.2's failure with a scratch kind added. `mise run check` and `mise run test` pass.
