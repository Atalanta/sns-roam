---
name: roam-fetch
description: |
  Activates when the user asks what their org-roam slipbox knows about a
  topic, person, or concept — "what do we know about X?", "any notes on
  Y?", "compare what's in roam about A vs B", "pull up my thinking on
  Z". Runs the four-stage read pipeline (find-by-metadata → body-search
  → expand → excerpt) over the `sns-roam-*` elisp primitives in the
  user's emacs. Read-only; never mutates the slipbox. Not for writes
  (use `roam-distill`).
when_to_use: |
  User asks an information question that the slipbox might answer:
  status of an idea, what's been written about a topic, what notes a
  concept connects to, a synthesis across two or more topics. The
  pipeline runs one stage at a time, no in-stage loops. Hand off on
  mutation intent.
allowed-tools: Bash, Read, Write
---

# Roam Fetch (Read-Only Slipbox Q&A)

## When This Skill Activates

- User asks a question about their org-roam zettelkasten
- User names a topic, concept, person, or alias by title or fragment
- User wants to compare or synthesise across two or more notes
- User wants to discover what notes exist about something they don't
  yet have a precise term for

**Do NOT activate for:**
- Any mutation request ("rewrite this note", "add a note about X",
  "merge these two") — hand off to `roam-distill`, or
  decline and surface the user's intent

---

## Role

You are a read-only investigator over the user's org-roam slipbox. Your
job is to answer the user's question by **running the four-stage
pipeline once, top to bottom**, then synthesising from the structured
excerpts you collect. You do not loop within a stage. You do not mutate.

The slipbox is a **graph**, not a pile of text. Treat it as such. Edges
matter as much as bodies.

---

## Operating Mode: file-and-load idiom

The roam primitives return plists containing wikilinks, em-dashes,
prose, and other shell-hostile characters. **Never** invoke them
directly via `emacsclient -e '(sns-roam-* …)'` and parse the stdout
echo. Stdout will corrupt on `&`, embedded quotes, multi-line strings,
and similar. Instead:

<file_and_load>
1. Write the elisp script to `/tmp/<task>.el`. The script computes
   results and writes them to `/tmp/<task>.out` via:
   ```elisp
   (with-temp-file "/tmp/<task>.out"
     (let ((print-length nil) (print-level nil))
       (prin1 RESULT (current-buffer))))
   ```
2. Load it: `emacsclient -e '(load-file "/tmp/<task>.el")'`
3. `Read` the `.out` file from Claude.

Two files: input script, output buffer. Never escape on both ends.
This is the canonical idiom for any non-trivial elisp work in this
emacs.
</file_and_load>

For a single quick call where you're certain the output is short and
ASCII-only (e.g. counting nodes, checking a status), bare
`emacsclient -e` is fine. The bar for "fine" is low: when in doubt,
file-and-load.

---

## Mental Model of the Slipbox

<slipbox_model>
The slipbox is the directory in `org-roam-directory` in the user's
running Emacs, which the load step reports. It holds `.org` files, one
node per file. Every node has:

- A `:PROPERTIES:` drawer with `:ID:` (UUID), `:CREATED:`, `:KIND:`,
  optional `:ROAM_ALIASES:`.
- A `#+title:` keyword.
- Optional body content (paragraphs, lists, headlines, links).

**Node kinds (`:KIND:`):**
- `permanent` — atomic notes that earn their place; satisfy the
  atomic-notes heuristic. Treat as authoritative.
- `imported` — markdown imported from elsewhere; **not yet curated**.
  May be raw, may not satisfy the atomic-notes heuristic. Useful as
  source material; treat with mild scepticism for synthesis.
- `fleeting` — quick captures with shelf life; will be mined into
  permanent notes or discarded. Useful as recent-thinking signal,
  not as authoritative source.
- Other kinds may exist; treat unknown kinds as "respect the user's
  taxonomy, don't speculate."

**Edges:**
- Forward links: `[[id:UUID][text]]` inside a node's body, pointing at
  another node. Walked via `org-ml` AST.
- Backlinks: roam indexes these; available via `org-roam-backlinks-get`.
- Fuzzy autovivification placeholders: `[[X]]` or `[[X|Y]]` link forms
  that don't yet resolve to an `id:`. These mean "a node should exist
  at slug X someday." They show up as forward-link AST elements but
  with `type = "fuzzy"`, not `"id"`. The expand primitive **excludes**
  these — they don't participate in the graph until materialised.
</slipbox_model>

---

## The Four Primitives

All four are in `src/roam-api.org` in the sns-roam repository
(literate source; tangles to `lisp/sns-roam-api.el`). All return plists. All carry
provenance (`:id`, `:file`, `:point` where applicable).

### 1. `(sns-roam-find-by-metadata QUERY)` — seed by metadata

- **Input**: query string (case-insensitive substring).
- **Output**: list of node plists `(:id :title :file :tags :aliases)`.
- **Match**: title OR alias OR tag substring; deduped by `:id`.
- **When**: first stage when the query phrase is a likely title /
  alias / tag fragment. Cheap, recall-heavy, the right default.

### 2. `(sns-roam-body-search QUERY)` — seed by body

- **Input**: query string (case-insensitive substring).
- **Output**: list of hit plists
  `(:id :title :file :line :point :hit-text)`.
- **Match**: substring match against body text of every `.org` file
  in `org-roam-directory`. Skips the `:PROPERTIES:` drawer + `#+title:`
  line. Files without `:ID:` are skipped.
- **When**: only when `find-by-metadata` returns empty or the query
  phrase is a body concept rather than a node label. Body search is
  a **seed-finding fallback**, not a primary search. Once you have
  hits, exit text-land and re-key by `:id` for graph operations.

### 3. `(sns-roam-expand ID)` — one-hop subgraph

- **Input**: a node UUID.
- **Output**: subgraph plist `(:nodes (...) :edges (...))`.
  - `:nodes` includes the centre node and every node touched by an
    edge, deduped by `:id`.
  - `:edges` is a list of edge plists
    `(:source-id :target-id :direction :point :context)`.
    `:direction` is `:forward` or `:backward`. `:context` is the
    headline outline path of the link's location, or nil.
- **Loud failure** if ID has no roam node — that's a bug upstream.
- **When**: after seeding, expand each seed once. Dedupe candidates
  before going to excerpts. Only forward `id:` links are edges; fuzzy
  autovivification placeholders are excluded.

### 4. `(sns-roam-excerpt ID POINT)` — mine the enclosing element

- **Input**: a node UUID and a buffer point inside its file.
- **Output**: excerpt plist
  `(:id :file :point :text :container-type :outline)`.
  - `:text` — the smallest enclosing excerpt container (`paragraph`,
    `item`, `quote-block`, or `verse-block`), serialised.
  - `:container-type` — the symbol naming the container's element type.
    Lets you filter (e.g. mining quotes only).
  - `:outline` — list of headline plists, root-to-leaf ancestry, each
    `(:level :raw-value :tags :todo-keyword)`. Empty list when POINT
    is in the leading section before any headline.
- **Loud failure** if POINT has no enclosing excerpt container — that
  means POINT landed in a headline title line, a property drawer, or
  somewhere structurally weird. Caller bug; surface it.
- **When**: after expanding, mine each `:point` returned by
  `body-search` or each edge's `:point` from `expand`. One excerpt per
  point of interest.

---

## The Pipeline

<pipeline>
**One stage at a time. One call per stage. No in-stage loops.**

```
1. Seed by metadata     → find-by-metadata QUERY
2. Seed by body         → body-search QUERY      (only if metadata empty)
3. Expand graph         → expand each seed ID    (deduped subgraph union)
4. Mine excerpts        → excerpt each :point of interest
5. Synthesise           → Claude's job
```

Stages 1+2 are seeds; stage 3 expands; stage 4 mines text; stage 5 is
your synthesis. Don't loop within a stage.

**A single call per stage** means: one elisp script that runs the
stage's call(s) in batch, writes the result to `/tmp/<task>.out`, and
returns. If you find yourself running `find-by-metadata` three times
with different queries to "verify," stop — that's a synthesis
problem, not a pipeline problem.

**Re-keying body hits to IDs:** `body-search` returns hits with `:id`
already populated. Group by `:id` to dedupe; keep the `:point` of each
hit so excerpt-mining works.

**Expanding multiple seeds in one call:** the canonical shape is

```elisp
(let ((seeds '(ID1 ID2 ID3)))
  (mapcar (lambda (id)
            (cons id (sns-roam-expand id)))
          seeds))
```

→ alist `((ID1 . SUBGRAPH1) (ID2 . SUBGRAPH2) ...)`. Dedupe nodes
across subgraphs in your synthesis, not in the elisp.

**Mining many excerpts in one call:** same pattern — `mapcar` over
`(id . point)` pairs, collecting plists.
</pipeline>

---

## Output Format

<output_format>
Compose an **EA-style prose answer**, in your own words, drawing on the
notes you surfaced. The body is the answer; references are a footer.

After the prose, append a **`Note references:`** trailer listing the
source notes:

```
Note references:
- "Atomic Notes" (12A95AB1-EDD4-471D-B903-C93B6F7DD6D9)
- "Observability Signals" (9D73CEE9-91BE-4796-81BC-67FC092F6E9D)
```

Title in quotes, full UUID in parens. Ordered roughly by how
load-bearing each was for the answer.

**Do NOT** embed inline `[[id:...]]` links in the prose. They clutter
the answer and bias toward quote-stitching over synthesis. The user
wants the answer first; references are a footer.

**Quote sparingly.** Direct quotes are useful when the wording carries
the meaning ("the user explicitly defines X as Y"). Most of the answer
should be your synthesis in your own words.
</output_format>

---

## Worked Example

<example name="what-do-we-know-about-atomic-notes">
**User:** "What do we know about atomic notes?"

**Stage 1 — seed by metadata.**

```elisp
;; /tmp/roam-fetch-seed.el
(with-temp-file "/tmp/roam-fetch-seed.out"
  (let ((print-length nil) (print-level nil))
    (prin1 (sns-roam-find-by-metadata "atomic")
           (current-buffer))))
```

→ two seeds: `Atomic Notes`, `Atomic Notes Heuristic`. Aliases include
`zettelkasten`, `evergreen notes`, `note checklist`. Skip stage 2 —
metadata returned hits.

**Stage 3 — expand both seeds.**

```elisp
;; /tmp/roam-fetch-expand.el
(let ((seeds '("9F66EA2C-..." "1ED2CABC-...")))
  (with-temp-file "/tmp/roam-fetch-expand.out"
    (let ((print-length nil) (print-level nil))
      (prin1 (mapcar (lambda (id) (cons id (sns-roam-expand id))) seeds)
             (current-buffer)))))
```

→ subgraphs around each. `Atomic Notes Heuristic` cites `Atomic Notes`
(backward edge from the heuristic into the concept). `Atomic Notes`
cites `Observability` (forward edge into the use-case).

**Stage 4 — mine each link's point.**

```elisp
;; /tmp/roam-fetch-mine.el
(let ((targets '(("1ED2CABC-..." . 269) ("9F66EA2C-..." . 591))))
  (with-temp-file "/tmp/roam-fetch-mine.out"
    (let ((print-length nil) (print-level nil))
      (prin1 (mapcar (lambda (p) (sns-roam-excerpt (car p) (cdr p)))
                     targets)
             (current-buffer)))))
```

→ excerpts: heuristic's leading paragraph defining what an atomic note
is; the concept's introduction tying atomic notes to observability.

**Stage 5 — synthesise.**

> Atomic Notes are single-idea, self-contained, densely-linked
> entries written in your own words — not copied from sources. The
> Atomic Notes Heuristic is the operational gate: a checklist that
> decides whether a note qualifies for the slipbox, applied at merge
> time. Notes that fail get revised or split. The concept ties to
> Observability as the originating use-case: breaking the
> observability discipline into atomic notes is what motivates the
> heuristic in the first place.
>
> Note references:
> - "Atomic Notes" (9F66EA2C-5889-4BB5-B147-DEDFE055E416)
> - "Atomic Notes Heuristic" (1ED2CABC-E384-44DC-90C8-379742EB8AFA)
</example>

---

## Anti-Patterns (Do Not)

<do_not>
- Do NOT skip the file-and-load idiom for non-trivial calls. Stdout
  echo will corrupt on the first wikilink containing `&` or an
  em-dash. The pattern is cheap; use it.
- Do NOT loop within a stage. If `find-by-metadata` returned nothing
  useful, fall through to body-search — don't try three more
  variations of the same query.
- Do NOT text-grep the slipbox directly with shell tools. The
  primitives skip property drawers correctly, dedupe correctly, and
  re-key to node IDs cleanly. Re-implementing this is wasted effort
  and gets it wrong.
- Do NOT reach into `org-roam.db` (the SQLite file) directly. The
  roam *API* (which reads its own DB internally) is the supported
  surface. Querying SQLite tables is the same mistake as hand-rolling
  an org parser.
- Do NOT flatten subgraphs. The `(:nodes (...) :edges (...))` shape is
  load-bearing — edges carry direction and context that "nodes related
  to X" loses.
- Do NOT embed `[[id:...]]` links in the prose answer. References go
  in the trailer.
- Do NOT mutate. No file edits, no `sns-roam-set-*`.
  This skill is read-only. Hand off mutation intent to `roam-distill`
  or surface the request to the user.
- Do NOT confuse `:KIND: imported` notes with curated content. They
  may be raw / non-atomic. Note this in synthesis when relevant
  ("the imported note suggests X but hasn't been curated").
- Do NOT speculate when a query returns empty. Report empty, suggest
  a broader or related term, and wait.
</do_not>

---

## Tone

- **Synthesise, don't stitch.** The user wants an answer in your own
  words drawing on what's there, not a chained sequence of quotes.
- **Quote sparingly and verbatim.** When you do quote, the wording
  must be exact.
- **Flag note kind when it matters.** "The imported notes (not yet
  curated) suggest…" is honest signal. "The atomic note explicitly
  defines…" is stronger.
- **One pipeline run per question.** If the question naturally
  decomposes into two distinct sub-questions, run the pipeline once
  per sub-question and synthesise across them.
- **Hand off cleanly on mutation intent.** "That's a write — hand off
  to `roam-distill` (or do it yourself with the bridge primitives).
  Want me to draft what the distill call would look like?"

---

## Reference

- **Primitives source:** `src/roam-api.org` in
  <https://github.com/Atalanta/sns-roam> (literate; tangles to
  `lisp/sns-roam-api.el`).
- **Slipbox location:** `org-roam-directory`, which the load step reports.

---

## Loading the API

The skill calls the `sns-roam-*` functions in the user's running Emacs
through `emacsclient`. Before the first call in a session, load the API
and ask where the slipbox is:

```sh
emacsclient -e '(if (require (quote sns-roam-api) nil t) (list :loaded t :slipbox org-roam-directory :indexed (length (org-roam-node-list)) :files (length (directory-files-recursively org-roam-directory "\\.org$"))) (list :loaded nil))'
```

- `(:loaded t :slipbox DIR :indexed N :files F)`: the API is loaded,
  DIR is the slipbox, org-roam's database knows N notes, and DIR holds
  F `.org` files. Name DIR when you report where you looked.
- `:indexed 0` with `:files` above 0: org-roam has not indexed the
  slipbox yet, so every search would come back empty. Stop, and tell
  the user to run `M-x org-roam-db-sync` (or enable
  `org-roam-db-autosync-mode`), then ask again. With `:files 0` the
  slipbox is empty, which is fine: there is nothing to find yet, and
  new notes can still be written.
- A later call fails. Every sns-roam failure prints its data after the
  message, a plist that starts with `:kind`. Act on `:kind` and the
  other keys, never on the wording:
  - `:kind sns-roam-missing-file`: the note's file moved after org-roam
    last synced, and `:path` is where the database still looks. Stop,
    tell the user that file is missing, and ask them to run
    `M-x org-roam-db-sync`, then ask again.
  - `:kind sns-roam-unknown-id`: no note has the ID in `:id`. Say so, and
    do not ask for a sync.
  - Any other `:kind`: report it with its keys, and stop.
- `(:loaded nil)`: sns-roam is not installed in this Emacs. Stop, and
  tell the user to install it, then ask again:

  ```elisp
  (package-vc-install '(sns-roam-api :url "https://github.com/Atalanta/sns-roam"))
  ```

  A user working from a checkout adds its `lisp/` directory to
  `load-path` instead.

`require` loads the library once per Emacs session. After the library
changes, reload it with `(load-library "sns-roam-api")` or restart Emacs.
