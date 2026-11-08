# Slice 7: a machine without the checkout installs the library from GitHub

## Goal

On a machine with no `~/Developer/sns-roam`, Emacs installs the library from `https://github.com/Atalanta/sns-roam` and `M-x sns-roam-meeting-note` runs from the installed copy. On this machine Emacs still loads the checkout.

## Who uses it the day it lands

The owner, the first time they clone `~/.emacs.d` onto another machine.

## Stakes

The current config block names `~/Developer/sns-roam/lisp`. On a new machine the command fails with "Cannot open load file". The owner's clone of `~/.emacs.d` used to work without extra steps, and this change would be the first thing that breaks that. The library also has no package header, so no installer can read it. A wrong dependency line would pull the wrong packages.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- The skills' hard-coded `~/Developer/sns-roam` load path, and the `yaml` dependency of `sns-roam-import.el`.
- Publishing to an archive, and pinning a commit.
- Removing the old copies in `~/.emacs.d`.

## Invariants

- On this machine Emacs loads `~/Developer/sns-roam/lisp/sns-roam-api.el`, not an installed copy. Otherwise a fix in the checkout would sit beside a stale copy, as in slice 2's CLJARCH-1.
- The tangled `lisp/sns-roam-api.el` stays in step with `src/roam-api.org` (`mise run check`).

## Scenarios

Scenario: S7.1 A machine without the checkout installs the library
  Given a batch Emacs with an empty package directory and the checkout path set to a directory that does not exist
  When it evaluates the committed config block, before anything has loaded the library
  Then `(commandp 'sns-roam-meeting-note)` is `t`, so `M-x` offers it
  And after calling it, the package directory holds an installed `sns-roam-api` and `symbol-file` of the command points into it

Scenario: S7.2 This machine keeps loading the checkout
  Given the checkout exists
  When the same block is evaluated with an empty package directory
  Then nothing is installed and `symbol-file` of the command points at `~/Developer/sns-roam/lisp/sns-roam-api.el`

## Facts the builder needs

- `package-buffer-info` errors on `lisp/sns-roam-api.el` today. Its header is the first code block of `src/roam-api.org`.
- Neither org-roam nor org-ml declares a `Version:` header. In `~/.emacs.d/elpa` they are 20260425.1623 and 20250514.2314, and Emacs is 31.1 (checked 2026-11-08).
- The block is in `~/.emacs.d/README.org`, subsection "The sns-roam bridge", committed as 6894643. The file also holds uncommitted changes of the owner's, to stay out of the commit.
- `use-package` takes `:vc (:url ... :lisp-dir "lisp")` in Emacs 31.

## Questions to resolve

None.

## Done when

`package-buffer-info` on the committed file returns name, version, author, URL and requirements (emacs, org-roam, org-ml, each at the tested version) and erroring before. An ert test fails when `Package-Requires` is removed; the builder shows that run. The builder runs S7.1 and S7.2 in batch Emacs and shows the `commandp` result, the package directory listing and both `symbol-file` results. The owner restarts Emacs, sees no `*Warnings*` buffer, and `M-: (symbol-file 'sns-roam-meeting-note)` after running the command shows the checkout path. `mise run check` and `mise run test` pass.
