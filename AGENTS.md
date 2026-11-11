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

## The owner's machine

- Emacs loads sns-roam from this checkout, through a `use-package` block in `~/.emacs.d/README.org`, so `(require 'sns-roam-api)` finds `lisp/` here.
- The skills in `~/.claude/skills` are links to `skills/` in this checkout.
- After changing `lisp/`, reload it in the running Emacs: `emacsclient -e '(load-library "sns-roam-api")'`.
- The history of `src/roam-api.org` comes from `~/.emacs.d`. Old copies there, in `roam-api.org`, `roam-import.org` and `sns-emacs-modules/`, are unused.

## Turnstile setup in a fresh clone

Git does not commit its config, so set these once per clone:

```sh
git config turnstile.lenses clojure
git config turnstile.check 'mise run check && mise run test'
git config turnstile.base main
git config turnstile.worker 'claude -p --output-format json --permission-mode acceptEdits --no-session-persistence --allowedTools "Bash(mise run tangle)" "Bash(mise run test)" "Bash(mise run check)" "Bash(emacs --batch *)" "Bash(git diff *)" "Bash(git status *)" "Bash(git log *)"'
```

The worker's allowed tools let it tangle and run the tests, and nothing else in the shell. `turnstile land` opens merge requests with `glab`, which fails on this GitHub repository, so a change that passes the review and the check reaches `main` by a fast-forward merge and a push.
