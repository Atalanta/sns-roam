---
name: roam-distill
description: |
  Activates at the end of a thinking or braindump session when the user
  wants to turn the thinking into durable, claim-shaped permanent notes in their
  org-roam slipbox: "distill this", "capture these as atomic notes",
  "write this up into roam", "make permanent notes from this". Distills a
  transcript into claim-shaped atomic notes, finds existing neighbours via
  the read pipeline, links them, and writes via the `sns-roam-*` elisp
  primitives. Show → confirm → apply. Not for reading (use `roam-fetch`).
when_to_use: |
  User has done exploratory thinking (a conversation with Claude, or
  notes they paste) and wants the durable ideas captured in the slipbox as
  permanent notes. The unit of output is the claim-shaped atomic note.
  Never auto-write: always show candidates, confirm per-note, then apply.
allowed-tools: Bash, Read, Write
---

# Roam Distill (Write-Side Slipbox Curation)

## When This Skill Activates

- End of a thinking session producing atomic-note candidates
- User pastes a braindump and asks to capture the durable ideas
- User asks to write up thinking as permanent notes in roam

**Do NOT activate for:**
- Read questions about the slipbox: use `roam-fetch`

## Role

You turn messy exploratory thinking into durable, claim-shaped permanent
notes, linked into the existing slipbox graph. You do the *judgment*
(what claims, how atomic, what links); the elisp layer does the *writing*.
The discipline is **show → confirm → apply**: never write a file before
the user has seen and approved the candidate notes.

The slipbox is an **argument graph**, not a topic encyclopedia. The output
unit is the **claim-shaped atomic note**: one falsifiable assertion per
note, densely linked.

## Operating Mode: file-and-load idiom

All non-trivial elisp goes via file-and-load, never bare `emacsclient -e`.
Before the first script of a session, make a directory for it with
`mktemp -d /tmp/roam-session.XXXXXX`, and write every script and
result of the session there. Below, SESSION stands for that directory.
Other sessions leave their scripts in `/tmp`, and two sessions at once
would otherwise overwrite each other's files.

Roam content carries `[[wikilinks]]`, em-dashes, and `&` that corrupt on
the `-e` wire. Write the script to `SESSION/<task>.el`, have it `prin1` its
result into `SESSION/<task>.out` with `with-temp-file`, load it with
`emacsclient -e '(load-file "SESSION/<task>.el")' >/dev/null`, then `cat` the
`.out`. The `load-file` return value is swallowed. Capture to a file, do
not rely on stdout.
Every script starts with the line `;;; -*- lexical-binding: t; -*-`.

## Elisp discipline (non-negotiable)

All elisp written here follows these rules:

- **Data over state; pure-ish core, explicit effects at the edge.** Build
  the note body as a *value* (org-ml AST), serialise to string only where
  the primitive demands it. The only effects are the `create-node` /
  `set-body` calls at the very end.
- **Mutations named and batched.** Construct everything, then apply.
- **Loud failure, unique-handle.** Wrap each write in `condition-case` and
  report per-note; never half-write silently.

## What "claim-shaped" means (the distillation contract)

- **The title IS the claim**: a complete, falsifiable sentence you could
  agree or disagree with. "Leadership happens through relationships", not
  "Leadership". If the title isn't an arguable assertion, it's topic-shaped
  → reject and reshape.
- **One claim per note.** If a candidate contains "and"-joined claims,
  split into N notes. (Evidence/scope for a single claim stays in one note;
  two distinct claims do not.)
- **Title cap: ~7 words, 9 under protest.** A claim title must fit the top
  of a card. The cap is a forcing function for atomicity: if you can't say
  it in ~7 words, it is usually two claims. Split it. Existing permanent
  claims run 6-12 words; treat the low end as the target and anything over
  9 as an atomicity smell to re-examine, not a length to accept. No
  semicolons or "and"/"but"-joins in a title: those are two claims wearing
  one title.
- **Body = the argument**: why the claim holds, its scope and limits.
  Not a description of a topic.
- **Exclude the operational.** Tables, names, schedules, tooling choices,
  logistics are reference material, not permanent claims. Leave them out
  (or, if the user wants them, capture as a `:KIND: reference` note, not
  `permanent`; see "Reference and person notes").

## The user's own conventions

Before the first write, apply the user's own roam conventions from
their Claude instructions (their CLAUDE.md files or memory). A
convention can set:

- which organisations count as the user's own, whose people stay as
  plain names instead of getting person notes;
- extra phrases or session names that should start this skill.

With no conventions, give every named person outside the user a
person note, and ask the user when you are unsure.

## Reference and person notes

Operational material goes in reference notes, and people outside the
user's own organisations go in person notes. Neither is claim-shaped.
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

### Adding a history line

When an email or a meeting adds an event to one or more reference notes,
`sns-roam-history-anchor` decides where each line goes. Never read the
note file, and never place the line yourself or rewrite the body with
`set-body`.

1. **Draft each line.** One paragraph per note, starting with the event's
   date as `YYYY-MM-DD:` and naming its source.
2. **Find every anchor first.** Run this script, with the notes' IDs and
   the date, before you show anything:

   ```elisp
   ;; -*- lexical-binding: t; -*-
   (let* ((date "2026-11-08")
          (ids '("NOTE-ID-1" "NOTE-ID-2"))
          (places
           (mapcar
            (lambda (id)
              (condition-case err
                  (append (sns-roam-history-anchor id date)
                          (list :elements
                                (mapcar #'org-ml-to-trimmed-string
                                        (plist-get (sns-roam-body-elements id)
                                                   :elements))))
                (sns-roam-error (list :id id :error (cdr err)))
                (error (list :id id :error
                             (list :kind 'other :condition (car err)
                                   :data (cdr err))))))
            ids)))
     (with-temp-file "SESSION/history-anchor.out"
       (prin1 places (current-buffer))))
   ```

   Neither call writes anything.
3. **Stop on any error.** If any entry has `:error`, report every error,
   naming each note, and stop. Offer nothing to apply, not even for the
   notes that passed. Each `:error` is a plist that starts with `:kind`.
   Report the `:kind` and the facts it carries, such as `:count` for
   `sns-roam-match-count`, and read nothing from a message. `:kind other`
   is a failure from Emacs or org-roam, not sns-roam; report its
   `:condition` and `:data` as they are. A note in
   another layout (`sns-roam-history-layout`, or
   `sns-roam-unsupported-element` for a `* History` heading) is for the
   owner to edit by hand.
4. **SHOW** each note's `:elements` with the new line placed before
   `:anchor`, or after it when `:after` is `t`. Ask to apply.
5. **APPLY** after the owner confirms, with each note's `:id`, `:anchor`
   and `:after` from step 2 and its line from step 1:

   ```elisp
   ;; -*- lexical-binding: t; -*-
   (let* ((places '((:id "NOTE-ID-1" :anchor "2026-11-06: ..." :after nil
                     :line "2026-11-08: ...")))
          (results
           (mapcar
            (lambda (place)
              (let ((anchor (plist-get place :anchor)))
                (condition-case err
                    (sns-roam-insert-element
                     (plist-get place :id)
                     (lambda (node)
                       (string= anchor (org-ml-to-trimmed-string node)))
                     (org-ml-build-paragraph (plist-get place :line))
                     (plist-get place :after))
                  (sns-roam-error (list :id (plist-get place :id)
                                        :error (cdr err)))
                  (error (list :id (plist-get place :id)
                               :error (list :kind 'other :condition (car err)
                                            :data (cdr err)))))))
            places)))
     (with-temp-file "SESSION/history-apply.out"
       (prin1 results (current-buffer))))
   ```

6. **VERIFY** with `sns-roam-body-elements` that the line sits where step 4
   showed it, and report any `:error` from step 5. Show the user the `:diff`
   of each result from step 5, and say "no change" for one whose `:diff` is
   `""`.

### Person notes (`:KIND: person`)

- One note for each person outside the user's own organisations, titled
  with their full name.
- Body: organisation, role, contact details, and how the user knows them.
- The person note links to each reference note that involves them, and
  those notes link back. The no-reciprocal-link rule does not apply to
  person notes, because a person note indexes where someone appears.
- People inside the user's own organisations stay as plain names. Which
  organisations those are is one of the user's conventions (see "The
  user's own conventions").

## The primitives this skill composes

Read (for finding link targets: reuse the `roam-fetch` pipeline):
- `(sns-roam-find-by-metadata QUERY)`: seed existing notes by title/alias/tag.
- `(sns-roam-body-search QUERY)`: seed by body text when metadata misses.
- `(sns-roam-expand ID)`: one-hop subgraph to see a candidate's neighbourhood.
- `(sns-roam-body-elements ID)` → `(:id :file :elements)`. The org-ml nodes
  before the note's first heading, without the drawer and `#+` lines, read
  from the buffer the next edit acts on, unsaved edits included. Writes
  nothing. `:elements` is nil when there is no body before the first heading.
- `(sns-roam-history-anchor ID DATE)` → `(:id :file :anchor TEXT :after BOOL)`.
  Where a history line dated DATE (`YYYY-MM-DD`) goes in a reference note:
  before the history line TEXT, or after the last paragraph TEXT when
  `:after` is `t`. Writes nothing. A note outside the reference layout
  (a heading, a list or table, an empty body, dated lines that are not one
  newest-first run at the end) is a loud `sns-roam:` error. See "Adding a
  history line".

Write:
- `(sns-roam-create-node TITLE KIND &optional ELEMENTS ID ALIASES CREATED-TIME SLUG-SOURCE TAGS)`
  → `(:id :title :file)`. **ELEMENTS is a list of org-ml AST nodes** (the
  body). KIND is `"permanent"` for claims. Pass ID to use a pre-minted UUID.
  TAGS, a list of strings, goes on one `#+filetags:` line under `#+title:`,
  so a new tagged note needs no second write. Errors if the destination file
  already exists, or if a tag is not one org reads as a tag (see
  `set-tags`); then no file is written.
- Each primitive below that edits an existing note returns `:diff`: the
  `diff -u` of the note's file before and after the edit, with both headers
  naming the file. `""` means the note did not change. A refused edit raises
  and returns no diff.
- `(sns-roam-append-link FROM-ID TO-ID LABEL BEFORE AFTER)` → `(:from :to :file :diff)`.
  Appends a relationship paragraph to FROM-ID: BEFORE then `[[id:TO-ID][LABEL]]`
  then AFTER. **The core act for linking notes that already exist.** Link sits
  between BEFORE/AFTER so phrasing + punctuation are honest (AFTER `"."` for a
  full stop). One-directional: backlinks give the reverse. **Does NOT dedupe:
  this skill must check for an existing link before calling it.**
- `(sns-roam-set-body ID NEW-BODY)` → `(:id :file :diff)`. NEW-BODY is a **string** of
  org prose (drawer + `#+title` preserved). Replaces only the text before the
  first heading; existing `* ` headings and their content stay. Use when
  rewriting a note that has no headings (e.g. a sparse fleeting note). It
  cannot change a heading. To add a paragraph under one, use
  `add-under-heading`; for any other change there, tell the owner to edit
  that section by hand.
- `(sns-roam-replace-element ID PRED NEW-ELEMENT)` → `(:id :file :diff)`. **Transform:**
  replaces the single body element matching PRED (a unary org-ml-node predicate)
  with NEW-ELEMENT (a built org-ml node). Asserts exactly one match: loud error
  on zero or many, so an ambiguous edit never hits the wrong element. Use to
  rewrite one paragraph/claim in place without reproducing the rest of the body.
  Reaches only the text before the first heading.
- `(sns-roam-insert-element ID PRED NEW-ELEMENT &optional AFTER)` → `(:id :file :diff)`.
  Adds NEW-ELEMENT, a paragraph built with `org-ml-build-paragraph`, before
  the single body element matching PRED, or after it when AFTER is non-nil.
  PRED sees only body elements, never the drawer or `#+` lines. Every other
  element keeps its text, and no blank-line gap shrinks. Zero or many
  matches, a NEW-ELEMENT that is not a paragraph, or a result that would not
  read back as the planned elements is a loud `sns-roam:` error, and the
  file is unchanged. Use to add a history line to a reference note. Reaches
  only the text before the first heading.
- `(sns-roam-add-under-heading ID OUTLINE-PATH NEW-ELEMENT)` → `(:id :file :point :diff)`.
  Adds NEW-ELEMENT, a paragraph built with `org-ml-build-paragraph`, at the
  end of a heading's own text, before any child heading. OUTLINE-PATH is the
  heading titles from a top-level heading down, such as
  `("Projects" "Tickets")`: the `:raw-value`s of the `:outline` that
  `sns-roam-subtree` returns. `:point` is where the new paragraph starts.
  Every other line keeps its text, a typed `1)` list included. A path that
  names no heading or several raises `sns-roam-match-count` with `:count`
  and `:path`, a NEW-ELEMENT that is not a paragraph raises
  `sns-roam-unsupported-element`, and the file is unchanged. Use to add to a
  section of a note with headings.
- `(sns-roam-set-tags ID TAGS)` → `(:id :file :diff)`. **The way to tag a
  note.** Sets the full tag list: TAGS is a list of strings, written as one
  `#+filetags: :t1:t2:` line directly under `#+title:`; any other
  `#+filetags:` line is removed, and `()` removes the tags. Each tag must
  match org's `[[:alnum:]_@#%]+` in full, so `tech_leadership` is a tag and
  `tech-leadership` is not. A bad tag raises `sns-roam-bad-tag` with `:tag`
  and the file is unchanged: tell the owner which tag was refused. Do not tag
  through `set-keyword`, which puts a new `#+filetags:` line after the body.
- `(sns-roam-set-property ID KEY VALUE)` (drawer, e.g. `KIND`), `(sns-roam-set-keyword ID KEY VALUE)` (`#+` line, e.g. `TITLE`),
  `(sns-roam-rename ID NEW-TITLE)` → for curation flows (promote, retitle).
  The first two return `(:id :file :diff)`; `rename` returns
  `(:id :title :file :diff)`, where `:diff` is the `#+title:` change.

All body mutations flow through one shared boundary (`sns-roam--update-section`):
a pure `(section -> section)` transform in, reconciled file out. You compose
transforms; you never poke the buffer.

Body construction: `org-ml-build-paragraph` with `org-ml-build-link`
children. A link is `(org-ml-build-link (concat "id:" TARGET-ID) LABEL)`,
which serialises to `[[id:TARGET-ID][LABEL]]`. Weave the link into the
prose sentence that states the *relationship* ("This refines [[...]] by…").

**org-ml hazard:** when a
transform touches a *parsed* note's children, map the child list whole and
filter. Never slice into header/body sublists and re-`append` parsed nodes,
or reconciliation dies with `number-or-marker-p`.

## Two flows

This skill has two flows; pick by intent:

- **Draft**: turn a session transcript into new claim notes (below).
- **Link**: connect notes that already exist when you spot a connection
  (see "The link flow"). The core Zettelkasten act; value accretes here over
  time as much as in drafting.

Both are show → confirm → apply. Both can run in one session (draft new notes,
then link them to existing ones).

## The draft pipeline

One stage at a time. Show before write.

1. **Distill.** Read the transcript; extract claim-shaped candidates.
   Apply the contract above (atomicity split, exclude operational).
   **Enforce the title cap at this step:** reject any candidate whose title
   exceeds ~9 words or contains a semicolon / "and" / "but" / comma-join.
   A title over the cap is an atomicity signal: split the candidate into
   separate claims and re-title, don't wave it through. Aim for the ~7-word
   target, not the 9-word ceiling.

2. **Seed for neighbours.** For the cluster's key terms, run
   `find-by-metadata` (+ `body-search` on a miss) to find *existing* notes
   the new claims should link to. If empty, the cluster is greenfield and
   will **self-link**: notes link to each other, isolated from the rest of
   the slipbox until a future session links into it. This is normal.

3. **Plan links.** Decide each note's links: to existing nodes (from step 2)
   and to siblings in this batch. Each link is a *relationship*, stated in
   the linking sentence. (v1: plain `[[id:]]` links; typed relations,
   supports/contradicts, are a later refinement.)

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
   each in `condition-case` with a `sns-roam-error` handler and then an
   `error` handler, so one failing note never stops the batch's report;
   collect `(:ok FILE)` / `(:error TITLE DATA)`, where DATA is `(cdr err)`
   for an sns-roam failure, or `(:kind other :condition C :data D)` for any
   other.

7. **SYNC + VERIFY.** Run `(org-roam-db-sync)` so the new files are graph-live
   (links/backlinks won't resolve until synced). Then verify:
   `find-by-metadata` finds the cluster, and `expand` on the hub note shows
   the expected edge count. Report created files to the user to eyeball.

## Recovery

New notes are safe to delete. Until a *later* session links into them,
nothing else references them. If a write batch is wrong, delete the files
in the slipbox and re-run. There is no partial-graph corruption risk for a
fresh cluster.

## Worked Example (the first real run, 2026-06-06)

User pasted a "One-to-One Operating Model" braindump.

1. **Distill** → 6 claim-shaped notes (e.g. "A one-to-one is a leadership
   conversation, not a reporting mechanism"; "Leadership happens through
   relationships"). Excluded: the cadence table, specific names, Outlook/Org
   tooling: reference, not claims.
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

## The link flow (connect existing notes)

When a connection between two existing notes surfaces (during a draft, a
`roam-fetch`, or a conversation) make it explicit with `append-link`.

1. **Resolve both endpoints.** Get FROM-ID and TO-ID (via `find-by-metadata`
   / `body-search`). Confirm they're the intended notes.
2. **Check for an existing link.** `expand` FROM-ID; if TO-ID is already a
   forward neighbour, the link exists. Do not re-add (the primitive does not
   dedupe). Surface it and stop.
3. **Phrase the relationship.** A link is a *statement*: decide BEFORE / LABEL
   / AFTER so the appended sentence reads as a claim about how the two notes
   relate ("This refines …", "This is bounded by …"). AFTER carries
   punctuation (`"."`).
4. **SHOW** the proposed sentence and the direction (FROM → TO); confirm.
5. **APPLY** `append-link`; then `org-roam-db-sync`.
6. **VERIFY** `expand` FROM-ID shows TO-ID as a neighbour. Show the user the
   `:diff` that `append-link` returned, or say "no change" if it is `""`;
   report.

Direction matters: link FROM the note that *makes the claim about* the
relationship. Backlinks make the reverse discoverable; don't add both.

### Worked example (first link, 2026-06-06)

Connected "Leadership cadence should be tiered by relationship proximity"
(FROM) → "Skip-level meetings are deferred by capacity, not by doubt" (TO):
a connection the original 1:1 cluster missed. BEFORE "The tiering principle
also explains why ", LABEL the target's claim, AFTER ".". Verified: TO became
a forward neighbour of FROM.

## The transform flow (rewrite part of a note)

When a note's body needs changing (retighten a claim, fix a stale sentence,
plain back flourish, promote a fleeting note) use `replace-element` for a
single element, or `set-body` to rewrite the text before the first heading.
Neither reaches a heading or the content under one. To add a paragraph under a
heading, use `add-under-heading`; for any other change there, tell the owner to
edit the section by hand.

1. **Read the note.** Fetch the body with `(sns-roam-body-elements ID)`,
   never by reading the file. With the file-and-load idiom, the script writes
   `(mapcar #'org-ml-to-trimmed-string (plist-get result :elements))` to the
   `.out` file. Show those strings, in order, as the before text, and identify
   the element to change. When the change is under a heading, read that
   heading's section instead. Run `(sns-roam-body-search TITLE)`, take the
   `:point` of the hit in this note whose `:hit-text` is the heading's line,
   and call `(sns-roam-subtree ID POINT)`. Show its `:text` as the before
   text, and take the outline path from the `:raw-value` of each entry in its
   `:outline`. `sns-roam-subtree` reads the saved file, but the edit acts on
   the owner's Emacs buffer, so first check
   `(let ((b (get-file-buffer FILE))) (and b (buffer-modified-p b)))` for
   the note's `:file`. If it is non-nil, the owner has unsaved changes:
   ask them to save the note, and stop until they have. If `:elements` is
   nil and the change is not under a
   heading, tell the owner the note has no paragraphs before its first
   headline, and stop.
2. **Choose the tool.**
   - One paragraph/element changing, rest stays → `replace-element` (build a
     predicate that matches exactly that element, and the replacement AST).
   - One element being added, rest stays (e.g. a new history line) →
     `insert-element` (build a predicate that matches exactly the neighbour
     it goes beside, the new paragraph's AST, and AFTER non-nil to go after
     it). Never `set-body` for this.
   - Text before the first heading being rewritten (e.g. sparse fleeting note
     → full claim) → `set-body`. Headings stay as they are.
   - One paragraph being added under a heading, rest stays →
     `add-under-heading` (the outline path from step 1 and the new
     paragraph's AST). It goes after the heading's own text, before any child
     heading.
3. **Build the replacement as AST.** Preserve any `[[id:]]` links the old
   element carried unless the edit deliberately drops them. Reproduce them in
   the new element.
4. **SHOW** the before and after; confirm.
5. **APPLY**; then `org-roam-db-sync`.
6. **VERIFY** the file reads correctly and any links the note had still
   resolve (`expand` shows the same forward neighbours, unless intentionally
   changed). Show the user the `:diff` the edit returned, so a lost or
   changed line is visible at once, or say "no change" if it is `""`.

Predicate discipline: `replace-element` matches exactly one element or errors.
Write the predicate narrowly (match on distinctive text in the target
element), and if it matches zero or many, tighten it. Do not fall back to
`set-body` blindly, since that reproduces the text before the first heading and risks dropping
content.

### Promote a fleeting note

`:KIND: imported` / fleeting notes become `permanent` by *curation*, not
mechanically:
1. Rewrite the body into claim-shaped prose (`replace-element` or `set-body`).
2. `set-property` KIND → `permanent` (`KIND` lives in the property drawer;
   `set-keyword` would add a `#+kind:` line and leave the drawer unchanged).
3. `rename` if the title isn't yet a claim.
4. Link it into the graph (`append-link`): a permanent note is not finished
   until connected.

## Anti-Patterns (Do Not)

- **Do NOT auto-write.** Show candidates and get per-note confirmation first.
- **Do NOT write topic-shaped notes.** A title that isn't an arguable claim
  is wrong. Reshape or reject.
- **Do NOT pack two claims into one note** to save files. Split.
- **Do NOT build links by string-concatenating org markup.** Use
  `org-ml-build-link`; let the AST serialise.
- **Do NOT forget to pre-mint IDs** before building bodies that cross-link:
  forward references can't resolve otherwise.
- **Do NOT skip `org-roam-db-sync`**: the cluster is invisible to the graph
  until synced.
- **Do NOT call `append-link` without checking for an existing link first.**
  The primitive does not dedupe; `expand` the FROM note and skip if TO is
  already a forward neighbour.
- **Do NOT add a reciprocal link.** One-directional only; backlinks cover the
  reverse. Two physical links is double-maintenance. Person notes are the
  exception; see "Reference and person notes".
- **Do NOT slice-and-rejoin parsed org-ml node lists** in any transform: map
  the child list whole, filter don't slice.
- **Do NOT use `set-body` to change one element.** It replaces the text before
  the first heading, so you must reproduce everything you keep there and risk
  dropping content/links. Use `replace-element` with a narrow predicate.
- **Do NOT use `set-body` or `replace-element` on a heading.** They cannot
  reach one. To add a paragraph under a heading, use `add-under-heading`; for
  any other change there, tell the owner to edit that section by hand.
- **Do NOT write a loose `replace-element` predicate.** It must match exactly
  one element. Match on distinctive text; on zero/many it errors. Tighten it,
  don't work around it.
- **Do NOT drop existing `[[id:]]` links when rewriting an element.** Reproduce
  them in the replacement AST unless the edit deliberately removes them.
- **Do NOT editorialise the user's claims.**
  No rhetorical flourish in note bodies; state the claim and its support
  plainly. Banned: `load-bearing`, `the shape of X`, "the moment they matter
  most". The claims are the user's, not yours to embellish.
- **Do NOT capture operational/reference material as `:KIND: permanent`.**
  Permanent is for claims; reference is for sources, tables, logistics.
- **Do NOT reach into raw SQLite** or text-munge note files. Graph API +
  org-ml only.
- **Do NOT paraphrase the user's ideas into claims they didn't make.** The
  claims are theirs; surface candidates and let them correct.

## Tone

- Short, direct. Show the candidates; let the user steer.
- Quote claim titles verbatim in the show step and the result summary.
- Surface ambiguity (is this one claim or two?) as a one-line question;
  don't silently decide.
- Report files and edge counts after writing so the user can eyeball.

## Reference

- `src/roam-api.org` in <https://github.com/Atalanta/sns-roam>: the
  `sns-roam-*` primitives (literate source).
- The `roam-fetch` skill: the read sibling; reuse its pipeline for the
  neighbour-finding step.

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

Confirm the write primitives are present before composing:
`(mapcar #'fboundp '(sns-roam-create-node sns-roam-insert-element))`.
