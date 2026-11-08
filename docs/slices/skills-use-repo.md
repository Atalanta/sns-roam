# Slice 3: the roam skills run the repository's code

## Goal

When Claude runs `roam-fetch` or `roam-distill` in an Emacs without the roam code, the code loads from `~/Developer/sns-roam`. It no longer loads from the old copy in `~/.emacs.d`.

## Who uses it the day it lands

The owner, whenever they ask Claude a question about their slipbox or have it distil a braindump into notes.

## Stakes

Both skills tell Claude to load `~/.emacs.d/sns-emacs-modules/sns-roam-api.el`. The two copies match today. After the next fix in the repository, one skill run would replace the fix with the old copy and give no error. `turnstile review` raised this as CLJARCH-1 on slice 2. The skills are not under version control.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- Removing the old copies and the old org files from `~/.emacs.d`.
- Changing what the skills tell Claude to do, beyond the paths. Both skills load only when the primitives are unbound, so after a fix in the repository the owner reloads by running the load command or restarting Emacs. A skill run in an Emacs that already holds the roam code keeps using it.
- Linking any other skill, and tests for the skills.

## Invariants

- Both skills keep their frontmatter `name` and `description`. Otherwise Claude Code stops offering them under those names, as the skill list shows each session.

## Scenarios

Scenario: S3.1 A roam-fetch run loads the repository copy
  Given `roam-fetch` is linked to the repository and the running Emacs has not loaded the roam code
  When the owner asks Claude "what do my notes say about backups?" and `roam-fetch` runs
  Then `M-: (symbol-file 'sns-roam-find-by-metadata)` shows `~/Developer/sns-roam/lisp/sns-roam-api.el`

Scenario: S3.2 A roam-distill run loads the repository copy
  Given `roam-distill` is linked to the repository and the running Emacs has not loaded the roam code
  When the owner asks Claude to distil a short braindump and `roam-distill` runs
  Then `M-: (symbol-file 'sns-roam-set-body)` shows `~/Developer/sns-roam/lisp/sns-roam-api.el`

## Facts the builder needs

- `~/.claude/skills/roam-fetch` and `roam-distill` are ordinary directories. Their `SKILL.md` files name the old paths at `roam-fetch` lines 123, 378 and 398, and `roam-distill` lines 359 and 372. Checked on 2026-11-08.
- The load command in each is `emacsclient -e '(load-file "~/.emacs.d/sns-emacs-modules/sns-roam-api.el")'`. The primitives' source is `src/roam-api.org` in this repository, which tangles to `lisp/sns-roam-api.el`.
- `bilan`, `mine-commentary` and `weekly-report` in `~/.claude/skills` are links into repositories, and Claude Code lists them.

## Questions to resolve

None.

## Done when

The owner runs `ls -l ~/.claude/skills/roam-fetch ~/.claude/skills/roam-distill` and sees links into `~/Developer/sns-roam/skills/`. `grep -c -E '\.emacs\.d|sns-emacs-modules' ~/.claude/skills/roam-fetch/SKILL.md ~/.claude/skills/roam-distill/SKILL.md` prints `0` for each, where it printed 5 and 2 before. The owner restarts Emacs so it holds no roam code. They make the S3.1 request to Claude and see the repository path. They restart Emacs again, make the S3.2 request, and see the repository path. A new Claude Code session lists both skills (invariant). `mise run check` and `mise run test` pass.
