# sns-roam

An Emacs Lisp bridge between Claude and an org-roam slipbox. It has read primitives and mutation primitives built on org-ml.

## Layout

- `src/roam-api.org` is the literate source.
- `lisp/sns-roam-api.el` is tangled from it and committed.
- `docs/design/` holds the design notes for a generic org-ml editing bridge. They are drafts, and the code doesn't implement them yet.

## Commands

- `mise run tangle` rewrites `lisp/` from `src/`.
- `mise run check` tangles, then fails if `lisp/` differs from what is committed.

## Rules

- Edit `src/*.org`. Never edit `lisp/*.el`, which is generated. In June 2026 `sns-roam-meeting-note` was added to the tangled file by hand, and the org source lacked it until it was restored when this repository was created.
- Public names start with `sns-roam-` and private ones with `sns-roam--`.
- Functions take and return plists. Edits to a note's body go through the single write boundary, `sns-roam--update-section`.
- Failure is loud. An unknown ID or a match that isn't unique raises an error with the `sns-roam:` prefix, and no code path guesses.
- When you change the body of a parsed org-ml section, map over the full child list and filter it. Don't slice it into sublists and join them again, because that corrupts the buffer positions org-ml reconciles against.
