# Slice 2: Emacs starts with the meeting note available

## Goal

After the owner restarts Emacs, `M-x sns-roam-meeting-note` creates a dated meeting note with no manual load.

## Who uses it the day it lands

The owner, each time they start a note for a recurring meeting.

## Stakes

Emacs loads none of the roam code at startup today, so the command is unbound until someone loads the file by hand. The owner keeps Emacs open all day. An error in the new config block would stop Emacs starting cleanly.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Making the other primitives available at startup. The Claude skills load the file themselves today.
- Moving the skills into this repository.
- Making the library require org-ml itself. The config already loads org-ml at startup.
- A load path that works on another machine.

## Invariants

- Emacs still starts and loads its other modules in order. Otherwise the owner has no working editor (`init.el` and `~/.emacs.d/README.org`).

## Scenarios

Scenario: S2.1 The meeting note works after a restart
  Given Emacs has just started and nothing has loaded the roam code
  When the owner runs `M-x sns-roam-meeting-note` and enters "alan-smithee-1-1"
  Then a buffer opens on a new note titled "alan-smithee-1-1" with today's date
  And `M-x describe-function` on the command shows `~/Developer/sns-roam/lisp/sns-roam-api.el` as its file

## Facts the builder needs

- `~/.emacs.d/init.el` requires each module in `~/.emacs.d/sns-emacs-modules`, ending with `sns-functions`. `sns-knowledge-base` holds the org-roam config and is tangled from `~/.emacs.d/README.org`.
- In the Emacs started on 2026-11-07, `sns-roam-meeting-note` is unbound and `sns-roam-api` is not loaded. org-ml is loaded. Checked on 2026-11-08.
- `~/.emacs.d/sns-emacs-modules/sns-roam-api.el` is byte-identical to `lisp/sns-roam-api.el` and is on the load path. A directory added with `add-to-list` goes in front, so the repository copy wins if the block runs after `init.el` sets the path.
- The config has no `:load-path` precedent.

## Questions to resolve

None.

## Done when

The owner restarts Emacs, runs `M-x sns-roam-meeting-note`, enters "slice2-check", and sees a buffer on `~/roam/<timestamp>-slice2_check.org` titled "slice2-check" with today's date (S2.1). `M-x describe-function` on the command shows the repository file (S2.1). Before the change, the same command answers "[No match]". The owner sees no `*Warnings*` buffer after the restart, and `M-: (featurep 'sns-functions)` answers `t`, because `init.el` requires that module last (invariant). The owner deletes the test note. `mise run check` passes in this repository.
