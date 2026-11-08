# Bridge design — sns-emacs-api

Capture from the design conversation on 2026-05-30. The current
implementation in `sns-emacs-modules/sns-emacs-api.el` is the result
of an iterative session and the following review crystallised what
shape the library should actually take. Refactor pending.

## Design principle (settled)

> The library doesn't need to hide org-element; it just needs to make
> writes safe.

Concretely:

- **Keep the AST visible.** Callers compose `org-element-parse-buffer`
  with the library's helpers. No abstraction layer that pretends to be
  the document model.
- **Add guardrails, not abstractions.** Uniqueness assertions, type
  checks, concentrated mutation — these add safety without inventing a
  new conceptual layer over Org.
- **Mutation concentrated and auditable.** A single mutating primitive
  that operates on already-resolved regions is the right shape.
- **Semantic uncertainty belongs in region discovery.** Mutation should
  only operate on regions whose meaning has already been established.
- **Loud failure preferred to heuristic recovery.** When the AST
  doesn't expose what we asked for, error explicitly. Don't silently
  fall back to text-search inference — that masks bugs at exactly the
  layer where they cause damage.

## What the library is for (settled)

**Goal A** — thin wrapper over `org-element` with safe writes.
The model navigates the AST itself; the library provides:
- A small set of write operations.
- Guardrails (uniqueness assertions, type checks).
- Pure helpers that compose with org-element naturally.

**Goal B** — higher-level semantic document API for LLMs.
The library decides what counts as a "section," "body," "node"; the
caller doesn't reach into org-element directly.

We're going with **Goal A**. Capable models can navigate Lisp ASTs
directly. Hiding `org-element` adds no value and makes the abstraction
fragile (the "every element has a body" mistake came from leaning B-ward).

## What survives the refactor

- `sns-find-elements` — returns all matches. Real guardrail.
- `sns-find-the-element` — asserts uniqueness. Earned its place when
  the loose-predicate footgun bit us during the
  `*** Make available` move (sns-look-and-feel got captured instead
  of sns-emacs-api). The fix was a tighter predicate; the better
  fix is making "find the unique match" the default name.
- `sns-substitute-in-string` — pure string transform. No org-element
  coupling. Belongs because body-content edits are common.
- The `!` suffix convention for mutating functions.

## What needs refactoring

The current code has these problems:

### 1. `sns-element-body-region` makes a false claim

It advertises "find the body of an element" but actually does:
- For elements with `:contents-begin/:contents-end`: return that range.
- For elements without (src-block, drawer, etc.): walk past the
  `#+begin_X` line and back from `#+end_X`/`:END:` via regexp.

The two branches are not the same operation. The first is an AST
property lookup; the second is syntax-level inference. Lumping them
under one name signals interchangeability that isn't real. A caller
that hands the function a src-block when they thought it was a
paragraph gets a region back that means something different.

### 2. Silent text-search fallback

The regexp fallback exists because src-block doesn't expose
`:contents-begin`. The honest move is to either:
- Refuse to handle elements org-element doesn't fully describe, or
- Have type-specific functions that *know* they're doing
  syntax-level recovery and name themselves accordingly.

### 3. The mutator/region-discovery conflation

Originally I proposed splitting `sns-apply-element-update!` into
type-specific mutators (`sns-apply-paragraph-update!`,
`sns-apply-src-block-body!`, etc.). The review correctly pointed out
this is wrong: it's the **region discovery** that's type-specific,
not the mutation. Mutation is just `delete-region` + `insert` over
a known `(begin . end)` pair, which doesn't care about element type.

## Proposed shape (settled)

Two concerns, two primitives:

```elisp
;; Type-aware region discovery. May fail loudly for elements
;; whose editable region the library doesn't know how to find.
(sns-element-edit-region element)
  ;; -> (begin . end) | error

;; Mechanical mutation over an already-resolved region. Pure
;; mutator; no element-type awareness.
(sns-apply-region-update! region new-body)
  ;; -> ()  (side-effecting)
```

Composition at the call site:

```elisp
(let* ((tree (org-element-parse-buffer))
       (block (sns-find-the-element tree 'src-block predicate))
       (region (sns-element-edit-region block))
       (new-body (sns-substitute-in-string
                  (org-element-property :value block)
                  '(("old" . "new")))))
  (sns-apply-region-update! region new-body)
  (save-buffer))
```

This separation also means a caller who computed a region by some
other route — manual buffer search, custom logic — can still use
`sns-apply-region-update!` without going through element discovery.
The mutator is genuinely reusable.

## Open question (deliberately unresolved)

How should `sns-element-edit-region` be structured internally?

**Option A** — single dispatching function:

```elisp
(defun sns-element-edit-region (element)
  (pcase (org-element-type element)
    ('paragraph (sns--contents-region element))
    ('src-block (sns--src-block-body-region element))
    ('drawer    (sns--drawer-contents-region element))
    (_ (error "No edit-region rule for %s" (org-element-type element)))))
```

**Option B** — family of type-specific functions:

```elisp
(sns-paragraph-edit-region paragraph)
(sns-src-block-edit-region src-block)
(sns-drawer-edit-region drawer)
```

Tradeoffs:

- **A** keeps the call site uniform: one function, dispatch hidden.
  Easy to extend by adding a `pcase` arm. Risks: the dispatch hides
  type assumptions; a caller who hands the wrong element type gets
  an error but only after the call rather than at the type.
- **B** forces the caller to commit to an element type at the call
  site. A type mismatch becomes a syntax error (wrong function
  called) rather than a runtime check. Risks: more functions to
  remember; less convenient for code that wants polymorphism.

Both are defensible. Don't decide under cognitive fatigue. Decide
when the next concrete use case clarifies which feels more natural —
and document the rationale either way.

## Refactor plan (when picked up)

The call site disciplines the API. We are not designing primitives
in the abstract and forcing the workflow through them; we are
refactoring just enough surface to express the existing font-edit
workflow cleanly under the proposed split. If the workflow doesn't
exercise an aspect of the API, we don't add it speculatively.

### The test case: font swap (commit a7da114)

The font-edit workflow is a coupled edit to two adjacent elements
under the heading `*** Fonts and font resizing` in `README.org`:

1. **Paragraph body** rewritten in full — descriptive prose changes
   from "JetBrains Mono at 12pt…" to "Maple Mono NF at 15pt… Matches
   the font configured in Ghostty…".
2. **`emacs-lisp` src-block body** patched via three ordered string
   substitutions:
   - `JetBrains Mono` → `Maple Mono NF`
   - `JetBrains Mono-12` → `Maple Mono NF-15`
   - `120` → `150`
   The `120 → 150` substitution must be **scoped to this block's
   body**, not the whole buffer — there are other numeric literals
   in the file.

What the workflow asks of the API:

- Locate exactly one paragraph and exactly one src-block by
  structural context (under a specific heading). Already covered by
  `sns-find-the-element`.
- For each, obtain a buffer region representing its editable body.
  A paragraph and a src-block are different element types with
  different region rules. This is the `sns-element-edit-region`
  contract.
- For the src-block, scope substitutions to that block's body —
  composed via `sns-substitute-in-string` over `:value` from
  org-element.
- Apply both edits in one save. Per the design discipline
  (multi-element edits: pure capture first, then mutate
  end-to-start), the workflow performs all discovery first, then
  applies regions in descending `:begin` order.

That last point is the load-bearing reason for the split. With
fused discovery+mutation, the second region's positions would be
invalid after the first mutation. With the split, the caller can
hold all `(region . new-body)` pairs as immutable values, sort by
position, and mutate without re-parsing.

### Provisional dispatch choice for this refactor

Going with **Option A** (single dispatching `sns-element-edit-region`)
for the font-swap exercise, on these grounds:

- The workflow's natural shape is "loop over a list of (element,
  new-body) pairs and apply." Per-type functions would push a
  `pcase` up to the call site — the same dispatch, just outside the
  library. That weakens the library's value proposition (guardrails
  in one place).
- The element-type set the workflow needs is small: paragraph and
  src-block. Two arms is not pcase sprawl.
- Loud failure on unknown types lives naturally in the dispatch's
  default arm.
- The choice is reversible. If a future use case wants
  type-asserted call sites, factor out `sns-paragraph-edit-region`
  / `sns-src-block-edit-region` and have `sns-element-edit-region`
  delegate. Option B becomes the implementation of Option A.

This choice is **provisional**. It is justified by the font-edit
workflow alone. If the next concrete use case (e.g. drawers,
plain-list items, headlines) finds the dispatch awkward — for
instance, because type-specific arms diverge in arity, return
shape, or required preconditions — switch to Option B then. Don't
canonise A on the strength of one workflow.

### Steps

1. Remove `sns-element-body-region` from the README and the tangled
   file. Keep `sns-find-elements`, `sns-find-the-element`,
   `sns-substitute-in-string` unchanged.
2. Define `sns-element-edit-region` as a single dispatching function.
   Cover paragraph and src-block. Unknown types signal an explicit
   error naming the type. Do not add other arms speculatively —
   add them when a workflow demands them.
3. Define `sns-apply-region-update!`. Strict mechanical mutator:
   takes a cons `(begin . end)` and a string, replaces the region
   in the current buffer. No element-type awareness. No conditional
   logic beyond a region-shape sanity check.
4. Drop `sns-apply-element-update!` from the README.
5. Express the font-swap workflow using the new shape. Treat this
   as the acceptance test: if the call site comes out as cleanly as
   the old one — or more cleanly — the split is validated. If the
   call site contortions reveal a flaw, *note it in this file* and
   stop; do not redesign mid-flight.
6. Update memory (both this project's and aldi-compass) to reflect
   the refined surface.

## Refactor outcome (2026-05-30)

Shipped. The new shape was tangled into `sns-emacs-api.el` and the
font-swap workflow runs cleanly against a fixture extracted from
`a7da114^:README.org`, producing the post-`a7da114` state byte-for-byte.

### What shipped

- `sns-element-edit-region` — single dispatching function. Arms for
  `paragraph` (delegates to `sns--paragraph-edit-region`, AST
  property lookup) and `src-block` (delegates to
  `sns--src-block-edit-region`, delimiter walk between `#+begin_src`
  and `#+end_src`). Unknown types raise
  `"sns-element-edit-region: no rule for element type %s"`.
- `sns-apply-region-update!` — mechanical mutator. Takes
  `(BEGIN . END)` and a string, validates the region shape, deletes
  and inserts. No element-type awareness.
- `sns-element-body-region` and `sns-apply-element-update!` removed
  from README and the tangled file.
- The internal helpers (`sns--paragraph-edit-region`,
  `sns--src-block-edit-region`) use the `sns--` double-dash
  convention for "private to this module."

### Acceptance test

`/tmp/font-swap-workflow.el` (kept out of the repo). Runs against a
fixture pulled from git at `a7da114^`, writes to a sibling temp
file, and the result diffs empty against the current README's font
section. The script is structured to make the discipline explicit:

- Pure discovery phase builds two `(region . new-body)` cons cells
  before any mutation runs.
- Mutation phase sorts by `:begin` descending and applies via
  `sns-apply-region-update!` end-to-start.

The split-makes-multi-edit-safe argument was load-bearing here. The
two regions live ~80 bytes apart in the same buffer; without
end-to-start ordering the second mutation would corrupt under any
other order.

### Validated (provisionally)

- Single dispatching `sns-element-edit-region` does compose cleanly
  with the workflow's `(element, new-body)` loop. No `pcase`
  leaked to the call site.
- Two arms (`paragraph`, `src-block`) is not sprawl.
- The split between region discovery and mutation expresses the
  end-to-start discipline as a *natural consequence* of the API
  shape, not a separate convention the caller has to remember.

### Still open

- Dispatch shape remains provisional. We have one workflow's worth
  of evidence. If a second workflow surfaces a use case where arms
  diverge in arity / preconditions / return shape, switch to a
  family of per-type functions and have the dispatcher delegate.
- We've not yet exercised: drawer, plain-list item, headline,
  example-block, quote-block. Add arms when a workflow demands
  them; resist speculative coverage.

### Surprise worth noting

The first run of the workflow errored with:
```
Expected exactly one emacs-lisp src-block under Fonts heading;
found 2 (positions: (5804 6142))
```
This was *not* a bug in the new primitives. It was a flaw in the
workflow's predicate: scoping by the heading's `:begin`/`:end`
range pulls in the next subsection too, because org-element's
`:end` for a section headline extends through trailing whitespace
into the following sibling. The fix was tightening the predicate
to also match on `set-face-attribute` in the block body.

The discipline working as designed:
- `sns-find-the-element`'s loud-failure-on-multiple-matches caught
  a wrong-element bug at find-time, not at mutate-time. A weaker
  "first match" primitive would have silently rewritten the
  keybinding block instead of the font-setting block.
- The error message named both candidate positions, making the
  diagnosis a one-line fix.

This validates the [[emacs-bridge-design-discipline]] memory's
"unique-match is the default" line as more than a stylistic
preference — it's a load-bearing safety property.

## Things the review explicitly liked

Worth preserving across the refactor:

- Mutation is isolated in a single place.
- API surface is small.
- Implementation remains understandable without learning another
  abstraction layer.
- Code is biased toward semantic operations rather than character
  offsets.
- The `!` suffix convention makes mutation intent obvious at call
  sites.

These are properties of the *shape*, not the specific functions, so
they survive any of the proposed refinements.
