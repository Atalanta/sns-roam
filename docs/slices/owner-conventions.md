# Slice 17: the roam skills hold no one user's employers, tools or terms

## Goal

A second Claude Code user can use roam-fetch and roam-distill as written, and the owner's own conventions apply only for the owner, from the owner's own Claude instructions.

## Who uses it the day it lands

A second person, a Claude Code user, setting up the skills; and the owner, whose sessions keep working as before.

## Stakes

The skills name the owner's employers in the person-note rule, hand off to Aldi skills the owner no longer uses (owner, 2026-11-11), trigger on "BWC/BWJ" sessions they never define, and cite the owner's "Vice Lisp" memory. A second user would get person notes judged by someone else's employers and handoffs to skills they don't have.

## Appetite

30 minutes of the owner's time at most, from approved plan to merge request.

## Out of scope

- The README (a later slice), and any change to the API.

## Invariants

- For the owner, roam-distill still activates at the end of a BWC/BWJ session, and people inside Ticketmaster and Live Nation still stay plain names (owner's current rules, `skills/roam-distill/SKILL.md` lines 4, 195 and 201).
- The elisp rules in the skill keep their content: data over state, batched mutations, loud failure (the skill's current "Vice Lisp discipline" section).

## Scenarios

Scenario: S17.1 A second user's external contact gets a person note
  Given a second user whose Claude instructions name "Acme" as their organisation
  When they ask Claude to capture a meeting with Jo Bloggs of Initech and Sam Lee of Acme
  Then Claude proposes a person note for Jo Bloggs, and names Sam Lee in plain text with no person note

Scenario: S17.2 The owner's conventions come from the owner's instructions
  Given the owner's `~/.claude/CLAUDE.local.md` with a "Roam conventions" section
  When the owner reads that section and the two skills
  Then the section holds the BWC/BWJ trigger and the Ticketmaster and Live Nation rule, and the skills name neither, nor Aldi

## Facts the builder needs

- Owner-specific lines, from `grep -n -i "aldi\|gtd\|BWC\|BWJ\|ticketmaster\|live nation\|vice lisp\|feedback-" skills/*/SKILL.md`: roam-fetch lines 9, 10, 32 and 345; roam-distill lines 4, 10 to 14, 25, 31, 57, 61 to 64, 105, 195, 201, 202, 279, 338, 344 and 505.
- The skills tell Claude to apply the user's own roam conventions from their Claude instructions (CLAUDE.md or memory), and say what a convention can set: which organisations count as the user's own, and extra phrases that start roam-distill.
- `~/.claude/CLAUDE.local.md` is the owner's personal file and is marked safe to edit. The new section moves the owner's text word for word, without expanding BWC or BWJ, which no file defines.

## Questions to resolve

None.

## Done when

The grep above finds no match in either skill. The owner reads the new "Roam conventions" section in `CLAUDE.local.md`, the skills' conventions paragraph, and the renamed elisp section beside the old one in `git diff`, and finds the same three rules. The builder also runs S17.1 as the owner, with Ticketmaster in place of Acme, and shows the Ticketmaster person kept as a plain name. The builder runs S17.1 by hand in a Claude session with a temporary instruction naming Acme, and shows the proposed notes. `mise run check` and `mise run test` pass.
