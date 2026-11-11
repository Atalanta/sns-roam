---
name: roam-distill
description: |
  Activates at the end of a BWC/BWJ braindump session when the user wants
  to turn the thinking into durable, claim-shaped permanent notes in their
  org-roam slipbox — "distill this", "capture these as atomic notes",
  "write this up into roam", "make permanent notes from this". Distills a
  transcript into claim-shaped atomic notes, finds existing neighbours via
  the read pipeline, links them, and writes via the `sns-roam-*` elisp
  primitives. Show → confirm → apply, mirroring `aldi-agent-patcher`.
  Not for reading (use `roam-fetch`); not for the GTD graph (use
  `aldi-agent-patcher`); not for vault import (that's the importer pipeline).
when_to_use: |
  User has done exploratory thinking (a BWC with Claude, or a BWJ dump
  they paste) and wants the durable ideas captured in the slipbox as
  permanent notes. The unit of output is the claim-shaped atomic note.
  Never auto-write — always show candidates, confirm per-note, then apply.
allowed-tools: Bash, Read, Write
---

# Roam Distill (Write-Side Slipbox Curation)

## When This Skill Activates

- End of a BWC/BWJ session producing atomic-note candidates
- User pastes a braindump and asks to capture the durable ideas
- User asks to write up thinking as permanent notes in roam

**Do NOT activate for:**
- Read questions about the slipbox — use `roam-fetch`
- GTD graph mutations — use `aldi-agent-patcher` (different graph)
- Importing markdown vaults — that's the importer pipeline, not Claude-facing

---

## Role

You turn messy exploratory thinking into durable, claim-shaped permanent
notes, linked into the existing slipbox graph. You do the *judgment*
(what claims, how atomic, what links); the elisp layer does the *writing*.
The discipline is **show → confirm → apply**: never write a file before
the user has seen and approved the candidate notes.

The slipbox is an **argument graph**, not a topic encyclopedia. The output
unit is the **claim-shaped atomic note** — one falsifiable assertion per
note, densely linked.

---

## Operating Mode: file-and-load idiom

All non-trivial elisp goes via file-and-load, never bare `emacsclient -e`.
Roam content carries `[[wikilinks]]`, em-dashes, and `&` that corrupt on
the `-e` wire. Write the script to `/tmp/<task>.el`, have it `prin1` its
result into `/tmp/<task>.out` with `with-temp-file`, load it with
`emacsclient -e '(load-file "/tmp/<task>.el")' >/dev/null`, then `cat` the
`.out`. The `load-file` return value is swallowed — capture to a file, do
not rely on stdout. (See `feedback-emacsclient-load-file-for-nontrivial-elisp`.)

---

## Vice Lisp discipline (non-negotiable)

All elisp written here obeys the Vice Lisp standard (see memory
`feedback-vice-lisp-discipline`):

- **Data over state; pure-ish core, explicit effects at the edge.** Build
  the note body as a *value* (org-ml AST), serialise to string only where
  the primitive demands it. The only effects are the `create-node` /
  `set-body` calls at the very end.
- **Mutations named and batched.** Construct everything, then apply.
- **Loud failure, unique-handle.** Wrap each write in `condition-case` and
  report per-note; never half-write silently.
- The taste test: *Hickey-proud, Syme-smiling.*

---

## What "claim-shaped" means (the distillation contract)

- **The title IS the claim** — a complete, falsifiable sentence you could
  agree or disagree with. "Leadership happens through relationships", not
  "Leadership". If the title isn't an arguable assertion, it's topic-shaped
  → reject and reshape.
- **One claim per note.** If a candidate contains "and"-joined claims,
  split into N notes. (Evidence/scope for a single claim stays in one note;
  two distinct claims do not.)
- **Title cap: ~7 words, 9 under protest.** A claim title must fit the top
  of a card. The cap is a forcing function for atomicity: if you can't say
  it in ~7 words, it is usually two claims — split it. Existing permanent
  claims run 6-12 words; treat the low end as the target and anything over
  9 as an atomicity smell to re-examine, not a length to accept. No
  semicolons or "and"/"but"-joins in a title — those are two claims wearing
  one title.
- **Body = the argument** — why the claim holds, its scope and limits.
  Not a description of a topic.
- **Exclude the operational.** Tables, names, schedules, tooling choices,
  logistics are reference material, not permanent claims — leave them out
  (or, if the user wants them, capture as a `:KIND: reference` note, not
  `permanent`; see "Reference and person notes").

---

## Reference and person notes

Operational material goes in reference notes, and people outside
Ticketmaster and Live Nation go in person notes. Neither is claim-shaped.
Both follow show, confirm, apply.

### Reference notes (`:KIND: reference`)

- One note per subject, titled by what it is: "Nobl9 contract". Keep dates
  out of the title, so the note gathers history across renewals.
- Current state first, in the present tense, updated in place. For a
  contract: edition, units, annual and unit price, term dates, notice
  window, and overage rate.
- Open items next, one line each, so anything still undecided stands out.
- History last, as dated lines, newest first, each naming its source:
  "2026-10-24: Nobl9 offered 1-, 2- and 3-year terms (email from Jennifer
  Tafolla)."
- No headings. `set-body` and `replace-element` cannot write under a
  heading, so a flat note stays editable through the API.
- Name people by name and role. Leave out email signatures and phone
  numbers; an external contact's details go in their person note.
- A decision becomes a history line. If its reasoning holds beyond this
  subject, capture the reasoning as a permanent claim and link it from the
  reference note.

### Person notes (`:KIND: person`)

- One note for each person outside Ticketmaster and Live Nation, titled
  with their full name.
- Body: organisation, role, contact details, and how the user knows them.
- The person note links to each reference note that involves them, and
  those notes link back. The no-reciprocal-link rule does not apply to
  person notes, because a person note indexes where someone appears.
- People inside Ticketmaster and Live Nation stay as plain names. The
  company directory holds their details, and Aldi holds their GTD person
  nodes.

---

## The primitives this skill composes

Read (for finding link targets — reuse the `roam-fetch` pipeline):
- `(sns-roam-find-by-metadata QUERY)` — seed existing notes by title/alias/tag.
- `(sns-roam-body-search QUERY)` — seed by body text when metadata misses.
- `(sns-roam-expand ID)` — one-hop subgraph to see a candidate's neighbourhood.

Write:
- `(sns-roam-create-node TITLE KIND &optional ELEMENTS ID ALIASES CREATED-TIME)`
  → `(:id :title :file)`. **ELEMENTS is a list of org-ml AST nodes** (the
  body). KIND is `"permanent"` for claims. Pass ID to use a pre-minted UUID.
  Errors if the destination file already exists.
- `(sns-roam-append-link FROM-ID TO-ID LABEL BEFORE AFTER)` → `(:from :to :file)`.
  Appends a relationship paragraph to FROM-ID: BEFORE then `[[id:TO-ID][LABEL]]`
  then AFTER. **The core act for linking notes that already exist.** Link sits
  between BEFORE/AFTER so phrasing + punctuation are honest (AFTER `"."` for a
  full stop). One-directional — backlinks give the reverse. **Does NOT dedupe:
  this skill must check for an existing link before calling it.**
- `(sns-roam-set-body ID NEW-BODY)` → `(:id :file)`. NEW-BODY is a **string** of
  org prose (drawer + `#+title` preserved). Replaces only the text before the
  first heading; existing `* ` headings and their content stay. Use when
  rewriting a note that has no headings (e.g. a sparse fleeting note). It
  cannot change a heading: tell the owner to edit that section by hand.
- `(sns-roam-replace-element ID PRED NEW-ELEMENT)` → `(:id :file)`. **Transform:**
  replaces the single body element matching PRED (a unary org-ml-node predicate)
  with NEW-ELEMENT (a built org-ml node). Asserts exactly one match — loud error
  on zero or many, so an ambiguous edit never hits the wrong element. Use to
  rewrite one paragraph/claim in place without reproducing the rest of the body.
  Reaches only the text before the first heading.
- `(sns-roam-set-property ID KEY VALUE)` (drawer, e.g. `KIND`), `(sns-roam-set-keyword ID KEY VALUE)` (`#+` line, e.g. `TITLE`),
  `(sns-roam-rename ID NEW-TITLE)` → for curation flows (promote, retitle).

All body mutations flow through one shared boundary (`sns-roam--update-section`):
a pure `(section -> section)` transform in, reconciled file out. You compose
transforms; you never poke the buffer.

Body construction: `org-ml-build-paragraph` with `org-ml-build-link`
children. A link is `(org-ml-build-link (concat "id:" TARGET-ID) LABEL)`,
which serialises to `[[id:TARGET-ID][LABEL]]`. Weave the link into the
prose sentence that states the *relationship* ("This refines [[...]] by…").

**org-ml hazard (see memory `orgml-parsed-node-slice-gotcha`):** when a
transform touches a *parsed* note's children, map the child list whole and
filter — never slice into header/body sublists and re-`append` parsed nodes,
or reconciliation dies with `number-or-marker-p`.

---

## Two flows

This skill has two flows; pick by intent:

- **Draft** — turn a BWC/BWJ transcript into new claim notes (below).
- **Link** — connect notes that already exist when you spot a connection
  (see "The link flow"). The core Zettelkasten act; value accretes here over
  time as much as in drafting.

Both are show → confirm → apply. Both can run in one session (draft new notes,
then link them to existing ones).

---

## The draft pipeline

One stage at a time. Show before write.

1. **Distill.** Read the transcript; extract claim-shaped candidates.
   Apply the contract above (atomicity split, exclude operational).
   **Enforce the title cap at this step:** reject any candidate whose title
   exceeds ~9 words or contains a semicolon / "and" / "but" / comma-join.
   A title over the cap is an atomicity signal — split the candidate into
   separate claims and re-title, don't wave it through. Aim for the ~7-word
   target, not the 9-word ceiling.

2. **Seed for neighbours.** For the cluster's key terms, run
   `find-by-metadata` (+ `body-search` on a miss) to find *existing* notes
   the new claims should link to. If empty, the cluster is greenfield and
   will **self-link** — notes link to each other, isolated from the rest of
   the slipbox until a future session links into it. This is normal.

3. **Plan links.** Decide each note's links: to existing nodes (from step 2)
   and to siblings in this batch. Each link is a *relationship*, stated in
   the linking sentence. (v1: plain `[[id:]]` links; typed relations —
   supports/contradicts — are a later refinement.)

4. **Mint IDs.** Pre-generate a UUID per new note (`org-id-new`). **This is
   the core technique:** intra-cluster links need the target's ID before the
   target exists, so mint all IDs up front, then build every body AST against
   the known IDs. No forward-reference problem, single creation pass.

5. **SHOW.** Present, per candidate: the claim (title), the body prose, the
   KIND, and the proposed links (which node, what relationship). The user
   confirms / edits / rejects **per note**. Do not proceed without explicit
   confirmation.

6. **APPLY.** Build each body as org-ml AST against the pre-minted IDs;
   `create-node` each with KIND `"permanent"` and its pre-minted ID. Wrap
   each in `condition-case`; collect `(:ok FILE)` / `(:error TITLE MSG)`.

7. **SYNC + VERIFY.** Run `(org-roam-db-sync)` so the new files are graph-live
   (links/backlinks won't resolve until synced). Then verify:
   `find-by-metadata` finds the cluster, and `expand` on the hub note shows
   the expected edge count. Report created files to the user to eyeball.

---

## Recovery

New notes are safe to delete — until a *later* session links into them,
nothing else references them. If a write batch is wrong, delete the files
in `~/roam/` and re-run. There is no partial-graph corruption risk for a
fresh cluster (unlike the GTD graph's open-next invariant).

---

## Worked Example (the first real run, 2026-06-06)

User pasted a BWJ "One-to-One Operating Model" dump.

1. **Distill** → 6 claim-shaped notes (e.g. "A one-to-one is a leadership
   conversation, not a reporting mechanism"; "Leadership happens through
   relationships"). Excluded: the cadence table, specific names, Outlook/Org
   tooling — reference, not claims.
2. **Seed** → `find-by-metadata` over leadership/1:1/cadence terms returned
   nil. Greenfield cluster → self-link.
3. **Plan** → "Leadership happens through relationships" became the hub;
   others link to it (grounds/operationalises/follows-from).
4. **Mint** → 6 UUIDs via `org-id-new`.
5. **Show** → table of claim→ID→links; user confirmed.
6. **Apply** → 6 `create-node` calls, KIND permanent, ASTs built against the
   minted IDs.
7. **Sync + verify** → `org-roam-db-sync`; cluster indexed, hub showed 5
   edges. Eyeballed two files: well-formed drawer + `#+title` + resolved
   `[[id:]]` links.

---

## The link flow (connect existing notes)

When a connection between two existing notes surfaces — during a draft, a
`roam-fetch`, or a conversation — make it explicit with `append-link`.

1. **Resolve both endpoints.** Get FROM-ID and TO-ID (via `find-by-metadata`
   / `body-search`). Confirm they're the intended notes.
2. **Check for an existing link.** `expand` FROM-ID; if TO-ID is already a
   forward neighbour, the link exists — do not re-add (the primitive does not
   dedupe). Surface it and stop.
3. **Phrase the relationship.** A link is a *statement*: decide BEFORE / LABEL
   / AFTER so the appended sentence reads as a claim about how the two notes
   relate ("This refines …", "This is bounded by …"). AFTER carries
   punctuation (`"."`).
4. **SHOW** the proposed sentence and the direction (FROM → TO); confirm.
5. **APPLY** `append-link`; then `org-roam-db-sync`.
6. **VERIFY** `expand` FROM-ID shows TO-ID as a neighbour; report.

Direction matters: link FROM the note that *makes the claim about* the
relationship. Backlinks make the reverse discoverable; don't add both.

### Worked example (first link, 2026-06-06)

Connected "Leadership cadence should be tiered by relationship proximity"
(FROM) → "Skip-level meetings are deferred by capacity, not by doubt" (TO) —
a connection the original 1:1 cluster missed. BEFORE "The tiering principle
also explains why ", LABEL the target's claim, AFTER ".". Verified: TO became
a forward neighbour of FROM.

---

## The transform flow (rewrite part of a note)

When a note's body needs changing — retighten a claim, fix a stale sentence,
plain back flourish, promote a fleeting note — use `replace-element` for a
single element, or `set-body` to rewrite the text before the first heading.
Neither reaches a heading or the content under one; for those, tell the owner
to edit the section by hand.

1. **Read the note.** Fetch the current body; identify the element to change.
2. **Choose the tool.**
   - One paragraph/element changing, rest stays → `replace-element` (build a
     predicate that matches exactly that element, and the replacement AST).
   - Text before the first heading being rewritten (e.g. sparse fleeting note
     → full claim) → `set-body`. Headings stay as they are.
3. **Build the replacement as AST.** Preserve any `[[id:]]` links the old
   element carried unless the edit deliberately drops them — reproduce them in
   the new element.
4. **SHOW** the before and after; confirm.
5. **APPLY**; then `org-roam-db-sync`.
6. **VERIFY** the file reads correctly and any links the note had still
   resolve (`expand` shows the same forward neighbours, unless intentionally
   changed).

Predicate discipline: `replace-element` matches exactly one element or errors.
Write the predicate narrowly (match on distinctive text in the target
element), and if it matches zero or many, tighten it — do not fall back to
`set-body` blindly, since that reproduces the text before the first heading and risks dropping
content.

### Promote a fleeting note

`:KIND: imported` / fleeting notes become `permanent` by *curation*, not
mechanically:
1. Rewrite the body into claim-shaped prose (`replace-element` or `set-body`).
2. `set-property` KIND → `permanent` (`KIND` lives in the property drawer;
   `set-keyword` would add a `#+kind:` line and leave the drawer unchanged).
3. `rename` if the title isn't yet a claim.
4. Link it into the graph (`append-link`) — a permanent note is not finished
   until connected.

---

## Anti-Patterns (Do Not)

- **Do NOT auto-write.** Show candidates and get per-note confirmation first.
- **Do NOT write topic-shaped notes.** A title that isn't an arguable claim
  is wrong. Reshape or reject.
- **Do NOT pack two claims into one note** to save files. Split.
- **Do NOT build links by string-concatenating org markup.** Use
  `org-ml-build-link`; let the AST serialise.
- **Do NOT forget to pre-mint IDs** before building bodies that cross-link —
  forward references can't resolve otherwise.
- **Do NOT skip `org-roam-db-sync`** — the cluster is invisible to the graph
  until synced.
- **Do NOT call `append-link` without checking for an existing link first.**
  The primitive does not dedupe; `expand` the FROM note and skip if TO is
  already a forward neighbour.
- **Do NOT add a reciprocal link.** One-directional only; backlinks cover the
  reverse. Two physical links is double-maintenance. Person notes are the
  exception; see "Reference and person notes".
- **Do NOT slice-and-rejoin parsed org-ml node lists** in any transform — map
  the child list whole, filter don't slice (memory `orgml-parsed-node-slice-gotcha`).
- **Do NOT use `set-body` to change one element.** It replaces the text before
  the first heading, so you must reproduce everything you keep there and risk
  dropping content/links. Use `replace-element` with a narrow predicate.
- **Do NOT use `set-body` or `replace-element` on a heading.** They cannot
  reach one. Tell the owner to edit that section by hand.
- **Do NOT write a loose `replace-element` predicate.** It must match exactly
  one element. Match on distinctive text; on zero/many it errors — tighten it,
  don't work around it.
- **Do NOT drop existing `[[id:]]` links when rewriting an element.** Reproduce
  them in the replacement AST unless the edit deliberately removes them.
- **Do NOT editorialise the user's claims** (memory `feedback-write-tersely`).
  No rhetorical flourish in note bodies; state the claim and its support
  plainly. Banned: `load-bearing`, `the shape of X`, "the moment they matter
  most". The claims are the user's, not yours to embellish.
- **Do NOT capture operational/reference material as `:KIND: permanent`.**
  Permanent is for claims; reference is for sources, tables, logistics.
- **Do NOT reach into raw SQLite** or text-munge note files. Graph API +
  org-ml only.
- **Do NOT paraphrase the user's ideas into claims they didn't make.** The
  claims are theirs; surface candidates and let them correct.

---

## Tone

- Short, direct. Show the candidates; let the user steer.
- Quote claim titles verbatim in the show step and the result summary.
- Surface ambiguity (is this one claim or two?) as a one-line question;
  don't silently decide.
- Report files and edge counts after writing so the user can eyeball.

---

## Reference

- `~/Developer/sns-roam/src/roam-api.org` — the `sns-roam-*` primitives (literate source).
- `~/.claude/skills/roam-fetch/SKILL.md` — the read sibling; reuse its
  pipeline for the neighbour-finding step.
- Memory `roam-claude-design` — locked design rules (graph-not-text, plist
  returns, unique-handle writes, loud failure).
- Memory `feedback-vice-lisp-discipline` — the elisp craft standard.
- Memory `roam-integration-arc` — the broader programme and skill boundaries.

---

## Loading the modules (if not already loaded)

```sh
emacsclient -e '(load-file "~/Developer/sns-roam/lisp/sns-roam-api.el")'
```

Confirm primitives are present before composing:
`(mapcar #'fboundp '(sns-roam-create-node sns-roam-find-by-metadata))`.
