---
name: full-codebase-audit
description: Runs an exhaustive, project-specific correctness and security audit of the entire Peak Coach AI codebase (backend and frontend, not just a diff), using a checklist grounded in this project's actual architecture rather than generic advice. Uses a multi-phase hunt-then-independently-verify pipeline across parallel subagents so findings are evidence-backed, not speculative, then produces both an in-chat findings report and a persisted markdown report. Only invoke explicitly via /full-codebase-audit — this is a deliberate, thorough, token-heavy full-repository review, not a lightweight check.
disable-model-invocation: true
effort: high
allowed-tools: Read Grep Glob
---

# Full codebase audit

A whole-repository audit, not a diff review. Every finding MUST be traceable
to a concrete `file:line` and a concrete failure scenario ("with input X /
state Y, the code does Z instead of the correct thing") — never a vague
"could be improved" or "consider adding." If you can't construct the failure
scenario, it is not a finding; drop it or mark it PLAUSIBLE in the validate
phase, never CONFIRMED.

## Phase 0 — Load prior audits (once, before anything else)

`docs/audits/` may contain previous reports from earlier runs of this skill.
List that directory. If reports exist, read the **most recent** one in full
and extract its findings list (file, summary, verdict, outcome if any). Carry
this forward as "previously flagged" — in the final report, cross-reference
new findings against it:
- A finding that still reproduces at the same location → keep it, note
  "still open since <date>".
- A previously-flagged finding that no longer reproduces → note it as
  resolved, don't re-list it as new.
- Do not pad the new report with unchanged boilerplate from the old one —
  only the delta and the still-open items matter to the reader.

If no prior report exists, skip straight to Phase 1.

## Phase 1 — Recon

Read `CLAUDE.md` and `docs/architecture.md` (if present) in full so the
architecture in your head matches the real one before you go hunting for
deviations from it. Then run, and read the output of:

- `find backend/apps -maxdepth 1 -type d` and `find frontend/lib/features -maxdepth 1 -type d`
  to confirm the subsystem groups in CHECKLISTS.md still match the actual
  app/feature list — if a new app or feature exists that isn't covered by any
  group below, add an ad-hoc Group 10 for it using the cross-cutting checks
  only.
- `cd backend && source venv/bin/activate && python manage.py check && python manage.py makemigrations --check --dry-run` —
  record any output verbatim; a non-empty result from either is itself a
  finding (drift between models and migrations, or a system check failure).
- `cd frontend && flutter analyze` — record any output verbatim; any issue
  reported is itself a finding.

These tool outputs are objective and don't need a validate pass — include
them in the report as-is, tagged `category: tooling`.

## Phase 2 — Hunt (parallel, grounded subagents)

Read `CHECKLISTS.md` in full now (not later — you need the whole thing to
route findings and to know what NOT to duplicate across groups).

Launch all 9 subsystem-group agents from CHECKLISTS.md **in parallel** (one
message, multiple Agent tool calls), `subagent_type: general-purpose`,
`run_in_background: false` (you need every group's results before Phase 3
can start). For each, the prompt MUST:

1. State the exact file scope for that group (copy from CHECKLISTS.md).
2. Instruct the agent to **read every file in that scope in full** — not an
   Explore-style excerpt/grep pass. Say so explicitly; a general-purpose
   agent defaults to shallow reads otherwise.
3. Paste that group's full checklist section verbatim.
4. State the output contract: a list of candidate findings, each with
   `file`, `line`, a short code quote, `category` (correctness /
   security / consistency-with-CLAUDE.md / efficiency / test-coverage),
   `summary`, and `failure_scenario` (concrete inputs/state → concrete wrong
   outcome). No candidate without a failure_scenario. If the agent finds
   nothing in a section, say so rather than inventing filler.
5. Tell the agent this is read-only investigation — no Edit/Write, no
   fixing anything.

Collect all 9 result sets before moving on.

## Phase 3 — Validate (independent re-verification)

This is what separates this audit from a generic pass: nothing reaches the
report on the finder's word alone.

For each group's candidate list, launch a **second, separate**
`general-purpose` agent (not the same one that found them) with:

1. The candidate findings for that group only — `file`/`line`/`summary`/
   `failure_scenario`, stripped of which model/reasoning produced them.
2. An instruction to independently open each cited file at the cited line,
   confirm the code actually reads the way the candidate claims, and try to
   construct the failure scenario itself from the real surrounding code
   (imports, callers, related model fields) — not just trust the prose.
3. A required verdict per candidate:
   - `CONFIRMED` — re-derived the same failure scenario from the source.
   - `PLAUSIBLE` — the concern is logically sound and the code supports it,
     but full confirmation would need running the app/DB (say what would
     confirm it).
   - `REJECT` — the code doesn't actually do what the candidate claims, or
     the described scenario can't occur (say why, specifically — "this is
     already guarded at line N" or similar).
4. Instruction to escalate or downgrade severity if the independent read
   reveals the candidate under- or over-stated impact.

Run these 9 validator dispatches in parallel too. Drop every `REJECT`.
Everything else proceeds to the report with its verdict attached.

## Phase 4 — Report

Merge: Phase 1's tooling output + all `CONFIRMED`/`PLAUSIBLE` findings from
Phase 3, sorted most-severe first. Severity bands: Critical (data
loss/security/wrong money-equivalent numbers reaching a user) > High
(incorrect behavior a real user will hit) > Medium (incorrect behavior in an
edge case) > Low (real but low-impact) > Structural (architecture/consistency
debt, not a bug per se).

1. Call `ReportFindings` once with the merged, verified list — this renders
   the in-chat report. Use `outcome` only if this run is re-reporting after
   fixes were applied (it normally isn't; this skill is audit-only).
2. Write the full report to
   `docs/audits/<YYYY-MM-DD>-full-codebase-audit.md`:
   - One-paragraph executive summary (counts by severity, headline risk if
     any).
   - "Previously flagged" section from Phase 0 (still-open / resolved).
   - Tooling output from Phase 1, verbatim.
   - Findings grouped by severity, each with file:line, summary,
     failure_scenario, verdict, and which subsystem group surfaced it.
   - A short "coverage" section: which groups ran, file counts per group,
     and anything skipped (e.g., a new app not yet covered — see Phase 1).
3. Do not fix anything. This skill is report-only. If the user wants fixes
   applied, that's a separate explicit request after they've read the
   report.
