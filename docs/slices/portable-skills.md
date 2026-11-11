# Slice 16: the roam skills load the API and find the slipbox on any machine

## Goal

A second Claude Code user who has installed sns-roam can ask roam-fetch about their own slipbox, wherever it is, and get an answer, without editing any path in the skills.

## Who uses it the day it lands

A second person, a Claude Code user, who installs sns-roam with `package-vc-install` and links the two skills into `~/.claude/skills`; and the owner on a new machine.

## Stakes

Both skills load the API with `(load-file "~/Developer/sns-roam/lisp/sns-roam-api.el")`, state the slipbox is `~/roam/`, and point to memories only the owner has (checked 2026-11-11). On another machine the load fails and Claude looks for notes in the wrong place. The owner wants the second user to start soon.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- The owner's own policy in the skills: the Ticketmaster and Live Nation person-note rule, the Aldi handoffs, the BWC/BWJ triggers and the Vice Lisp standard. A later slice moves them.
- The README, and installing the skills by any means other than a symlink.

## Invariants

- On the owner's machine the skills behave as before: Emacs already loads sns-roam from the checkout, so `(require 'sns-roam-api)` finds it (README.org, slice 2).
- The skills stay read-first and follow show, confirm, apply (each skill's own rules).

## Scenarios

Scenario: S16.1 A second user's slipbox is found where their Emacs keeps it
  Given an Emacs with sns-roam installed by `package-vc-install`, not yet loaded, and `org-roam-directory` set to a directory other than `~/roam/` holding a note titled "Tide tables"
  When the user asks Claude, through roam-fetch, what their notes say about tide tables
  Then Claude loads the API, names that directory as the slipbox, and cites the "Tide tables" note

Scenario: S16.2 An Emacs without sns-roam gets an install instruction
  Given an Emacs where `(require 'sns-roam-api)` fails
  When the user asks Claude a roam-fetch question
  Then Claude reports that sns-roam is not installed and gives the `package-vc-install` command with the repository URL

## Facts the builder needs

- Hard-coded references to replace, from `grep -n "Developer/sns-roam\|~/roam\|memory \`"`: `skills/roam-fetch/SKILL.md` lines 73, 89, 123, 377 to 388 and 398; `skills/roam-distill/SKILL.md` lines 268, 465, 476, 502 and 515. The Vice Lisp line 63 is for the later slice.
- The load step becomes: if `sns-roam-find-by-metadata` is unbound, `(require 'sns-roam-api)`; if that fails, report S16.2. The slipbox location comes from `org-roam-directory` in the running Emacs.
- The skills already state the file-and-load idiom and the "Note references:" trailer, so each memory pointer can go without losing a rule.
- The repository URL is `https://github.com/Atalanta/sns-roam`. Slice 15's rehearsal script, `/tmp/s15/install.el`, installs with `package-vc-install` into a temporary `package-user-dir`.

## Questions to resolve

None.

## Done when

The builder starts a separate Emacs server with the package installed by the slice 15 method and a temporary `org-roam-directory` holding "Tide tables". It runs the skill's load step and stage 1 through `emacsclient -s` to that server, and shows the directory and the note in the output (S16.1). It runs the load step against a server without the package and shows the S16.2 message. The grep above finds no match in either skill. `mise run check` and `mise run test` pass.
