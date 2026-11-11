# Slice 15: installing sns-roam no longer brings in the Obsidian importer

## Goal

A person who installs sns-roam gets the API and nothing else: no Obsidian importer, no `yaml` package, and no instructions that mention either.

## Who uses it the day it lands

A second person, a Claude Code user, who will install sns-roam on their own machine, and the owner on any new machine.

## Stakes

The owner's Obsidian import is finished (owner, 2026-11-11). The importer's `use-package yaml :ensure t` crashed the first start on a new machine on 2026-11-08 (slice 8), and `Package-Requires` still lists `yaml` for it. A second user who installs today downloads a package nothing they use needs.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Notes in the owner's slipbox with `:KIND: imported`. They stay, and roam-fetch keeps its rules for them.
- The old copies in the owner's `~/.emacs.d`, which is a different repository, and the other README and skill changes planned for later slices.

## Invariants

- Every remaining primitive behaves as before: the tangled `lisp/sns-roam-api.el` differs only in its `Package-Requires` line (AGENTS.md, `mise run check`).
- Removed code stays in git history, so nothing is lost (AGENTS.md: the repository holds the literate sources).

## Scenarios

Scenario: S15.1 A fresh install brings in only what the API needs
  Given a batch Emacs with an empty package directory
  When the person installs sns-roam from the repository with `package-vc-install`
  Then `org-roam` and `org-ml` are installed, `yaml` is not, and `(require 'sns-roam-api)` returns `sns-roam-api`

Scenario: S15.2 The repository describes only the API and the skills
  Given the person has cloned the repository
  When they read `README.org`, `AGENTS.md` and the two skills
  Then the files list the API's sources and the two skills, and `grep -rn "roam-import\|importer" README.org AGENTS.md skills src` finds no match

## Facts the builder needs

- Delete `src/roam-import.org` and `lisp/sns-roam-import.el`. `mise run tangle` loops over `src/*.org`, so it needs no change.
- `Package-Requires` is on line 35 of `src/roam-api.org`. Nothing in `lisp/sns-roam-api.el` requires `yaml`.
- Importer mentions to remove: `README.org` line 8; `AGENTS.md` lines 3, 7 and 8; `skills/roam-fetch/SKILL.md` lines 11 and 38; `skills/roam-distill/SKILL.md` lines 12 and 32; and the `create-node` prose in `src/roam-api.org` near lines 1533 to 1725. Keep the `:KIND: imported` rules in roam-fetch.
- Slice 8's rehearsal installs from a `file://` URL to the local repository before the change is pushed.

## Questions to resolve

None.

## Done when

The builder runs S15.1 in a batch Emacs with a temporary `package-user-dir` and a `file://` URL to this branch, and shows the installed package list and the `require` result. It shows the S15.2 grep with no output, and `git diff main -- lisp/sns-roam-api.el` changing only the `Package-Requires` line. `mise run check` and `mise run test` pass.
