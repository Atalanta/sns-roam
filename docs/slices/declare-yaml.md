# Slice 8: a first start on a new machine no longer crashes during the install

## Goal

On a machine without the checkout, Emacs finishes installing `sns-roam-api` from GitHub, and `init.el` runs to its last module, `sns-functions`. Package failures that `use-package` logs and survives may remain (see Out of scope); a second fatal error would end the slice, and the builder reports it for a new slice.

## Who uses it the day it lands

The owner, the first time they clone `~/.emacs.d` onto another machine.

## Stakes

A first start in a clean Ubuntu VM on 2026-11-08 stopped inside `package-vc-install` with `wrong-type-argument (stringp yaml)`, and the rest of `init.el` never loaded. `lisp/sns-roam-import.el` runs `(use-package yaml :ensure t)`. While the package compiles, that form adds `yaml` to `package-selected-packages` as a symbol with position, and sorting the list fails. A host rehearsal with two other packages in the list reproduced it.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Other failures in that VM run: `ef-themes`, `vertico`, `marginalia` and `orderless` failed to install with `stringp, nil`. Cause not yet known.
- Compiler warnings in `sns-roam-import.el`.
- Changing how the importer works.

## Invariants

- The importer still loads `yaml` and finds it when `sns-roam-import` loads.
- The tangled `lisp/*.el` stays in step with `src/*.org` (`mise run check`).

## Scenarios

Scenario: S8.1 A clean clone's first start reaches the last module
  Given the clean Ubuntu VM with a fresh clone of `~/.emacs.d`, tangled, and no checkout
  When Emacs starts with `early-init.el` and `init.el`
  Then `sns-roam-api` is installed, the log has no `wrong-type-argument (stringp yaml)` error, and `(featurep 'sns-functions)` is `t` when the run ends
  And `commandp` of `sns-roam-meeting-note` is `t` and `(require 'sns-roam-import)` loads `yaml`

Scenario: S8.2 The install survives other selected packages
  Given a batch Emacs with an empty package directory, `package-selected-packages` holding `vertico` and `orderless`, and no checkout
  When it installs `sns-roam-api` from the repository
  Then the install finishes without error and `yaml` is installed as a dependency

## Facts the builder needs

- The form is in `src/roam-import.org` line 88, tangled to `lisp/sns-roam-import.el`. The package header is in `src/roam-api.org`.
- `yaml` installed in the VM as `yaml-20260605.834`. The host has `yaml-mode`, not `yaml`.
- The host rehearsal is `/tmp/s71b.el`, run with the real GitHub URL. The install fetches `main`, so the fix must be pushed before S8.1 and S8.2 can pass against GitHub; the builder may use a `file://` URL to the local repo first.

## Questions to resolve

None.

## Done when

The builder shows the crash from the host rehearsal before the change, then S8.2 passing after it. A new ert test fails if any file in `lisp/` contains `:ensure`; with the `use-package yaml :ensure t` form restored, the builder shows the test failing. `Package-Requires` lists `yaml` at the tested version. The builder repeats the clean-clone start in the VM (S8.1), shows the log lines, and shows `(require 'sns-roam-import)` returning and `(featurep 'yaml)` printing `t` in that session. `mise run check` and `mise run test` pass.
