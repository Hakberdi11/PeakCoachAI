# Strength Integration Strategy (`goal = increase_strength`)

**Status:** Proposal for review. No code, migrations, or config have been changed. Nothing here is approved.
**Inputs:** `docs/research/strength-findings.md` (ground truth for every number below; section references are to that document unless prefixed `H§`, which refers to `docs/research/hypertrophy-findings.md`), `docs/research/coach-integration-strategy.md` (the hypertrophy-goal integration proposal this document extends), plus the current state of `apps/onboarding`, `apps/workouts`, `apps/adaptation`, `apps/progress`, and `frontend/lib/features/{onboarding,progress}`.
**Scope:** how to make the `increase_strength` path numerically grounded and genuinely distinct from `build_muscle`, reusing the shared prescription/adaptation infrastructure rather than forking it.

---

## 0. Recommendation summary (read this if nothing else)

Today, `increase_strength` differs from `build_muscle` by exactly one substring in one f-string: `- Goal: Increase Strength` in `_build_prompt()`. Nothing downstream reads the goal. The consequences are concrete and mostly *wrong in the direction that matters most for strength*:

- **Rest defaults to 90 s** in three places (`PlannedExercise.rest_seconds` default, `_to_display_shape`, `persist`). §6 puts heavy strength work at **180–420 s**. Any exercise the model omits a rest value for silently gets a prescription the research explicitly says **"converts a strength set into a hypertrophy set."**
- **There is no load field anywhere.** `PlannedExercise` has sets and reps only. Strength is the one goal where **load is the strongest single moderator of the outcome** (§1) — an app that prescribes "5 reps" without prescribing "at 85% of your 1RM" has not prescribed strength training at all.
- **No 1RM, estimated or otherwise, exists in the data model.** `PersonalRecord` stores `(exercise_name, weight, reps)` but PR detection in `session_service.log_set` compares **weight only**, so 100 kg × 1 counts as a PR over 97.5 kg × 5 (a materially *better* performance, e1RM ~110 vs ~100). For a strength goal, the app's own progress metric is currently mis-ranked.
- **`evaluate_reps` is a hypertrophy rule applied to a strength user.** It compares reps against a fixed rep window and never looks at load, RIR, or the previous exposure — so it cannot express any of §8's autoregulation rules, and it will fire `DECREASE_LOAD` on a perfectly normal heavy single that "missed" a 3-rep target.
- **No periodization state exists.** Each `generate()` call produces a fresh plan with no memory of what week or phase the user is in, which makes §4's block structure and §4's taper (the best-evidenced part of the whole report) unimplementable.

Prioritized recommendation:

| # | Change | Effort | Payoff | New user data? |
|---|---|---|---|---|
| 1 | **Goal-strategy inside the shared prescription layer** — one `compute_prescription()` entry point, a `StrengthStrategy` alongside `HypertrophyStrategy`, emitting load %1RM, sets, reps, rest, RIR per lift | M | Very high — this is the whole "not templated, and not hypertrophy-with-a-label" delta | No (works on existing fields, poorly) |
| 2 | **`StrengthEstimate` (e1RM) model + AMRAP-free seeding**, then passive maintenance from every logged set | M | Very high — converts every %1RM in the report into a kg number | Optional 1 screen |
| 3 | **`target_load_kg` + `target_rir` on `PlannedExercise`; `rir` + `is_warmup` on `SetLog`** | S | Very high — without a load field the strength plan is not expressible | Yes (in-workout, 1 tap) |
| 4 | **Fix the 90 s rest default** → compute rest from load bracket (§6) | XS | High — currently a silent, systematic under-prescription | No |
| 5 | **`PeriodizationState` (phase + week index + block target)** as first-class state driving regeneration | M | High — unlocks blocks, deloads, taper, test scheduling | No |
| 6 | **3 conditional onboarding screens shown only when `goal == increase_strength`** (target lifts, current working weights w/ skip, max-test history) | S | High | Yes (conditional, ~+2 net screens for strength users only) |
| 7 | **Session-1/2 calibration protocol** — a ramp to a top set of 3–5 at RPE 8, e1RM via Brzycki, replacing any true-max request at onboarding | M | High — the safe alternative to asking a novice for a 1RM | Yes (in-workout) |
| 8 | **Strength-specific adaptation rules** (e1RM trend, RIR-delta load steps, reactive deload, phase transition) alongside — not replacing — `evaluate_reps` | M | High | Needs #3 |
| 9 | **e1RM-based PR detection** replacing weight-only comparison; surface e1RM trend in `/progress` | S | Medium–high — it is the report's #1 recommended progress signal (§12) | No |

**Net onboarding change:** shared flow unchanged in length for the other four goals. Strength users see **+3 conditional screens**, of which the first two are the ones that carry all the numeric value and the third is two taps. Under the pruning already proposed in `coach-integration-strategy.md` §3.2 (12 → 11 shared screens), a strength user lands at **13 screens** or **11** if the working-weights screen is deferred to session 1 (see §4.4 tradeoff).

---

## 1. Problem framing

### 1.1 What "distinct from hypertrophy" has to mean numerically

The two research reports disagree, deliberately and substantially, on the parameters that define a program. This is the divergence the product must express:

| Parameter | `build_muscle` (H§ glance table) | `increase_strength` (§ glance table) | Divergence |
|---|---|---|---|
| Primary load | 65–85% 1RM | 75–95%+ 1RM | Materially heavier |
| Primary reps | 6–12 (bulk) | 1–5 | 2–3× fewer |
| Rest, compounds | 120–300 s | 180–300 s heavy; **180–420 s at ≥90%** | Longer, and hard-floored |
| RIR, main work | 0–3, closer to failure is better | **1–3, flat across RIR 0–4; closer to failure may be slightly *worse*** | Opposite gradient |
| Weekly volume | 10–20+ sets/muscle, accrues to 20–30+ | Most benefit by 5–10 sets/lift, near-flat past 15–20 | Volume is a *hypertrophy* lever |
| Frequency driver | Distributes volume | Distributes **skill practice** + heavy exposure | Same mechanism, different rationale |
| Exercise selection | Variation is fine/good; equipment-agnostic | **Specificity**: same lift, ROM, grip, tempo. Transfer from a similar-but-different exercise is **1/2 to 1/3** of the direct effect | Hard constraint, not preference |
| Periodization | Model matters little | Periodized > non-periodized **ES 0.43**; taper worth **+2–6% 1RM** | First-class, phase-structured |
| Progress signal | Rep/weight PRs | **e1RM from a top set at RPE 8–9**, ±3–6% | Different metric |

The critical asymmetry, stated verbatim in §2: **"more volume is a hypertrophy lever, more load/specificity is a strength lever."** A strength plan that is a hypertrophy plan with lower rep numbers is still wrong, because it will lack heavy exposure frequency (§1: ≥1 set/week at ≥90%), specificity constraints (§7), rest length (§6), and phase structure (§4).

### 1.2 What the code does today, precisely

`_build_prompt()` interpolates 11 qualitative labels into prose and asks the model to "design a training split." The only hard constraints stated are day count and equipment. For a strength user, the prompt never mentions %1RM, RIR, a load, a phase, a target lift, or a rest bracket. The output schema is `{name, sets, reps_min, reps_max, rest_seconds, order}` — there is nowhere to *put* a load even if the model produced one.

Three specific defects that bite strength harder than hypertrophy:

1. **`rest_seconds` default 90.** Appears in `PlannedExercise.rest_seconds = models.PositiveSmallIntegerField(default=90)`, in `_to_display_shape` (`exercise.get('rest_seconds', 90)`), and again in `persist()`. §6 is High-confidence that ≤1 min rest measurably reduces 1RM gain vs 3 min, and that short rest cuts tonnage at high loads by 20–40%.
2. **Weight-only PR detection.** In `session_service.log_set`, `previous_best` is `.order_by('-weight').first()` and `is_new_pr = weight > previous_best.weight`. Per §12, the right frequent signal is **e1RM from a 2–5 rep top set**, and **each additional rep at a fixed load ≈ +2.5–3.5% e1RM**. Rep PRs at a fixed load are currently invisible to the app — for a strength user that is the majority of their real progress.
3. **`evaluate_reps` semantics.** `failed >= 2 → DECREASE_LOAD` where `failed = sum(1 for s in sets if s.reps < planned.target_reps_min)`. On a strength plan of 5×3 @ 90%, a user who gets 3,3,3,2,2 (a normal, productive heavy session with fatigue-driven dropoff) is told to reduce load. `exceeded_all` (every set above `target_reps_max`) essentially never fires at ≥85% 1RM, so the strength user gets asymmetric, downward-only adaptation.

### 1.3 What already exists and should be reused

- `PersonalRecord` (`apps/progress`) is the natural home for strength-goal progress surfacing and already has `(exercise_name, weight, reps, session, achieved_at)` — enough to compute e1RM retroactively.
- `AdaptationHistory` + the `generate()` → `_format_adaptation_notes()` loop already gives a place to persist and re-inject coaching decisions.
- `generate_preview_from_profile()` is the single funnel all three plan paths share, so any prescription layer inserted there covers the anonymous preview, save-preview, and regeneration paths at once.
- The `coach-integration-strategy.md` proposals for `training_age_months`, numeric `session_minutes`, structured limitations, `SetLog.rir`, `SetLog.is_warmup`, `TrainingBlock`, and the post-generation validator are **all prerequisites for this document too**. This proposal adds to them; it does not duplicate them.

---

## 2. Data-needs analysis: what a numerically-grounded strength prescription requires

Each row: the parameter from the findings, the input needed to compute it, why, and current status.

### 2.1 Load (%1RM → kg) — the parameter that defines the goal

| Input | Why (research) | Status |
|---|---|---|
| **Estimated 1RM per target lift** | §1: prescriptions are 75–95% 1RM. Without a 1RM, "85%" is not a number the user can put on a bar. §12: e1RM from a 2–5 rep top set is ±3–6% — good enough to prescribe from. | **Missing entirely.** No field, no model, nothing derivable except historical max weight in `SetLog`/`PersonalRecord`, which is not the same thing. |
| **Which lifts are the target lifts** | §1: specificity effects are **2–3×**. §7: the competition lift gets 60–80% of direct volume in strength/peak phases. You cannot allocate 60–80% of volume to "the target lift" if you don't know what it is. | **Missing.** `priority_muscles` is a *muscle* list, which is the hypertrophy framing; strength is organized by **lift/movement pattern**. |
| **Per-lift e1RM, not a global one** | §5: upper body progresses at **40–60%** the absolute rate of lower body; §11d gives per-lift frequency, set, and rest tables. §12: e1RM accuracy is worse for deadlift than bench. Lift-level granularity is mandatory. | Missing |
| **Training age (months)** | §1/§ glance: 75–85% (novice) / 80–92% (intermediate) / 85–95%+ (advanced) for main-lift work. | **Partial** — 3-way `experience` label, where "intermediate" spans a 1–3 yr band the report treats as one row but "beginner" spans 0–12 mo where the report changes prescription *within* the year (§4: linear session-to-session at 0–9 mo, WUP after). |
| **Bodyweight** | Fallback seed for e1RM when unknown; also §10 (absolute strength scales ~BM^0.67, +1 kg BM ≈ +1–2% total). | **Have** (`weight_kg`), but captured once and never again. |
| **Sex** | §11a is explicit: **%1RM-to-rep tables built on male data under-load women** (women often +1–5 reps at 60–80% 1RM). Prefer RPE/RIR or individual rep-max testing. This changes how e1RM is *estimated from reps*, not the load prescription itself. | **Have** (`gender`) |
| **Equipment / plate increments** | §5: increments are +2.5–5 kg lower body, +1–2.5 kg upper, micro-plates 0.5–1.25 kg. A computed load must be rounded to something the user can actually load. | **Partial** — `equipment` is a category list, no plate/dumbbell increment info |

### 2.2 Volume — sets per lift per week

| Input | Why | Status |
|---|---|---|
| **Training age** | §2 table: 6–10 / 9–15 / 12–20 direct sets/week per competition lift. | Partial |
| **Phase** | §4: accumulation 12–20 sets/wk/pattern, strength 10–15, peak 5–9. Volume is phase-dependent, so a single weekly number is not enough — it needs a phase to index into. | **Missing** |
| **Per-lift identity** | §11d: squat 10–18, bench 12–20, deadlift **5–12**, OHP 8–15 heavy sets/week. Deadlift is not squat. | Missing |
| **Direct vs accessory split** | §2: strength block 65–80% direct / 20–35% accessory; accumulation 45–60% / 40–55%. Requires each planned exercise to be classified by **carryover tier** (§7: competition / near-identical / moderate / general / isolation). | **Missing** — `PlannedExercise` has a name string only |
| **Age** | §11c: >40–50 → fewer ≥90% exposures (1×/wk or every 10–14 d), deload every 3–5 wk. | **Have** |
| **Session minutes** | §6 rest brackets of 3–5 min make strength sessions *time-expensive*: 5 sets at 4 min rest is 20 min of rest for one exercise. A 30-minute session cannot contain a compliant heavy prescription. This is a harder constraint for strength than for hypertrophy. | **Partial** — `workout_duration` is a CharField including the non-numeric `'90+'` |

### 2.3 Frequency

| Input | Why | Status |
|---|---|---|
| **Training days/week** | §3: 2–3 / 2–4 / 3–5 sessions touching each lift. The **scaling rule is `frequency ≈ weekly sets ÷ 4–5`** with per-session hard sets on a lift capped at 3–6. | **Have** (`training_days`, 2–6) |
| **Number of target lifts** | Frequency is per-lift, so days × lifts is the real budget. Three target lifts at 3×/week each does not fit in 3 days at §6 rest lengths. | Missing (follows from 2.1) |
| **Lift identity** | §3/§11d: deadlift **1–2 heavy exposures/week**, and 3+ is "poorly tolerated by most"; bench tolerates 2–4 (up to 6). Per-lift frequency caps are a hard constraint, not a preference. | Missing |
| **Inter-session spacing** | §9: same lift at ≥85% needs 48–96 h; heavy DL→heavy squat ≥48 h, preferably 72. Constrains **day ordering**, which the current plan model expresses only as `WorkoutDay.order` with no calendar semantics. | Derivable from ordering; not expressed |

### 2.4 Periodization and phase

| Input | Why | Status |
|---|---|---|
| **Current phase + week within phase** | §4: accumulation 3–5 wk, transmutation 3–4 wk, realization 1–3 wk, deload 1 wk every 4–8. Intensity +2.5–5%/wk, volume −10–20%/wk *within* a mesocycle. Every one of these numbers is a function of "which week is it." | **Missing entirely** |
| **Training age** | §4 model table: novice = session-to-session linear; late novice = WUP; intermediate = DUP or 3–5 wk waves; advanced = block. The *model itself* is selected by training age. | Partial |
| **Target date (optional)** | §4 taper: 8–14 days, volume-load −40–60%, intensity held 85–95%, last ≥90% session 5–10 days out. A taper is only computable against a date. §12: intermediates max every 12–20 weeks. | **Missing** |
| **Last max-test date** | §12: novices every 8–12 wk, intermediates 12–20, advanced 2–4×/yr. Also the "never max when" gates. | **Missing** |

### 2.5 Intensity regulation (RIR/RPE)

| Input | Why | Status |
|---|---|---|
| **Per-set RIR** | §8: main-lift RIR 1–3; the daily autoregulation rule is "top set ≥1 RPE point easier than target → +2.5–5%; ≥1 point harder → −2.5–7.5%." Without per-set RIR this rule cannot be evaluated. | **Missing** (`SetLog` has weight/reps only) |
| **RIR reliability estimate** | §8: **novices systematically underestimate remaining reps by 2–4**, and RPE autoregulation is only reliable for intermediate+ at ≥80%. The report's explicit conclusion: **"percentage-based prescription is safer for the first 6–12 months."** So the system must know whether to *trust* a user's RIR. | Missing — derivable from training age + weeks of RIR-logging history |
| **Age** | §11c: >40–50 → RIR +1 (2–4 rather than 1–3) on main lifts. | **Have** |
| **Sex** | §11a: prefer RPE/RIR over male-derived %1RM tables for women; rest may be 15–25% shorter at submaximal loads but **unchanged at ≥90%**. | **Have** |

### 2.6 Rest

Fully computable with **no new user data** from: load bracket (≥90% → 180–420 s; 80–90% → 180–300 s; 70–80% → 120–240 s; accessories 90–180 s; isolation 60–120 s), plus age (+30–60 s if >40–50) and the "3–5 min between exercises if the next is a competition lift" rule. The single missing input is the **load bracket of the exercise**, which follows from 2.1. This is the cheapest high-value fix in the whole document: today a hardcoded `90` overrides a computation requiring nothing the app doesn't already have.

### 2.7 Recovery, deload, and safety gating

| Input | Why | Status |
|---|---|---|
| **Per-lift fatigue cost** | §11d heuristic: DL 1.0, squat 0.7, bench 0.4, OHP 0.3, accessory 0.1–0.2 per hard set at 85%. Explicitly a coaching heuristic, not a measured constant — should be labelled as such wherever surfaced. | Missing |
| **Reactive deload markers** | §9: any 2 of — velocity −10% at fixed load over 2 sessions; RPE +1.5 at fixed load; sleep down 3+ nights; joint pain ≥4/10; BW −1%/wk unintended; motivation loss 2+ sessions. | Mostly missing (RPE/pain/sleep/BW all uncaptured) |
| **Sleep** | §10: chronic ≤5–6 h → 5–10% multi-joint force loss; **≥7 h × 3 nights before a max attempt**; skill-dependence gradient means squat/bench lose 2–6% on poor sleep. Relevant as a **gate on test days**, not just a volume cap. | Missing |
| **Pain 0–10** | §13: train ≤3–4/10, back to baseline in 24 h; reduce load 20–40% before removing the pattern. Also a "never max" gate at ≥4/10. | Missing |
| **Bodyweight trend** | §10: >1% BW/wk loss costs 1RM (−2–8% over a cut); "never max" if BW dropped >2% in the prior week. | Captured once at onboarding only |

### 2.8 Explicitly out of scope

**Velocity-based training (§8).** The report gives full MVT and load–velocity numbers, but VBT requires hardware the app cannot assume, and §8's own caveat (±0.03–0.08 m/s device/biological noise, needs rolling 3+ session trends) means a phone-camera approximation would be worse than useless. Recommend: **do not build VBT**, but leave the `StrengthEstimate` model's `source` field open so an external velocity-derived e1RM could be ingested later. Where the adaptation rules below would use velocity, substitute the RPE-at-fixed-load equivalent, which the report treats as the same class of signal.

**Nutrition/supplements (§10).** Same scope boundary as `coach-integration-strategy.md` §7.7. Two exceptions worth surfacing as *content*, not as a feature: creatine (§10, **High** confidence, +5–15% strength outcomes) and the pre-max sleep rule are cheap, high-value coaching notes for this goal specifically.

---

## 3. Onboarding vs. progressive collection

### 3.1 The 1RM question, stated honestly

This is the central design decision, and the research settles part of it and not all of it.

**What the findings say against asking for a true 1RM at onboarding:**
- §12: a true 1RM test costs **3–7 days of reduced training capacity**, carries elevated injury risk at RPE 10, and has **±2–5% test-retest variability** — worse than the ±3–6% of an e1RM from a top set that costs nothing.
- §12: "never max when sleep <6 h for 2+ nights; a heavy session within 72 h; joint pain ≥4/10; BW drop >2%." At onboarding the app knows none of these.
- §12: to do it properly requires **7–14 days of taper** first. A max attempted on day zero of using the app is by definition untapered and under-warmed-up, so it is not just risky, it is *inaccurate* — it will read low and permanently anchor the user's loads too light.
- §8: novices underestimate remaining reps by 2–4, so a novice's self-assessed "max" is unreliable in both directions.
- §5: a novice is gaining **+2–5%/week**. Any number captured at onboarding is stale within a fortnight regardless of how it was obtained.

**Conclusion:** the app must **never** ask an untested user to attempt a true 1RM, and should not ask "what is your 1RM?" as a required field. But it should absolutely ask the much easier, much safer question the report itself endorses as the tracking primitive: **"what's the heaviest set you've done recently — weight × reps?"** Everyone who trains knows what they did last Tuesday; almost nobody knows their true 1RM.

**The three-tier estimation ladder** (this is the answer to "how should the app estimate a safe starting load without a max test?"):

| Tier | Source | Accuracy | When used |
|---|---|---|---|
| **T3 — Anchor conversion** | User-supplied recent set (weight × reps, ≤10 reps), converted via **Brzycki for 1–6 reps, Epley for 6–10** (§12), with a **−5% conservatism haircut** on the first block | ±5% formula error, biased low deliberately | If the user answers the working-weights screen |
| **T2 — Calibration session** | Session 1–2: ramp to a **top set of 3–5 reps at RPE 8 (RIR 2)** on each target lift, e1RM from that set | ±3–6% (§12: this is the report's recommended every-session signal) | Always; supersedes T3 within 1–2 sessions |
| **T1 — Bodyweight seed** | Bodyweight multiplier by lift × sex × training age, **deliberately biased low** | Poor, but bounded and safe | If the screen is skipped, for the pre-signup preview only |

Two honesty notes on T1: **the research report does not supply bodyweight-multiplier norms** — it gives progression rates and rep-max equivalents, not population strength standards. Any multiplier table the product ships is therefore a *product heuristic*, not a research-derived constant, and must be labelled as such internally and biased low so the first session is under-loaded rather than over-loaded. Errors here are asymmetric: an under-loaded first session costs one easy workout and gets corrected the same day by T2; an over-loaded first session costs a failed rep at a heavy load in an unsupervised setting.

Second: the T2 calibration set is itself **the RPE-8 top set the research recommends doing every session anyway** (§12). It is not an extra test bolted onto training — it is the prescribed first working set, framed to the user as "your first heavy set tells us your numbers." That framing is what makes progressive collection free here.

### 3.2 Decision rule

A data point belongs in pre-plan onboarding if the *first plan is not generatable or is visibly wrong without it*. Everything else defaults and gets corrected from logs.

**Must ask, strength-specific:** which lifts the user wants to get strong at. Without it there is no target for the 60–80% direct-volume allocation (§7) and the plan collapses back into a generic split — this is the single question that most determines whether the plan looks strength-specific.

**Should ask, skippable:** current working weights for those lifts (T3 above).

**Should ask, cheap:** has the user ever tested a max, and when (gates whether the app can trust a stated number, and seeds the §12 retest clock).

**Default and refine from logs:** e1RM per lift (T2, within 1–2 sessions), RIR calibration confidence (§8: assume novice error ±2–4, tighten over 6–12 months), per-lift fatigue tolerance, actual session duration vs stated, rep-max relationship individualization (§12: comparing a formula estimate to one real top set reduces error to ±2–4% *for that person on that lift*), plate increments available, sleep, bodyweight trend, pain.

### 3.3 Proposed onboarding additions — 3 conditional screens

These are shown **only when `goal == increase_strength`**, immediately after the goal screen's branch point. The other four goals see the shared flow unchanged. Implementation-wise this means the flat `switch (_step)` with `const _stepCount = 12` in `onboarding_flow_screen.dart` needs to become a **computed step list** (a `List<OnboardingStep>` built from the draft's goal), which is a prerequisite refactor for any conditional branching at all and is worth doing once for all five goals.

| # | Screen | Type | Rationale (research tie) | Parameters unlocked |
|---|---|---|---|---|
| **S1** | **"Which lifts do you want to get strong at?"** — multi-select from squat / bench / deadlift / overhead press / weighted pull-up / barbell row / other, **capped at 3** (4 if training_days ≥ 5) | multi-choice, required | §1: specificity effects are 2–3×; §7: comp lift takes 60–80% of direct volume in strength/peak. §3: per-lift frequency is 2–4 sessions/wk, so 3 lifts × 3 sessions is already 9 heavy exposures — a cap is a real programming constraint, not UI tidiness. Replaces `priority_muscles` for this goal (muscles are the hypertrophy unit of analysis; lifts are the strength unit). | target-lift set, direct/accessory allocation, per-lift frequency and set tables (§11d), which patterns get the ≥90% exposure |
| **S2** | **"Roughly what can you lift right now?"** — per selected lift: `weight × reps` for a recent hard set, with **"I don't know" per lift** and a **skip-all** affordance. Helper text: *"A set you've actually done — not a max attempt. Don't test anything today."* | numeric pairs, **skippable** | §12: e1RM from 2–10 reps is ±5%; ≤5 reps is ±3–6%. This is the only question that converts every %1RM in §1 into a kg number in the *pre-signup preview plan* — the plan doing the conversion work. Explicitly **not** a 1RM request, for the §12 safety reasons above. | `e1rm_kg` per lift → `target_load_kg` per set, load increments, plate rounding, realistic progression-rate expectations (§5) |
| **S3** | **"Have you ever tested a true 1-rep max?"** — Never / Yes, within 3 months / Yes, longer ago; plus optional "do you have a meet or test date?" (date picker) | 1–2 taps | §12: retest cadence is 8–12 wk (novice) / 12–20 wk (intermediate) / 2–4×/yr (advanced) — the app needs a clock start. §8: a lifter who has never trained at ≥90% should get **percentage-based** prescription, not RPE-based, for the first 6–12 months. §4: a taper (8–14 d, −40–60% volume-load, the best-evidenced part of periodization, worth +2–6%) is only computable against a date. | RIR-trust flag, first-block intensity ceiling, retest scheduling, taper planning, whether a peak phase exists in the first mesocycle at all |

**Count: 3 conditional screens** (2 required, 1 of which is 2 taps; 1 skippable). Net for a strength user, layered on the `coach-integration-strategy.md` 11-screen shared flow: **13 screens** (S1 replaces the shared "priority muscles" screen for this goal, so the true delta is +2).

**Shared-flow changes this goal also depends on** (already proposed in the hypertrophy strategy doc, listed here so the dependency is explicit, not duplicated): `training_age_months` instead of the 3-way label; numeric `session_minutes`; structured limitations; the plan-summary confirmation screen. Strength additionally wants **plate increments available** (2.5 / 1.25 / 0.5 kg micro-plates), but that is a low-value question — better inferred from equipment defaults and corrected if the user reports they can't load a prescribed weight.

### 3.4 Progressive collection plan

| Data point | Mechanism | When | Feeds |
|---|---|---|---|
| **e1RM per lift (T2)** | Session 1–2 **calibration top set**: prescribed warm-up ramp (§11c: 5–7 ramp sets for >40s, fewer for young) to a top set of 3–5 reps at RIR 2, with an explicit "stop when it gets hard, don't grind" instruction | First 1–2 sessions per lift | Every `target_load_kg`; supersedes T1/T3 |
| **e1RM, continuously** | Passive, from every working set at ≤5 reps and RIR ≤3 (§12: use reps ≤5 for strength tracking; error grows to ±10–20% above 10 reps — **so sets above 8 reps should not update the strength e1RM at all**) | Every session | Load progression, phase transitions, progress display |
| **Per-set RIR** | 0–4+ chip strip when logging, defaulting to the prescribed target | From session 3 | The §8 daily autoregulation rule (±2.5–7.5% load); hard-set counting; deload markers |
| **Individual formula calibration** | When a true top-set-of-1 or a tested max exists, compare to the formula estimate and store a per-user, per-lift correction factor | On any single at RIR ≤1 | §12: reduces e1RM error from ±5% to **±2–4%** for that person on that lift; recalibrate after >10% change in 1RM or BW |
| **Rep PR at fixed load** | Scheduled AMRAP-to-RIR-1 at ~80% of last known e1RM | **Every 3–4 weeks per lift** (§12 — more often and the AMRAP fatigue itself interferes) | Independent e1RM check; each extra rep ≈ +2.5–3.5% e1RM |
| **RPE at fixed load** | Derived: compare RIR on a repeated load across exposures | Continuous | §9 deload trigger (RPE +1.5 at fixed load); substitutes for the velocity signal the app can't measure |
| **Warm-up ramp actuals** | `SetLog.is_warmup` | Every session | Excludes warm-ups from hard-set counts and from e1RM |
| **Session duration actual** | Passive, `finished_at − started_at` | Every session | Detects the "3–5 min rest doesn't fit in 45 min" failure; either shrink the plan or tell the user the truth |
| **Pain 0–10 per exercise** | Optional tap | Ad hoc | §13 substitution ladder; "never max" gate |
| **Sleep (nights before a planned heavy/test day)** | Prompted **only** around ≥90% sessions and test days, not daily | ~Weekly | §10: ≥7 h × 3 nights pre-max; skill-gradient penalty of 2–6% on squat/bench |
| **Bodyweight** | Weekly check-in | Weekly | §10: BM^0.67 scaling, deficit strength cost, "never max if BW −2% this week" |

**Design principle:** the strength user's progressive collection is unusually cheap because **the calibration set is a training set**. Nothing in the ladder above asks the user to do work they weren't already prescribed.

---

## 4. From qualitative labels to real numbers

### 4.1 Where this lives: one prescription layer, two strategies

`coach-integration-strategy.md` §4.1 proposes `compute_prescription(profile, training_state) -> Prescription`. **This proposal does not create a parallel system.** It proposes that `compute_prescription` dispatch on `profile.goal` to a strategy object, with the shared machinery factored out:

```
compute_prescription(profile, training_state)
  ├─ shared: training-age resolution, age/sex modifiers, equipment→increment rounding,
  │          session time budget arithmetic, limitation→substitution ladder,
  │          e1RM lookup + confidence, plate rounding, validator contract
  ├─ HypertrophyStrategy   (goal=build_muscle; volume-per-muscle centric)
  ├─ StrengthStrategy      (goal=increase_strength; load/specificity/phase centric)
  └─ ... (lose_fat, improve_fitness, build_habits)
```

**Share vs. diverge, explicitly:**

| Component | Shared | Strength-specific |
|---|---|---|
| `StrengthEstimate` / e1RM model and maintenance | **Shared** — hypertrophy needs loads too | Strength additionally requires per-lift granularity, ≤5-rep-only updates, and individual formula calibration |
| `SetLog.rir`, `is_warmup` | **Shared** | Interpretation diverges: hypertrophy wants RIR→0; strength wants RIR 1–3 and treats RIR 0 on compounds as a cost (§8) |
| `PersonalRecord` + PR detection | **Shared** — fix the weight-only comparison for everyone | Strength surfaces **e1RM trend** as the primary metric; hypertrophy surfaces volume/rep PRs |
| Equipment → plate increment rounding | **Shared** | Strength needs micro-plates (§5: 0.5–1.25 kg) surfaced as a real recommendation |
| Limitation → substitution ladder | **Shared** structure | Strength substitutes **within the pattern using §7 carryover coefficients** (≥0.5 carryover required); hypertrophy can freely swap to any exercise hitting the same muscle |
| Session time budget arithmetic | **Shared** formula | Different constants: strength rest is 180–420 s, so the same 60 min buys far fewer sets |
| Adaptation engine plumbing (`AdaptationHistory`, hooks on finish/feedback) | **Shared** | New rule set (§6 below), new `Decision` values (phase transition, deload, test scheduling) |
| **Volume model** | — | **Diverges fundamentally.** Hypertrophy: sets per *muscle*, accruing to 20–30+. Strength: sets per *lift*, flattening at 15–20 (§2) |
| **Periodization state** | — | **Strength-only.** H§ finds model choice matters little; §4 here finds periodization worth ES 0.43 and the taper worth +2–6% |
| **Exercise selection rule** | — | **Diverges.** Hypertrophy: variety is fine, equipment-agnostic. Strength: §7 carryover tiers with phase-dependent variation budgets (40–60% → 20–35% → 0–15%) and a "don't rotate main-lift variations more often than every 3 weeks" hard rule |
| **Rest** | Same bracket table shape | Strength floors at 180 s for main work; hypertrophy floors at 120 s for compounds, 60 s isolation |

### 4.2 Label → number mapping tables

**`training_age_months` → the strength prescription core** (§1, §2, §3, §4, §5, §8, §9):

| Training age | Model (§4) | Main-lift load | Reps | Direct sets/wk/lift | Freq/lift | RIR | Rest ≥85% | Increment/step | Deload | Retest |
|---|---|---|---|---|---|---|---|---|---|---|
| 0–9 mo | Linear, session-to-session | 75–85% | 3–5 | 6–10 | 2–3 | 2–4 | 3–5 min | LB +2.5–5 kg/session, UB +1–2.5 kg/session; reset −10% after 2–3 failed sessions | rarely / 8–16 wk | 8–12 wk |
| 9–18 mo | Weekly undulating | 78–90% (H 85–90 / M 78–82 / L 68–72) | 3–8 by day | 8–12 | 2–3 | 2–3 | 3–5 min | weekly, not per session | 6–8 wk | 8–12 wk |
| 18–36 mo | DUP / 3–5 wk waves | 80–92% | 2–5 | 9–15 | 2–4 | 1–3 | 3–5 min | ~0.5–1% of 1RM/wk within a block; wave +2.5–5% | 4–8 wk | 12–20 wk |
| 36–60 mo | Block | 85–95% | 1–5 | 12–20 | 3–5 (DL 1–2) | 1–3 | 3–7 min | ≤5%/month cap (§9 tendon) | 4–6 wk | 12–20 wk |
| 60+ mo | Block | 85–95%+ | 1–5 | 12–20 (10–18 in peaking) | 3–5 | 1–3 | 3–7 min | micro-plates 0.5–1.25 kg | 4–6 wk | 2–4×/yr |

**Phase → the within-block numbers** (§4), applied as a multiplier layer on the row above:

| Phase | Weeks | Load | Sets × reps | RIR | Sets/wk/lift | Accessory share | Variation share (§7) |
|---|---|---|---|---|---|---|---|
| Accumulation | 3–5 | 65–80% | 4–6 × 5–10 | 2–4 | 12–20 | 40–55% | 40–60%, pool 6–10, rotate every 3–6 wk |
| Transmutation (strength) | 3–4 | 80–90% | 4–6 × 3–5 | 1–3 | 10–15 | 25–35% | 20–35%, pool 4–6 |
| Realization (peak) | 1–3 | 87–95%+ | 3–5 × 1–3 | 0.5–2 | 5–9 | ≤15% | 0–15%, comp lift only |
| Deload | 1 | 85–95% *of normal top-set load* | −40–60% sets | 4+ | ~⅓ normal | minimal | none |
| Taper (pre-test) | 8–14 d | top sets **held at 85–95%** | volume-load −40–60% | — | — | — | none; last ≥90% session 5–10 d out; last 48–72 h ≤70% and ≤20–30% volume |

Within a mesocycle: **top-set load +2.5–5%/week, volume −10–20%/week** (§4).

**Age and sex modifiers** (§11a, §11c) — applied last, as deltas, not as separate tables:

| Condition | Modifier |
|---|---|
| Age > 40–50 | Rest +30–60 s (→ 4–6 min at ≥85%); RIR +1 (main lifts 2–4); ≥90% exposures 1×/wk or every 10–14 d; deload every 3–5 wk; load-increase cap ≤2.5–5%/month; warm-up 10–15 min / 5–7 ramp sets; 72 h between same-lift ≥85% sessions |
| Age 65+, untrained | 70–85% 1RM, 2–3 × 6–10, 2–3×/wk; **no heavy singles** until experienced |
| Female | Prefer **RIR-anchored** load selection over male-derived %1RM→rep tables (expect +1–5 reps at 60–80%); rest may be 15–25% shorter at submaximal loads but **unchanged at ≥90%**; **no change** to load prescription, rep ranges, exercise selection, or periodization model. Do **not** implement menstrual-phase periodization (§11a: not supported; symptom-driven volume reduction of 20–40% on symptomatic days is the defensible version) |

**Per-lift caps** (§11d) — a hard post-filter on whatever the tables above produce:

| Lift | Freq cap | Heavy sets/wk | Rest | Special |
|---|---|---|---|---|
| Back squat | 2–4 | 10–18 | 3–5 min | 1–2 sessions at ≥85% |
| Bench | 2–4 (up to 6) | 12–20 | 3–5 min | Lowest fatigue/set |
| Deadlift | **1–2 heavy** (+1 variation) | **5–12** | 3–6 min | **Avoid >2 sets of 5+ reps at ≥85%**; prefer singles/doubles |
| OHP | 2–3 | 8–15 | 2–4 min | Fewer sets at ≥90%; 0.5–1.25 kg increments |
| Weighted pull-up / row | 2–3 | 8–16 | 2–3 min | 1–2.5 kg steps |

**`equipment` → increment rounding:** barbell present → round to 2.5 kg (5 kg jumps possible), micro-plates recommended for upper body; dumbbells only → round to the available dumbbell ladder, which for many home setups is 2–2.5 kg apart and therefore a **5–10% jump on a 25 kg press** — worth flagging to the user, since §9 caps monthly increases at 5–10%.

**`injuries` → §13 ladder, strength-flavoured:** reduce load 20–40% (not remove) → restrict ROM to pain-free → substitute **within the pattern preserving ≥0.5 carryover** (low-bar → high-bar/SSB/box; flat bench → floor press/football bar/±5–10 cm grip; conventional DL → trap bar/block pull/sumo) → isometrics 4–5 × 30–45 s at 60–85% MVC as a bridge → unilateral work on the healthy side (cross-education, ~7–15% contralateral gain). Return-to-load ≤10%/week; **no true max until ≥4–6 weeks symptom-free at ≥85%.**

### 4.3 Proof 1 — the same user, two goals

Inputs: M, 28, 84 kg, trained 26 months, 4 days/week, 60 min, full commercial gym, no limitations, bench e1RM 105 kg.

| | `build_muscle` | `increase_strength` |
|---|---|---|
| Organizing unit | Chest: 16 sets/week | Bench: 12 sets/week direct + 4 close-variation |
| Bench prescription | 4 × 8–10 @ **75 kg** (~71%), RIR 1 | Wk1 5 × 3 @ **89 kg** (85%), RIR 2; wk2 5 × 3 @ **92 kg**; wk3 4 × 2 @ **95 kg** |
| Rest on bench | 150 s | **240 s** |
| Weekly bench frequency | 2 (as part of chest volume) | 3 (heavy / medium / variation) |
| Second-lift work | Incline DB press, cable flye, dips — chosen for stimulus | Close-grip bench (0.75–0.90 carryover), spoto press if the sticking point is off the chest |
| ≥90% exposure | Not a concept | ≥1 set/week during strength phases |
| Accessories | 40–55% of volume, RIR 0–2 | 25–35% of volume, RIR 1–3, dosed for weak points |
| Progression trigger | Top of rep range on all sets → +2.5 kg | e1RM trend + RIR delta on the top set → +2.5% |
| Structure over 8 weeks | Volume ramp within tier, deload when markers trip | Accumulation 4 wk → strength 3 wk → deload 1 wk, phase state tracked |
| Progress metric shown | Volume, rep PRs | **e1RM trend per lift**, ±5% noise band drawn on the chart |

These are two different programs. Today they are one program with a different word in the prompt.

### 4.4 Proof 2 — two strength users, same labels

Both answer: goal `increase_strength`, 4 days/week, 60 min, barbell gym, target lifts squat + bench + deadlift.

| | User A | User B |
|---|---|---|
| Inputs | M, 24, 80 kg, trained 30 mo, squat e1RM 150 / bench 105 / DL 180, has maxed before | F, 47, 62 kg, trained 5 mo, no known loads (skipped S2), never maxed |
| Model (§4) | DUP / 3-week waves | Linear, session-to-session |
| Squat, week 1 | 5 × 3 @ **127.5 kg** (85%), RIR 2 | 3 × 5 @ **calibration-derived**, seeded low; +2.5 kg next session |
| Load basis | %1RM off a calibrated e1RM | **RIR-anchored** (§11a: male-derived %-tables under-load women), percentage-capped (§8: %-based is safer <6–12 mo) |
| Rest, squat | 240 s | 240 s + 45 s (age >40) = **285 s** |
| RIR target | 1–3 | **2–4** (novice + age >40, both push RIR up) |
| Deadlift dose | 8 heavy sets/wk, 1 heavy + 1 variation exposure | 6 sets/wk, 1 exposure, 3×5 |
| ≥90% exposure | 1–2×/wk | **None in the first block** — no max history, so no ≥90% work until the ladder has calibrated |
| Deload cadence | Every 5 weeks + reactive | Every 4–5 weeks (age >40 pulls it in from "rarely") |
| Test plan | Rep PR every 3 wk; true max at wk 14 with an 8–14 d taper | Rep PR every 4 wk; recalibrate at wk 8–12, **no true max offered** |
| Expected gain framing | +0.5–1%/month; unambiguous change in 10–14 wk | +1–2%/week early; noticeable in 1–2 wk, unambiguous in 3–4 wk |
| Progress copy | "e1RM ±5% — trust the trend, not one session" | "You'll feel warm-ups get lighter in 1–3 weeks" |

---

## 5. Periodization state as a first-class concept

### 5.1 Should it exist? Yes — with a caveat about what it's for

§4 grades "periodized beats non-periodized" as **High** (ES 0.43, holds when volume-equated), and grades **which model** as Low. That combination is the design brief: the app should **track and vary phase systematically**, but should not claim a specific model is optimal, and should choose the model by training age (where the coach-consensus mapping in §4 is the best available guidance) rather than by an evidence claim it can't support.

This is the sharpest divergence from the hypertrophy goal, where the equivalent finding was that model choice matters little and a simple volume ramp suffices.

### 5.2 Proposed state

Extend (do **not** fork) the `TrainingBlock` model already proposed in `coach-integration-strategy.md` §6.1:

```
TrainingBlock(user, plan, started_at, week_index, phase, deload_active)
  + phase_length_weeks
  + block_goal            # e.g. "squat +5 kg", derived from §5 progression rates
  + planned_test_date     # nullable; drives the taper
  + last_test_at          # per-lift, or on StrengthEstimate
  + model                 # linear | wup | dup | block — set from training age
  + intensity_anchor      # top-set %1RM for week 1, ramps +2.5–5%/wk
```

`phase ∈ {accumulation, transmutation, realization, deload, maintenance}` — hypertrophy users use only `{accumulation, deload}`, so the field is shared and the strength strategy simply uses more of its range.

### 5.3 The phase state machine

Transitions are **deterministic where the research gives a duration, reactive where it gives a trigger**:

| From | To | Trigger |
|---|---|---|
| (start) | accumulation | New block. Length 3–5 wk (§4), shorter end for novices |
| accumulation | transmutation | `week_index` reaches phase length **AND** no active deload markers |
| transmutation | realization | Phase length reached (3–4 wk) **AND** a test/peak is planned within 1–3 wk; otherwise → deload → new accumulation at a higher `intensity_anchor` |
| any | deload | Scheduled cadence by training age/age (§9) **OR** reactive: any 2 of the §9 markers |
| realization | (test) → deload | Taper complete; then a mandatory deload |
| any | maintenance | Adherence collapse, injury, or user-declared travel/deficit: §2 — strength holds for 4–8 wk on ~⅓ volume **if intensity stays ≥80%** |

**Novices get a simplified machine**: linear progression with reactive resets (§4: reset −10% after 2–3 consecutive failed sessions) and no realization phase at all until they have ≥1 calibrated max or 8–12 weeks of history. Imposing a block structure on a novice is unnecessary complexity — §11b notes 60–80% of first-year adaptation comes from load exposure alone and "program design sophistication contributes little."

### 5.4 How phase drives regeneration

Today `generate()` produces an unrelated plan each time. Proposed:

- **Weekly micro-regeneration within a phase should not call the AI at all.** Week-to-week change inside a block is arithmetic: top set +2.5–5%, volume −10–20%, same exercises (§7: don't rotate main-lift variations more often than every 3 weeks). A deterministic `advance_week(block)` producing the next week's loads is cheaper, faster, reproducible, and cannot hallucinate. **The AI is called at phase boundaries, not weekly.**
- **At a phase boundary**, the prompt states the *new* phase's numeric envelope and the previous phase's exercise list, and asks for selection changes only — narrowing the variation pool from 6–10 to 4–6 to comp-lift-only as the phase advances.
- **Taper** is fully deterministic from §4 (−40–60% volume-load, intensity held 85–95%, last ≥90% session 5–10 d out, last 48–72 h ≤70% and ≤20–30% volume). No AI involvement; this is a schedule.
- **`raw_ai_response` on `WorkoutPlan`** already stores the display-shape plan, so week-advanced variants can be persisted as new `WorkoutPlan` rows with `source='periodization'` rather than `'ai'` — the field exists and the distinction is worth keeping for auditability.

### 5.5 What to show the user

Phase state is one of the few pieces of internal machinery worth surfacing directly: "Week 2 of 4 — Strength phase. Loads go up ~3% this week, volume comes down." It is legible, it explains why this week feels different, and it is a strong anti-"generic" signal. It also sets the §12 expectation calendar honestly (novice: unambiguous change in 3–4 weeks; intermediate: 10–14 weeks) — the report is explicit that an advanced lifter cannot detect real progress from any single test on a short timescale, and telling them that up front is better coaching than implying otherwise.

---

## 6. Adaptation engine for strength

### 6.1 Relationship to the existing rules

`evaluate_reps` and `evaluate_feedback` should be **kept and scoped**, not deleted. Both are reasonable-ish hypertrophy heuristics (the hypertrophy strategy doc proposes its own fixes to them). The proposal is that `engine.py` gains a goal dispatch, and the strength rules below run *instead of* `evaluate_reps` for strength users, while both goals share the `AdaptationHistory` write path and the "fold recent decisions into the next generation" loop.

Why `evaluate_reps` cannot simply be tuned for strength:

- It has **no load term**. §8's central rule is about *load adjustment relative to a target RPE at a known %1RM*. A rule that never reads `SetLog.weight` cannot express it.
- It fires on **one session**. §9 requires 2 consecutive exposures / 2 markers before concluding fatigue. On a strength plan, one bad heavy day is noise.
- Its increase condition (`all sets > target_reps_max`) is nearly unreachable at ≥85% 1RM where the rep target is 1–3.
- It has **no phase awareness**, so it would fight the periodization state: a planned intensification week *should* produce higher RPEs and fewer reps, and the engine would read that as under-recovery and cut load.

`evaluate_feedback` has a separate defect that matters for both goals: it queries the last 3 `WorkoutFeedback` rows with **no time window**, so three "hard" sessions spread over months trigger a volume cut. For strength it is also the wrong instrument — a 4-level session difficulty cannot express "+1.5 RPE at a fixed load," which is the §9 marker.

### 6.2 Proposed strength rules

All thresholds are from §5, §8, §9, and §12.

| Rule | Trigger | Action | Ref |
|---|---|---|---|
| **S1 — Within-session load autoregulation** | Top set comes in **≥1 RPE point easier** than target | **+2.5–5%** for the next set | §8 |
| **S2 — Within-session load reduction** | Top set **≥1 RPE point harder** than target | **−2.5–7.5%** for the next set | §8 |
| **S3 — Back-off dosing** | After the top set at target RPE | Back-offs at **−5 to −12% load**, same reps, stop when RPE exceeds top set by >1 point; typically **2–5 sets** | §8 |
| **S4 — Novice linear progression** | Training age <9 mo, session completed at or above target reps | **+2.5–5 kg lower body / +1–2.5 kg upper**, next session | §4, §5 |
| **S5 — Novice reset** | **2–3 consecutive failed sessions** on the same lift | **−10%** and rebuild | §4 |
| **S6 — Intermediate+ weekly progression** | Week advances within a block | Top set **+2.5–5%**, volume **−10–20%**; equivalently **~0.5–1%/wk of 1RM** | §4, §5 |
| **S7 — e1RM stall** | No e1RM improvement across **3 consecutive exposures** at constant volume, and no active deload | Change **one** lever: add a session (if weekly sets ÷ 4–5 supports it), or add 2–3 sets/wk, or rotate the *variation* (never the comp lift), respecting the ≥3-week rotation floor | §3, §7 |
| **S8 — Reactive deload** | **Any 2 of**: RPE at a fixed load up **≥1.5** across 2 sessions; reps at a fixed load down; sleep down 3+ nights; joint pain ≥4/10 in a working set; unintended BW −1%/wk; motivation loss 2+ sessions | 1 week: **−40–60% sets, intensity held at 85–95% of normal top sets** (volume deload is the best-evidenced lever and best preserves strength). Use the intensity variant (−10–20% load, volume held) only when the complaint is joint/tendon | §9 |
| **S9 — Scheduled deload** | Cadence: novice rarely/8–16 wk; intermediate 4–8 wk; advanced 4–6 wk; **3–5 wk if >40, in a deficit, sleep-restricted, or >15 sets/wk/lift** | Same structure as S8 | §9, §11c |
| **S10 — Readiness-triggered day adjustment** | Poor readiness on the day | **Cut volume 30–50% first**; only cut intensity 5–10% if RPE at the opener load is clearly off | §8 |
| **S11 — Tendon governor** | Any progression step | Cap **weekly volume-load increase at 5–10%** and **monthly 1RM-target increase at ≤5%** (≤2.5–5% if >40). Tendon adapts 1.5–3× slower than muscle | §9, §11c |
| **S12 — Failure guard** | Set logged at RIR 0 on a compound at ≥85% | Flag, don't punish. §8: strength gains are flat across RIR 0–4 and failure may slightly *reduce* them; failure sets extend recovery by 24–48 h. Coaching note, plus S8 marker weighting | §8 |
| **S13 — Novice RIR discount** | Training age <6–12 mo, or <8 weeks of RIR logging | **Do not run S1/S2.** Novices underestimate remaining reps by 2–4. Use percentage-based prescription and objective rep/load signals only | §8 |
| **S14 — Phase transition** | Week index reaches phase length, no active deload markers | Advance phase per §5.3; write an `AdaptationHistory` row so the change is visible and folds into the next generation | §4 |
| **S15 — Test gating** | User or schedule requests a max | **Block** if: sleep <6 h for 2+ nights; a heavy session within 72 h; joint pain ≥4/10; BW down >2% this week; or <4–6 wk symptom-free after an injury. Require a taper first. Schedule for **late afternoon (4–8 PM)** unless the user habitually trains mornings (§10: 3–8% time-of-day difference) | §12, §10, §13 |
| **S16 — Rep-PR scheduling** | 3–4 weeks since the last AMRAP on a lift | Schedule an AMRAP-to-RIR-1 at ~80% of last known e1RM. Each extra rep ≈ +2.5–3.5% e1RM | §12 |
| **S17 — Maintenance mode** | Adherence collapse, travel, injury, or aggressive deficit | Drop to **~⅓ volume (3–6 sets/wk/lift) but hold intensity ≥80%** — strength holds 4–8+ weeks this way. Do **not** cut load. Explicitly the opposite of the usual "reduce intensity when life gets busy" instinct | §2 |

### 6.3 New `AdaptationHistory.Decision` values needed

Current values are load/volume up/down. Strength needs at minimum: `ADVANCE_PHASE`, `TRIGGER_DELOAD`, `SCHEDULE_TEST`, `BLOCK_TEST`, `RESET_LOAD`, `ENTER_MAINTENANCE`. These are additive enum values on a shared model, not a new model.

### 6.4 Confidence labelling

§4 grades block structure Low–Moderate, §7's carryover coefficients Low, §11d's fatigue-cost heuristic explicitly "a coaching heuristic, not a measured constant," and §9's deload structure Low–Moderate. Where the engine acts on these, `AdaptationHistory.reason` should say so plainly ("Standard practice, not strongly evidenced — we're doing this because…"). That is both more honest and better coaching UX than false certainty, and it matches the approach in the hypertrophy strategy doc.

---

## 7. Architecture implications

### 7.1 Data model

**`OnboardingProfile`** (strength-conditional fields, all nullable so other goals are unaffected):
- `target_lifts` (JSON list, ≤3–4)
- `has_tested_max` (choice: never / <3 mo / older)
- `target_test_date` (nullable date)
- plus the shared changes this depends on: `training_age_months`, numeric `session_minutes`, structured `limitations`

`priority_muscles` stays for the other goals; for `increase_strength` the UI shows `target_lifts` instead, and the prescription layer treats `target_lifts` as the allocation key. Existing rows: no backfill needed — strength users without `target_lifts` fall back to a squat/bench/deadlift default with low confidence, which is the right guess.

**New `StrengthEstimate`** (shared with hypertrophy, per the other doc's §6.1, extended here):
`(user, lift_key, exercise_name, e1rm_kg, confidence, source, formula, calibration_factor, updated_at, last_tested_at)`
`source ∈ {onboarding_anchor, calibration_set, logged_set, bodyweight_seed, true_max}`. `calibration_factor` implements §12's individual-correction (±5% → ±2–4%).

**`TrainingBlock`** extended per §5.2 above.

**`PlannedExercise`** — additions needed for strength specifically, on top of the shared ones (`target_rir_min/max`, `target_load_kg`, `exercise_class`):
- `load_pct_1rm` (the prescription; `target_load_kg` is its rounded realization, and keeping both makes the plan auditable and re-derivable if the e1RM updates)
- `lift_key` + `carryover_tier` (§7: 1.00 / 0.75–0.90 / 0.50–0.75 / 0.30–0.55 / 0.10–0.30) — the field that makes the direct-vs-accessory volume split computable
- `is_top_set` / `is_amrap` (so the calibration and rep-PR protocols are expressible in the plan itself rather than as out-of-band UI)

**`SetLog`** — `rir`, `is_warmup` (shared), plus `is_top_set` denormalized or derived.

**`PersonalRecord`** — add `e1rm_kg` (computed at write time) and change PR detection from `weight >` to `e1rm >`, with `PersonalRecord` gaining a `kind` field (`weight` / `rep_at_load` / `e1rm`) so the progress screen can show all three honestly. This fixes a real current defect for every goal, not just strength.

**`WorkoutFeedback`** — `session_rpe` (1–10) alongside `difficulty`, per the shared proposal; strength additionally wants a per-lift pain flag on `ExerciseLog`.

### 7.2 Prompt restructuring for this goal

Three sections, same shape as the hypertrophy proposal, different content:

1. **Hard numeric constraints (computed, non-negotiable).** Current phase and week index; per-lift weekly set targets and per-session caps; per-lift frequency caps (§11d); for each prescribed set: `load_pct_1rm`, `target_load_kg` (rounded to loadable plates), reps, RIR, rest seconds; the direct-vs-accessory volume split for this phase; required ≥90% exposures; minimum inter-session spacing for each lift; banned patterns and required substitutions.
2. **Exercise-selection guidance (delegated judgement).** Choose variations from the §7 carryover tiers to hit the phase's variation budget; pool size 6–10 / 4–6 / comp-only by phase; do not rotate a main-lift variation that has been in place <3 weeks; weak-point → variation mapping (§7) as a reference list; accessories 2–5 per session, 2–4 sets, 6–15 reps, RIR 1–3; order the session so the competition lift is first and fresh.
3. **Extended output schema.** `_SCHEMA_INSTRUCTIONS`, `_to_display_shape`, and the `PlannedExercise` write in `persist()` all need the new fields. Note that `_to_display_shape` and `persist` are the two places the `90` default lives — both need the computed rest value instead, and the model field default should become null-with-required rather than `90`.

Design intent, same as the hypertrophy doc: **the model chooses exercises and ordering; it never chooses the dose.** For strength this is even more important, because the dose *is* the intervention.

### 7.3 Post-generation validation

The strength validator additions, run against the computed `Prescription`:
- every main-lift set has a `load_pct_1rm` within the phase band
- weekly sets per lift within the training-age × phase band, and within the §11d per-lift cap (especially the deadlift's 5–12 and the "no more than 2 sets of 5+ reps at ≥85%" rule)
- rest ≥180 s on anything at ≥80% 1RM; reject the 90 s default outright
- direct-vs-accessory ratio matches the phase (65–80% direct in a strength block)
- at least one ≥90% exposure per week during strength/peak phases (§1's "minimum useful heavy exposure")
- same-lift heavy sessions ≥48 h apart in the day ordering
- session time budget: `Σ(sets × (rest + ~40 s))` fits `session_minutes` — the constraint most likely to be violated, because 3–5 min rest is expensive

On failure: one repair round-trip naming the specific violations, then a deterministic trim.

### 7.4 Flow-specific notes

- **Anonymous preview** still works: `compute_prescription` runs on an unsaved `OnboardingProfile` with empty training state, using T1/T3 e1RM seeding. The preview plan for a strength user should show **loads in kg with an explicit confidence caveat** ("estimated — your first heavy set will dial this in"). Showing a load, even a hedged one, is the strongest possible anti-generic signal at the exact moment the user is deciding whether to sign up.
- **`save-preview`** should re-validate server-side against a freshly computed prescription rather than trusting the round-tripped display-shape JSON. This is already a soft integrity gap and becomes a correctness issue once loads are involved.
- **`_format_adaptation_notes`** should pass resolved numeric deltas and current phase state, not free prose.
- **Frontend onboarding:** the flat `switch (_step)` with `const _stepCount = 12` cannot express conditional steps. It needs to become a computed step list before S1–S3 can exist. `OnboardingDraft` gains the three nullable fields. `app_router.dart` and the preview/save-preview providers are unaffected.
- **Frontend progress:** `progress_screen.dart` currently shows streaks, total volume, a volume bar chart, and a PR list rendered as `weight × reps`. For a strength user, **total volume is explicitly a poor proxy** (§12 ranks it "contextual only") and should be de-emphasized in favour of a **per-lift e1RM line chart with a ±5% noise band drawn on it** — the noise band is important, because §12's whole framing is that users misread noise as progress or regress. The PR list should show e1RM alongside weight × reps.
- **In-workout UI:** the set-logging screen needs a prescribed-load display, an RIR chip strip, and a distinct treatment for the top set / AMRAP set. This is the largest frontend change in the proposal.

### 7.5 Suggested sequencing

- **Phase 1 (no new user data):** goal dispatch in the prescription layer; `StrengthStrategy` emitting %1RM, sets, reps, rest, RIR; fix the 90 s rest default; e1RM-based PR detection; e1RM computed retroactively from existing `SetLog` history. Delivers a genuinely different strength plan using only fields that already exist.
- **Phase 2 (schema for loads):** `StrengthEstimate`, `PlannedExercise.target_load_kg` / `load_pct_1rm` / `lift_key` / `carryover_tier`, prompt restructure, strength validator.
- **Phase 3 (onboarding + capture):** conditional step list, S1–S3, `SetLog.rir` / `is_warmup`, calibration-session protocol, in-workout load + RIR UI.
- **Phase 4 (periodization + adaptation):** `TrainingBlock` extensions, phase machine, deterministic `advance_week`, strength rule set S1–S17, taper.
- **Phase 5 (progress surface):** per-lift e1RM chart with noise band, phase display, rep-PR scheduling, expectation-setting copy from §12's timeline table.

---

## 8. Tradeoffs, stated explicitly

**8.1 Asking for working weights at onboarding (S2).**
*For:* it is the only way the pre-signup preview plan shows real kg numbers, and that preview is doing the conversion work. Formula error from a 2–5 rep set is ±5% (§12) — good enough to prescribe from immediately.
*Against:* it is the hardest screen in the flow, it appears before signup, and a true beginner genuinely has no answer. There is also a real safety asymmetry: an inflated self-report (users over-report) produces an over-loaded first heavy session performed alone.
*Mitigations:* per-lift "I don't know"; explicit "don't test anything today" copy; a **−5% conservatism haircut** on all first-block loads derived from self-report; and the T2 calibration set superseding the anchor within 1–2 sessions regardless.
*Alternative:* defer S2 entirely to session 1. Costs a weaker preview (rep/%1RM shown, kg not), buys a cleaner funnel and removes the over-report risk. **Genuine A/B test, not a settled question** — but note the strength goal is the one where a load-free preview looks most obviously incomplete.

**8.2 Asking for a true 1RM at onboarding — rejected, and why that costs something.**
A true 1RM would improve first-plan load accuracy from ±5% (formula) or worse (seed) to ±2–5% (§12 test-retest). That is a real gain. It is nonetheless the wrong call: §12 says a proper max needs a 7–14 day taper (impossible on day zero), costs 3–7 days of capacity, and must be gated on sleep/pain/bodyweight conditions the app cannot yet evaluate. An untapered, unsupervised, un-warmed-up max on a first-time user is both the least accurate and the highest-risk way to obtain the number. The residual cost of refusing: the first 1–2 sessions run on estimates that may be 5–10% off, which S1/S2/S4 correct within a week. **That is a good trade, and it should be an explicit product principle, not an implicit one.**

**8.3 Deterministic weekly progression vs. calling the AI every week.**
*For determinism:* reproducible, instant, free, cannot hallucinate a 40% load jump, and is exactly what §4's "+2.5–5%/week, volume −10–20%/week" prescribes.
*Against:* users may perceive "the AI made me a new plan" as the product's value, and a fixed 4-week block can feel unresponsive.
*Mitigation:* adaptation rules still fire weekly and visibly modify next week's numbers, so the plan *does* respond — it just responds via arithmetic the app can defend rather than via a regenerated split. Consider surfacing the reasoning ("we held your bench at 92.5 kg because last week's top set came in at RPE 9.5").

**8.4 Phase tracking adds state that can get out of sync.**
If a user disappears for three weeks mid-block and returns, `week_index` is meaningless. Detraining begins at 2–3 weeks of inactivity, −5–10% 1RM at 3–4 weeks (§9). The state machine needs an explicit re-entry rule (roll back to accumulation, reduce loads by the detraining estimate, and re-calibrate) or phase state becomes a source of wrong prescriptions. This is real added complexity that the hypertrophy path does not carry.

**8.5 Capping target lifts at 3.**
*For:* §3's per-lift frequency and §2's per-lift volume tables mean 4+ lifts at meaningful frequency don't fit in ≤4 training days at §6 rest lengths. The cap is programming, not UI.
*Against:* users who want to get strong at five things will feel restricted, and "other" lifts may be their actual priority.
*Mitigation:* allow 4 when `training_days ≥ 5`; treat unselected lifts as accessories rather than removing them; explain the constraint in the plan-summary screen.

**8.6 Specificity vs. equipment and enjoyment.**
§7's carryover table implies a strength plan is repetitive by design — peaking phases are "competition lift, competition technique, competition equipment only." That is correct science and potentially poor retention, especially for a consumer app whose users did not sign up for a powerlifting meet. Consider: keep accessory selection varied (it's 25–35% of volume and is dosed for hypertrophy anyway, §2), and reserve strict specificity for users who set a test date in S3. A user with no test date arguably should live mostly in accumulation/transmutation and never see a true peak block.

**8.7 RIR capture for a population that can't estimate RIR.**
§8 is blunt: novices underestimate remaining reps by 2–4, and percentage-based prescription is safer for the first 6–12 months. So the app will be collecting RIR from exactly the users whose RIR is least trustworthy. S13 handles this by not acting on it, but it means the RIR tap costs friction before it delivers value. *Mitigation:* introduce it from session 3, default it to the prescribed target, and use the first 8 weeks of data to build the user's calibration rather than to drive load decisions — which also gives an honest reason to show them their calibration improving.

**8.8 What this proposal does not address.**
Velocity-based training (§8) — deliberately excluded, see §2.8. Nutrition, creatine, caffeine, and sleep (§10) beyond a test-day gate and a coaching note — same scope boundary as the hypertrophy doc. Injury/rehab (§13) is used only as a substitution ladder, not as a rehab feature; the report's own framing ("training-science principles, not medical advice") should be reflected in any UI that touches it. Competition-specific features (attempt selection, meet-day flow, weight classes) are out of scope; if the product ever wants them, §4's taper numbers are already the hard part and are covered here.
