# Coach Integration Strategy

**Status:** Proposal for review. No code, migrations, or config have been changed.
**Inputs:** `docs/research/hypertrophy-findings.md` (treated as ground truth for all numbers), plus the current state of `apps/onboarding`, `apps/workouts`, `apps/adaptation`, and `frontend/lib/features/onboarding/`.
**Scope:** what user data the science actually requires, when to collect it, and how to turn qualitative onboarding answers into numeric prescriptions the AI can be held to.

---

## 0. Recommendation summary (read this if nothing else)

The core finding: **the current pipeline cannot produce a numerically-grounded plan, and the bottleneck is not the AI — it's that no layer in the system ever computes a number.** `_build_prompt()` in `plan_generator.py` passes eleven qualitative labels to the model and asks it to "design a training split." Nothing in the request states a weekly set target, an RIR target, a %1RM, or a load in kg. The model therefore falls back on its own priors, which is exactly what produces the templated, generic output the product is trying to escape. Two users with identical labels and 40 kg of bodyweight difference get the same plan because nothing in the prompt differs.

The single highest-leverage change is **not** more onboarding questions. It is inserting a deterministic **prescription layer** between onboarding and the AI, which computes the numbers in Python from the research tables and hands the AI a filled-in constraint envelope. The AI's job narrows from "design a program" to "select and order exercises that satisfy these numbers." That change alone makes plans individualized, testable, and defensible — and it works with *most* of the data already collected.

Prioritized:

| # | Change | Effort | Payoff | Needs new user data? |
|---|---|---|---|---|
| 1 | **Deterministic prescription layer** (`compute_prescription(profile, state) -> Prescription`) computing weekly sets/muscle, frequency, per-session set budget, rep ranges, RIR, rest — from the research tables | M | Very high — this is what stops plans being templated | No (works on existing fields) |
| 2 | **Restructure the prompt** into: computed numeric constraints → exercise-selection guidance → extended JSON schema (`target_rir`, `target_load_kg`, `primary_muscle`, `secondary_muscles`) | S | Very high | No |
| 3 | **Post-generation validator** that recomputes weekly sets per muscle from the AI's response and rejects/repairs plans outside the computed band | S | High — closes the loop; the AI can no longer silently return a template | No |
| 4 | **Capture RIR per set** (`SetLog.rir`) and **`is_warmup`** | S | Very high — RIR is the #2 needle-mover and the input to all autoregulation | Yes (in-workout, 1 tap) |
| 5 | **Strength anchors → e1RM model** (3 optional onboarding lifts, then passively maintained from every logged set) | M | High — turns "beginner" into concrete kg | Yes (1 skippable screen) |
| 6 | **Training age in months** replacing the 3-way experience label | XS | High — every research table keys on training age, not on a 3-bucket label | Yes (same screen, better options) |
| 7 | **Rewrite adaptation thresholds** against §7.2 autoregulation markers; add deload, volume-ramp, pain, and adherence rules | M | High | Partly (needs #4) |
| 8 | **Weekly check-in** (bodyweight, sleep band, wellness composite) | S | Medium | Yes (~30 s, weekly) |
| 9 | **Prune dead onboarding questions** (`motivation`, `coach_personality`, `training_style`, `training_environment`) from the pre-plan flow | XS | Medium — buys back the friction budget for #5 and #6 | Reduces questions |

Net onboarding change under this proposal: **12 screens today → 11 screens**, with substantially more prescriptive information captured. The friction budget is funded by deleting questions that currently have no effect on the numbers.

---

## 1. Problem framing

### 1.1 What the code does today

`_build_prompt()` (`backend/apps/workouts/services/plan_generator.py`) interpolates the profile into prose and asks for a split. The full set of information reaching the model is:

goal, motivation, experience, age, gender, height, weight, training environment, equipment, training days, workout duration, training style, priority muscles, injuries, plus recent `AdaptationHistory` reasons.

Of these, only `training_days` and `equipment` are used as hard constraints ("exactly N training days," "only the available equipment"). Everything else is decoration the model may or may not act on. Weight and age are in the prompt but there is no instruction that connects them to anything — the model has no reason to prescribe differently for a 55 kg 19-year-old and a 105 kg 58-year-old.

The response schema is `{name, sets, reps_min, reps_max, rest_seconds, order}`. There is no field for RIR, no field for load, and no field for which muscle an exercise trains. That last omission is the important one: **the #1 variable in the research report — total hard sets per muscle per week — is not computable from anything the system stores.** `PlannedExercise` has an `exercise_name` string and nothing else, so neither the generator nor the adaptation engine can answer "how many sets is this user doing for chest this week."

`rest_seconds` defaults to `90` in two places (`_to_display_shape` and `persist`). Per §5 of the findings, 90 s is below the 120–300 s compound bracket, so any exercise the AI omits a rest value for silently gets an under-prescription on the biggest lifts.

Warm-up sets are indistinguishable from working sets in `SetLog`, so any future set-counting would over-count.

### 1.2 The two constraints in tension

- **Precision requires inputs.** You cannot compute 1.62 g/kg protein, +2.5% on a lift, or 14 sets/week for quads without bodyweight, a load estimate, and a training-age estimate.
- **Inputs cost completion.** The pre-signup preview flow (`/onboarding` → `/onboarding/generating` → `/onboarding/plan` → `/signup`) means every onboarding screen sits *before* the user has any account or investment. Drop-off here is drop-off at the top of the funnel. The 12-screen flow is already at the edge of tolerable.

The resolution is not a compromise on question count. It is recognising that **most numeric precision comes from computation, not from asking.** The research tables are lookups keyed on a handful of variables. Once those variables are known, the derived numbers — sets, frequency, rest, RIR, rep distribution, protein, progression rate — are all deterministic. The only genuinely *unaskable-cheaply* quantity is current strength, and even that can be seeded from bodyweight multipliers and then corrected within two sessions of logged data.

---

## 2. Data-needs analysis: what a numerically-grounded first plan requires

Each row states the parameter from the research report, the inputs needed to compute it, and whether the input exists today.

### 2.1 Volume — total hard sets per muscle per week

| Input | Why | Research reference | Status |
|---|---|---|---|
| **Training age (months)** | The entire volume tier table is keyed on it: 6–10 sets (0–6 mo), 10–16 (6–24 mo), 12–20 (2–5 yr), 15–25 (5+ yr). MEV likewise: ~3–4 / ~5–6 / ~6–8 / ~8–10. | §1.2, §10.2 | **Partial** — only a 3-way `experience` label; "intermediate" spans 6 months to 5 years, i.e. a 10-set spread |
| **Goal** | Sets/muscle/wk differ by goal: hypertrophy 10–20, strength 5–12 per pattern, general fitness 4–10, fat loss 6–15, endurance 8–15. | §10.4 | **Have** |
| **Age** | >60 caps weekly sets at 6–15 with a lower recovery ceiling. | §10.3 | **Have** |
| **Sex** | Possible +10–20% weekly sets for females *if recovery markers permit* — flagged Low confidence, so this should be an adaptation-time adjustment, not a first-plan assumption. | §10.1 | **Have** |
| **Priority muscles** | Specialization allocation: up to ~25–35 sets for lagging muscles in 4–8 wk blocks, with non-priority muscles dropped toward maintenance (2–6 sets) to pay for it. | §1.2, §1.1 | **Have** (but unbounded — should cap at 2) |
| **Muscle tagging on each exercise** | Required to *count* sets at all. Fractional counting: indirect involvement = 0.5 sets. | §1.4 | **Missing** — the critical gap |
| **Hard-set definition** | Only sets at ≤4 RIR count. Warm-ups must be excluded. | §1.4 | **Missing** — no RIR field, no warm-up flag |

### 2.2 Frequency and split

| Input | Why | Reference | Status |
|---|---|---|---|
| **Training days/week** | Determines the split template: 3 d = full body, 4 d = upper/lower ×2, 5 d = U/L/PPL, 6 d = PPL ×2. | §3 | **Have** (2–6; note 2 is below the 3–6 evidence range — see §7.3 tradeoffs) |
| **Computed weekly sets** | Frequency follows volume, not the reverse: ≤10 sets → 1–2 sessions, 11–20 → 2–3, 21–30 → 3–4. | §3 | Derived |
| **Per-session ceiling** | ~6–10 hard sets per muscle per session; sharp diminishing returns beyond. Caps what can be crammed into few days. | §3 | Derived |
| **≥48 h spacing** for heavy compound work on the same muscle | Constrains day ordering, not just day count. | §3, §7.1 | Derivable from day order; not currently expressed |

### 2.3 Session duration → set budget

| Input | Why | Reference | Status |
|---|---|---|---|
| **Session minutes (numeric)** | Working time 45–90 min; beyond ~90 min set quality falls. The budget is real arithmetic: `sets ≈ (minutes − warmup) × 60 / (rest_s + ~40 s execution)`. At 60 min with 8 min warm-up: ~16 compound-paced sets or ~25 isolation-paced sets. This is the constraint that decides whether the computed weekly volume is even *achievable*. | §3, §6.1 | **Partial** — stored as a `CharField` choice including the string `'90+'`, which is not arithmetic-usable |
| **Warm-up volume** | 2–4 ramp sets per compound for >50; 1–2 for young. Consumes budget. | §10.3, §11.4 | Missing |

Without numeric session minutes, the generator cannot detect the common failure case: a user asking for 6 sets/muscle across 5 muscles in 30 minutes. Today the AI is asked to "fit within the workout duration" and simply guesses.

### 2.4 Intensity — load, reps, RIR

| Input | Why | Reference | Status |
|---|---|---|---|
| **Estimated 1RM (or a working load) per movement pattern** | The only way to convert "65–80% 1RM" into a number the user can act on. Without it, load is left entirely to the user and the app is a rep-counter, not a coach. | §2.1 | **Missing entirely** |
| **Bodyweight** | Fallback seeding of e1RM by bodyweight multiplier when no anchor exists; also drives protein, gain/loss rate targets. | §9.1, §9.3 | **Have** |
| **Training age** | RIR targets: 2–4 (novice), 1–3 (intermediate), 0–3 (advanced). Also RIR *reliability*: novice estimation error is ±1–3 reps, improving to ±1 after 8–12 weeks of anchored practice. | §2.2, §10.2 | Partial |
| **Sex** | A given %1RM maps to different reps: 80% 1RM ≈ 8–10 reps for many women vs 6–8 for many men. So a rep-range prescription at a fixed %1RM is sex-dependent. | §10.1 | **Have** |
| **Age** | >60: effective range 60–85% 1RM, RIR 2–4, avoid routine failure. | §10.3 | **Have** |
| **Goal** | Rep allocation: hypertrophy 6–12 primary; strength 1–6 at 80–95%; endurance 15–30 at 40–60%. | §10.4 | **Have** |
| **Exercise class (compound/isolation)** | RIR 1–3 compound vs 0–2 isolation; rest 120–300 s vs 60–120 s. | §2.2, §5 | **Missing** — no classification on `PlannedExercise` |

### 2.5 Rest

Rest is fully determined by exercise class + goal + sex + age: 120–300 s compound (target 150–180), 60–120 s isolation, floor >60 s, 180–300 s for maximal strength, −20–30% for females at matched %1RM, +30–60 s for older adults. All inputs already exist except **exercise class**, which is the same missing field as above. This is a case where a hardcoded `default=90` is being used in place of a computation that needs no new user data at all.

### 2.6 Exercise selection

| Input | Why | Reference | Status |
|---|---|---|---|
| **Equipment** | Machines vs free weights are hypertrophy-equivalent, so equipment constrains selection without compromising the outcome — a genuinely usable constraint. | §6.1 | **Have** |
| **Injuries/limitations, structured** | The regression hierarchy (§11.2) and region-specific prescriptions (§11.3) are *algorithmic* — "shoulder impingement-type pain → neutral grip, ROM below painful arc, landmine/incline ≤30–45°, add external rotation 2×10–20 2–3×/wk." That can only be applied if the limitation is a structured region + severity, not a free-text blob. | §11.2, §11.3 | **Partial** — `injuries` is a `TextField` the AI interprets ad hoc |
| **Priority muscles** | Drives which muscles get long-length-emphasis picks and extra exercise variations. | §6.2, §6.4 | **Have** |
| **Existing plan history** | Hold core exercises constant 4–8 weeks; 2–3 variations per muscle per block; excessive rotation impairs load progression. Regeneration today produces a fresh plan with no continuity. | §6.4 | **Missing** — no block concept |

### 2.7 Recovery, progression, and nutrition context

| Input | Why | Reference | Status |
|---|---|---|---|
| **Training age** | Progression rate: +2.5–5%/wk (novice) vs +1–3%/mo (intermediate) vs +0.5–1%/mo (advanced). Deload cadence: 8–12+ wk / 6–8 wk / 4–6 wk. | §4.2, §10.2 | Partial |
| **Sex + training age** | Realistic lean-mass expectation setting (0.7–1.1 vs 0.35–0.55 kg/mo in year 1) — matters for retention, not for the plan itself | §4.2 | **Have** |
| **Sleep hours** | <6 h → MPS −18%, volume tolerance down, injury odds ~1.7×. A permissive variable: it should *cap* prescribed volume, not add to it. | §8 | **Missing** |
| **Bodyweight trend** | Gain/loss rate vs target (0.25–0.5%/wk novice gain; 0.5–1.0%/wk loss). Also an under-recovery marker (unintentional ↓>2%/wk). | §9.3, §7.2 | **Missing** — bodyweight is captured once at onboarding and never again |
| **Cardio volume** | Interference appears >3 sessions/wk and >20–30 min/session of high-intensity endurance; running ES −0.24, cycling ~0. Relevant only for the fat-loss goal. | §10.4 | **Missing** |

### 2.8 What is captured but does nothing

- **`motivation`** — five choices, no numeric consequence. Copy/tone input only.
- **`coach_personality`** — same. Belongs in post-signup settings, not before the first plan.
- **`training_style`** — the four options (`high_intensity`, `progressive_overload`, `high_volume`, `balanced`) are not mutually exclusive alternatives in the science. Progressive overload is mandatory for everyone (§4, listed #3 of the five variables that move the needle). "High volume" and "high intensity" are the two ends of the same dose-response curve, and the report is explicit that load is largely interchangeable when volume-equated and near failure (§2.1). Asking the user to pick one invites an unscientific prescription and gives the AI a licence to deviate from the computed volume. Recommend removal.
- **`training_environment`** — fully derivable from `equipment`. `commercial_gym` adds nothing that "barbell + dumbbells + machines + cables" doesn't already say.
- **`height_cm`** — not used by any training parameter in the report. Only relevant for a TDEE estimate, which the app does not currently compute. Keep only if nutrition guidance is on the roadmap; it is free to collect since it shares a screen with weight.

---

## 3. Onboarding vs. progressive collection

### 3.1 The decision rule

A data point belongs in onboarding if **(a)** a plan cannot be generated without it, **or** **(b)** getting it wrong initially produces a visibly bad first plan that costs more trust than the question costs friction. Everything else defaults, and gets corrected from behaviour.

Applying that:

**Must ask (plan is undefined without it):** goal, training age, days/week, session length, equipment, bodyweight, age, sex, limitations.

**Should ask (cheap, high prescriptive value):** priority muscles, strength anchors.

**Can default and refine:** current working loads for non-anchor lifts (seed from anchors/bodyweight multipliers, corrected within 1–2 sessions); RIR calibration (assume novice error ±1–3 reps, tighten over 8–12 weeks); actual session length vs stated (measured from `started_at`/`finished_at`); adherence; sleep; bodyweight trend; cardio volume; recovery capacity; pain response; exercise preferences.

Note the asymmetry that makes progressive collection work here: **almost every "can default" item is measurable from data the app already generates during normal use.** The app is a logging app; the logs *are* the profile.

### 3.2 Proposed onboarding set — 11 screens

Ordered roughly by declining engagement risk (cheap, identity-affirming questions first; the numeric ones once the user is invested).

| # | Screen | Type | Why it's in the pre-plan flow | Parameters it unlocks |
|---|---|---|---|---|
| 1 | **Primary goal** | single choice (existing 5) | Selects the entire row of §10.4 | sets/muscle/wk, %1RM, reps, RIR, rest, frequency |
| 2 | **How long have you been training consistently?** | single choice → **months** (Never / <6 mo / 6–24 mo / 2–5 yr / 5+ yr) | Replaces `experience`. Every tier table in the report keys on training age; the 3-bucket label collapses a 10-set-per-week spread into one option | volume tier, MEV, RIR target, progression rate, deload cadence, exercise pool size, periodization model |
| 3 | **About you** (age, sex, bodyweight, height) | numeric + choice, one screen | Age gates the >50/>60 modifiers; sex gates rest and rep-at-%1RM mapping; bodyweight gates load seeding and protein | rest ±, RIR floor, warm-up ramp sets, load caps, protein g/kg, gain/loss rate |
| 4 | **Days per week** | slider 2–6 | Split template and per-session set budget | frequency, split, sets/session |
| 5 | **Session length** | single choice → **numeric minutes** (30/45/60/75/90) | Converts to a hard set budget; the constraint that makes volume achievable rather than aspirational | sets/session cap, exercise count, rest feasibility |
| 6 | **Equipment** | multi choice (existing 6, + "bodyweight only") | Exercise pool; also absorbs `training_environment` | exercise selection, implement regression chain |
| 7 | **Limitations** | **structured region checklist** (shoulder / elbow / wrist / low back / hip / knee / ankle / none) + optional note | Converts free text into the algorithmic §11.3 prescriptions. Severity ("current pain" vs "past, now fine") decides regression depth | exercise substitution, ROM restriction, load reduction 20–50%, implement changes |
| 8 | **Priority muscles** | multi choice, **capped at 2** | Specialization allocation is a zero-sum trade against maintenance volume elsewhere; uncapped selection makes it meaningless | +sets to priority within MRV, non-priority toward maintenance floor |
| 9 | **Strength anchors** | 3 lifts, "weight × reps you could do today" — **skippable** | The single highest-value new question. Converts every %1RM in the report into a kg number. Skip → bodyweight-multiplier seed by sex/training age, corrected within 2 sessions | e1RM per pattern → concrete `target_load_kg`, progression increments |
| 10 | **Sleep + recovery context** | 2 taps (typical sleep band; current stress/fatigue 1–5) | Sleep is permissive: <6 h should *cap* prescribed volume rather than the plan silently over-prescribing. Cheap insurance against a first plan the user cannot recover from | volume cap, deload sensitivity, baseline for the wellness composite |
| 11 | **Plan summary / confirm** | review screen | Not a question — shows the computed numbers ("14 sets/week for chest, 3 sessions, 150 s rest on compounds") *before* generation. Converts the data collection into visible value and is the strongest anti-"generic" signal available | — |

**Count: 10 questions + 1 confirmation = 11 screens**, versus 12 today.

Removed: `motivation`, `coach_personality`, `training_style`, `training_environment` (4 screens). Added: strength anchors, sleep/recovery, summary (3 screens). `experience` upgraded in place; `injuries` upgraded in place; `workout_duration` type-changed in place.

`motivation` and `coach_personality` should move to a **post-signup "personalize your coach" step** — they affect tone, which matters for retention, but they should not be gating the first plan.

### 3.3 The alternative: an 8-screen minimum

If completion data shows 11 is still too many, the defensible minimum is: goal, training age, about-you, days/week, session length, equipment, limitations, confirm — **8 screens**. Priority muscles, strength anchors, and sleep move to progressive collection (first-session prompts).

Cost of the 8-screen version: the first plan has no load prescriptions (bodyweight-multiplier seeds only), no specialization, and no sleep-based volume cap. The first plan is the one shown pre-signup and is doing the conversion work — weakening it to save three screens is likely the wrong trade, but it is a real option and should be A/B'd rather than assumed.

### 3.4 Progressive collection plan

| Data point | Mechanism | When | Feeds |
|---|---|---|---|
| **RIR per set** | In-workout: one tap on a 0–4+ chip strip when logging a set, defaulting to the prescribed target so it's zero-friction to accept | From session 3 (let the first two be about learning the UI) | Load autoregulation ±2.5–5%; hard-set counting (only ≤4 RIR counts); failure-set cap (≤20–25% of weekly sets) |
| **e1RM per exercise** | Passive, from every `SetLog` (weight × reps → Epley/Brzycki) | Continuous | All `target_load_kg` values; stall detection; progression-rate reality check |
| **Session RPE** | Post-workout, one 1–10 slider — augmenting or replacing the current 4-level `difficulty` | Every session | Under-recovery marker: ↑≥1 point at identical prescribed work sustained over 2 weeks |
| **Per-exercise pain flag** | In-workout, optional tap: 0–10 NRS on any exercise | Ad hoc | Pain-monitoring framework: ≤3/10, must return to baseline by 24 h, must not rise week-over-week; triggers regression hierarchy |
| **Actual session duration** | Passive, `finished_at − started_at` | Every session | Corrects the stated session length; recalibrates set budget if the user consistently runs 20 min over |
| **Adherence / completion rate** | Passive, from session status and `ExerciseLog.status` (`skipped`) | Rolling 14 d | If completion is low, the *prescription* is wrong, not the user. Reduce volume toward MEV before assuming non-compliance |
| **Inter-session spacing per muscle** | Passive, from session dates + muscle tags | Continuous | 48 h minimum spacing for heavy compound work; flags when a plan's day order is being violated in practice |
| **Bodyweight** | Weekly check-in, one number | Weekly | Gain/loss rate vs target %BW/wk; unintentional ↓>2%/wk is an under-recovery marker |
| **Sleep + wellness composite** | Weekly check-in, 3 taps (sleep hours band, soreness, stress/mood 1–5) | Weekly | Composite drop >10–15% vs baseline is one of the deload triggers; subjective measures outperform objective ones per §7.2 |
| **Equipment / days / injury changes** | Block-boundary review, every 4–8 weeks | At block end | Regenerate with continuity rather than from scratch |
| **Exercise preference (keep/swap)** | Passive inference from replace/skip behaviour, already captured in `ExerciseLog.replaced_with_name` | Continuous | Exercise pool weighting; a consistently-replaced exercise should stop being prescribed |

**Design principle for progressive prompts:** never more than one new question per session, and never before the user has completed the workout. The weekly check-in should be a single screen, ≤30 seconds, dismissible without penalty.

---

## 4. From qualitative labels to real numbers

### 4.1 The prescription layer

Proposal: a new pure-Python module — `apps/coaching/services/prescription.py` or a new `apps/prescription` app — exposing something like:

```
compute_prescription(profile, training_state) -> Prescription
```

Deterministic, no AI, no I/O, fully unit-testable against the research tables. `training_state` carries what's known from logs (e1RM estimates, block week index, recent adaptation decisions, adherence, recovery markers); for the anonymous pre-signup preview it is simply empty, and the function still returns a complete prescription from onboarding alone.

The output is a structured object, not prose:

- **Per-muscle:** `weekly_sets_target`, `mev`, `maintenance_floor`, `sessions_per_week`, `sets_per_session_cap`
- **Global:** `split_template`, `session_set_budget`, `rep_distribution` (fraction of sets in 4–6 / 6–12 / 12–20+), `progression_rule` (increment size and trigger), `deload_policy`
- **Per exercise class:** `rir_target`, `rest_seconds`, `tempo`, `warmup_ramp_sets`
- **Per movement pattern:** `e1rm_kg`, `e1rm_confidence`, `target_load_kg` at the prescribed %1RM, rounded to the achievable increment for the equipment
- **Constraints:** banned movement patterns, ROM restrictions, required substitutions from the limitation profile

### 4.2 Label → number mappings

**`experience` → training age → volume tier** (§1.2, §10.2):

| Answer | Months | Weekly sets/muscle | MEV | RIR compound | RIR isolation | Progression | Deload |
|---|---|---|---|---|---|---|---|
| Never trained | 0 | 6–8 | ~3–4 | 3–4 | 2–3 | +2.5–5%/wk, session-to-session linear | 8–12+ wk / autoregulated |
| <6 months | 0–6 | 6–10 | ~4 | 2–4 | 1–3 | +2.5–5%/wk linear | 8–12+ wk |
| 6–24 months | 6–24 | 10–16 | ~5–6 | 2–3 | 1–2 | weekly linear | 6–8 wk |
| 2–5 years | 24–60 | 12–20 | ~6–8 | 1–3 | 0–2 | +1–3%/mo, DUP | 6–8 wk |
| 5+ years | 60+ | 15–25 | ~8–10 | 0–3 | 0–2 | +0.5–1%/mo, block | 4–6 wk |

Note the report's own caveat: the advanced numbers are Low-confidence extrapolation. The prescription layer should start advanced users at the **lower** end of their band and ramp, per the "≤2× MEV in a first block" rule (§1.3), rather than opening at 25 sets.

**`goal` → the §10.4 row**, applied as a modifier on top of the training-age tier — e.g. `increase_strength` shifts rep distribution toward 1–6 at 80–95% and rest to 180–300 s; `lose_fat` holds load fixed and permits a 20–40% volume cut but never below 6–10 sets/muscle/wk.

**`training_style` → deleted, replaced by autoregulation.** Users who want "high intensity" get it through RIR targets that tighten as their RIR estimation calibrates; users who want "high volume" get it through the volume ramp within their tier ceiling. Neither should be a static label that overrides the dose-response curve.

**Bodyweight + sex + training age → seed e1RM** when the anchor screen is skipped. Bodyweight multipliers by pattern, adjusted for sex and training age, produce a starting number that is wrong but *bounded* — and every logged set corrects it. Confidence should be stored alongside the estimate so the adaptation engine knows whether it's acting on a guess or on measured data.

**Structured limitations → the §11.2 hierarchy**, applied in order, one variable at a time: reduce load 20–50% → restrict ROM to the pain-free arc (re-expand 10–20°/wk) → slow eccentric 3–6 s → change implement (barbell → dumbbell → cable → machine) → unilateral → change movement pattern → isolate around the joint. This is a decision table, not something to leave to the model's discretion.

### 4.3 The proof: two users, identical labels

Both answer: goal `build_muscle`, experience `intermediate`, 4 days/week, 60 min, commercial gym, priority chest. Today they receive the same prompt modulo two numbers the model has no instruction to use, and — predictably — near-identical plans.

Under the proposal:

| | User A | User B |
|---|---|---|
| Inputs | M, 24, 82 kg, trained 30 mo, bench e1RM 100 kg, sleeps 8 h, no limitations | F, 52, 61 kg, trained 8 mo, bench e1RM 35 kg, sleeps 5–6 h, shoulder impingement |
| Weekly sets, chest | 18 (priority, upper tier) | 11 (lower tier: <12 mo training age, sleep <6 h caps volume, age >50 recovery ceiling) |
| Sessions/muscle | 3 (18 sets ÷ ≤10/session ⇒ ≥2, chosen 3) | 2 |
| Rest, compound | 150 s | 150 s × (1 − 0.25 female) = 115 s, + 45 s age adjustment ⇒ **160 s** |
| RIR, compound | 1–3 | 2–4 (training age + age >50: avoid routine failure) |
| Bench prescription | 4 × 6–8 @ **72.5 kg** (~72% e1RM), 2 RIR | Barbell bench excluded (impingement) → **landmine press, incline ≤30–45°**, 3 × 8–10 @ **20 kg**, 3 RIR, ROM below painful arc |
| Added work | Long-length chest pick (deep flye / crossover) | + external rotation & lower-trap, 2 × 10–20, 2×/wk per §11.3 |
| Progression | +2.5 kg when 8 reps hit on all sets at ≤1 RIR | +1 kg upper body, weekly, load increase capped ≤10%/wk |
| Warm-up | 2 ramp sets | 3–4 ramp sets (>50) |

These are different programs derived from the same qualitative answers. That difference is the product.

---

## 5. Adaptation engine

### 5.1 What's wrong with the current rules

```python
failed = sum(1 for s in sets if s.reps < planned.target_reps_min)
exceeded_all = all(s.reps > planned.target_reps_max for s in sets)
if failed >= 2:   -> DECREASE_LOAD
elif exceeded_all: -> INCREASE_LOAD
```

Four problems:

1. **It compares against the plan, not against the user's own prior performance.** The §7.2 marker is "reps at a *fixed load* drop >5% versus last session, on two consecutive exposures." The engine never looks at the previous exposure to the same exercise, so it cannot compute the marker the evidence specifies.
2. **It ignores load.** Missing the rep target at a weight the user just increased by 5% is normal progression behaviour, not under-recovery. Missing it at the same weight as last week is a real signal. These produce identical decisions today.
3. **`failed >= 2` on a single session has no basis.** The research requires **two consecutive exposures** before concluding under-recovery — a single bad session is noise (poor sleep, a bad day) and reducing load on it will systematically under-load users.
4. **`exceeded_all` is too strict in the wrong way.** Requiring every set to exceed the rep *maximum* means a user who hits the top of the range exactly on all sets — the textbook double-progression trigger (§4.1) — never gets an increase.

`evaluate_feedback` has a separate issue: it queries the user's last 3 `WorkoutFeedback` rows with **no time window**, so three "hard" sessions spread over three months trigger a volume cut. It also uses the 4-level ordinal, which cannot express the "sRPE ↑≥1 point at identical prescribed work" marker.

### 5.2 Proposed rule set

All thresholds below come from §7.2, §4.1, and §11.1 of the findings.

| Rule | Trigger | Action | Reference |
|---|---|---|---|
| **R1 — Load increase (double progression)** | All working sets reach the **top of the prescribed rep window** at ≤1 RIR, on one exposure | +2.5–5%: **+1–2.5 kg upper body, +2.5–5 kg lower body**; reset to the bottom of the window | §4.1 |
| **R2 — Load decrease (under-recovery)** | Reps at the **same load** drop **>5%** (or ≥1 rep on a set of ~10) vs the previous exposure, **on two consecutive exposures** | −5–10% load, hold volume | §7.2, §1.3 |
| **R3 — Stall** | No e1RM improvement across **3 consecutive exposures** at constant volume | Change **one** lever: +1 set, or rotate the exercise if it has been held ≥4 weeks | §4.1, §6.4 |
| **R4 — Volume ramp** | Within an accumulation block, weekly | **+1–2 sets/muscle/week**, opening at ≤2× MEV, capped at the training-age tier ceiling; reset at deload | §1.3, §4.1 |
| **R5 — Deload (autoregulated)** | **2+ under-recovery markers** trip, or performance stalls 2 consecutive sessions | 5–7 days: **−30–50% sets, −0–20% load, 4–6 RIR** | §7.3 |
| **R6 — Pain** | Pain >3/10 during loading, OR not back to baseline by 24 h, OR rising across a 7-day window | Reduce load **20–50%** or regress **one** step in the §11.2 chain — one variable at a time | §11.1, §11.2 |
| **R7 — Adherence** | Completion <60–70% of prescribed sets over 14 days | Reduce prescribed **volume** toward MEV and/or session length. In a deficit: never reduce load — cut volume 20–40% but never below 6–10 sets/muscle/wk | §9.3, §10.4 |
| **R8 — Failure-set cap** | >25% of weekly sets logged at 0 RIR | Flag; failure training impairs subsequent strength expression and volume performance | §2.2 |
| **R9 — Novice RIR discount** | User has <8–12 weeks of RIR-anchored logging | Weight self-reported RIR at **low confidence** (novice error ±1–3 reps, systematically over-estimating reps remaining); prefer objective rep/load signals for R1/R2 | §2.2 |
| **R10 — Load-increase cap** | Any load increase | Cap weekly load or volume increase at **≤10%** (tendon remodels 2–3× slower than muscle) | §10.3, §11.3 |

### 5.3 Under-recovery markers to track (for R5)

Feasible with app data, no wearables:

- Reps at fixed load ↓>5% vs last exposure — needs the per-exercise history query R2 also needs
- Session RPE ↑≥1 point at identical prescribed work, sustained 2 weeks — needs the 1–10 sRPE field
- Subjective wellness composite ↓>10–15% vs baseline — needs the weekly check-in
- Joint/tendon discomfort persisting >72 h — needs the pain flag
- Unintentional bodyweight ↓>2% over a week — needs weekly bodyweight
- Sleep <6 h sustained — needs the weekly check-in

Deliberately **not** proposed: HRV (§7.2 rates it **Low** confidence for resistance training specifically), and CMJ/grip tests (require the user to perform a test they didn't ask for). DOMS should be captured for user-facing empathy but must **not** drive programming — §7.1 is explicit that soreness is a poor proxy for both recovery and growth.

### 5.4 A note on honesty about confidence

The findings grade deload evidence as **Low** and say a planned deload may cost volume without demonstrable benefit in non-elite lifters. R5 is therefore correctly specified as *autoregulated, not calendar-driven*, and the system should not insert scheduled deloads for novices. Where the engine acts on Low-confidence parameters, `AdaptationHistory.reason` should say so — this is also better coaching UX than a false-certainty message.

---

## 6. Architecture implications

### 6.1 Data model changes (proposal, not implementation)

**`apps/onboarding` — `OnboardingProfile`:**
- `training_age_months` (int) replacing / supplementing `experience`
- `session_minutes` (int) replacing the `workout_duration` CharField
- `limitations` (JSON: list of `{region, status, severity}`) supplementing free-text `injuries`
- `sleep_hours_band`, `baseline_stress` (small ints)
- `training_style`, `training_environment` deprecated; `motivation` and `coach_personality` made nullable and moved post-signup
- Migration path: keep the old columns, derive the new ones for existing rows (`beginner` → 3 mo, `intermediate` → 18 mo, `advanced` → 60 mo), backfill, then drop later.

**New — `StrengthEstimate`:** `(user, movement_pattern, exercise_name, e1rm_kg, confidence, source, updated_at)`. `source` ∈ {onboarding_anchor, logged_set, bodyweight_seed}. Updated on every `log_set`.

**New — `TrainingBlock`:** `(user, plan, started_at, week_index, phase, deload_active)`. Without this there is nowhere to store "which week of the ramp are we in," and R3/R4/R5 and the "hold exercises constant 4–8 weeks" rule are all unimplementable.

**New — `WeeklyCheckIn`:** `(user, week_start, bodyweight_kg, sleep_hours, soreness, stress, mood)`.

**`apps/workouts`:**
- `PlannedExercise`: `+ target_rir_min/max`, `target_load_kg`, `primary_muscle`, `secondary_muscles` (JSON, fractional weights per §1.4), `exercise_class` (compound/isolation), `tempo`, `is_lengthened_emphasis`, `warmup_sets`
- `SetLog`: `+ rir` (nullable), `+ is_warmup` (bool) — without `is_warmup`, hard-set counting is wrong from day one
- `ExerciseLog`: `+ pain_score` (nullable 0–10)
- `WorkoutFeedback`: `+ session_rpe` (1–10), keeping `difficulty` for backwards compatibility

**Muscle taxonomy:** a canonical muscle list plus an exercise → `{primary: [...], secondary: [...]}` mapping is a prerequisite for everything volume-related. Two options: (a) a server-side lookup table for common lifts with the AI supplying tags for anything unrecognised, or (b) trust the AI's tags entirely. (a) is more work but makes volume counting auditable; (b) is faster but means the volume math depends on the model being consistent. **Recommend (a) with (b) as fallback.**

### 6.2 Prompt restructuring

Replace the single prose blob in `_build_prompt()` with three explicitly separated sections:

1. **Hard numeric constraints (computed, non-negotiable).** Per-muscle weekly set targets and per-session caps, the split template and day names, the session set budget, rep distribution percentages, RIR targets by exercise class, rest seconds by exercise class, `target_load_kg` per movement pattern, banned patterns and required substitutions. Framed as constraints the response *must* satisfy, not as context.
2. **Exercise-selection guidance (judgement, delegated to the AI).** 4–8 exercises/session, 1–3 compounds first when fresh, 2–5 isolation, 2–4 distinct exercises per muscle per week, ~50–70% compound sets, ≥1 lengthened-position exercise per muscle per week (with the §6.2 concrete picks available as a reference list), equipment-legal only, exercises held constant for 4–8 weeks with continuity against the previous block.
3. **Extended output schema.** Add `target_rir_min`, `target_rir_max`, `target_load_kg`, `primary_muscle`, `secondary_muscles`, `exercise_class`, `tempo`, `is_lengthened_emphasis`, `warmup_sets` to `_SCHEMA_INSTRUCTIONS`, `_to_display_shape`, and the `PlannedExercise` write in `persist()`.

The design intent: **the model chooses exercises and their order; it never chooses the dose.**

### 6.3 Post-generation validation

`_validate_display_shape()` currently only checks that required keys exist. It should become a real constraint checker that, given the `Prescription`:

- recomputes weekly sets per muscle from the returned plan (using fractional counting) and rejects if outside the target band
- verifies the session set budget is not exceeded
- verifies rest values fall in the class-appropriate bracket (and rejects the current silent `default=90`)
- verifies no banned movement pattern appears
- verifies loads are within a plausible band of the e1RM estimate

On failure: one repair round-trip stating the specific violations, then a deterministic fallback that trims the plan to fit rather than surfacing an error. This is the mechanism that actually guarantees the plan is evidence-grounded — without it, everything upstream is a suggestion the model may ignore.

### 6.4 Flow-specific notes

- **Anonymous preview:** `compute_prescription` runs fine on an unsaved `OnboardingProfile` with empty training state, so `/plans/preview/` keeps working. Strength anchors given at onboarding are usable immediately; users who skip them get bodyweight-seeded loads flagged as low confidence in the UI ("we'll dial this in after your first session").
- **`save-preview`:** the client currently posts display-shape JSON back and `persist()` writes it. With numeric fields present, the server should **re-validate against a freshly computed prescription** rather than trusting the round-tripped payload. Worth noting this is already a soft integrity gap today.
- **Adaptation → prompt:** `_format_adaptation_notes` currently passes free-text reasons. It should instead pass **resolved numeric deltas** (e.g. "chest weekly sets 14 → 16; bench target load 72.5 kg"), so adaptation modifies the prescription object rather than nudging the model with prose.
- **Frontend:** `OnboardingDraft` and `onboarding_flow_screen.dart` change shape; the step machine is a flat `switch` on `_step` with a hardcoded `_stepCount = 12`, so reordering is mechanical but touches every case. Worth considering a declarative step list at the same time. The new plan-summary screen (#11) is genuinely new UI. `AuthInterceptor`, `app_router.dart`, and the preview/save-preview providers are unaffected.

### 6.5 Suggested sequencing

- **Phase 1 (no new user data):** prescription layer + prompt restructure + validator + exercise/muscle taxonomy + fix the `rest_seconds=90` default. Delivers most of the "not templated" benefit on existing fields.
- **Phase 2 (onboarding changes):** training age in months, numeric session minutes, structured limitations, strength anchors, plan-summary screen; prune dead questions.
- **Phase 3 (in-app capture):** `SetLog.rir` + `is_warmup`, session RPE, pain flag, `StrengthEstimate` maintenance.
- **Phase 4 (adaptation):** rewrite `engine.py` against §5.2; add `TrainingBlock` and `WeeklyCheckIn`; implement deload and volume-ramp.

---

## 7. Tradeoffs, stated explicitly

### 7.1 Strength anchors (screen #9)

- **For:** the only question that converts every %1RM in the report into an actionable kg number in the first plan. Without it, the pre-signup plan — the plan doing the conversion work — shows rep ranges but no loads, which is the most visible "generic" tell.
- **Against:** it is the hardest question in the flow. Beginners genuinely don't know, and asking may produce anxiety or an abandon at the worst possible point (screen 9 of 11, still pre-signup).
- **Mitigation:** make it explicitly skippable with a friendly default path, accept "weight × reps" rather than a true 1RM (nobody knows their 1RM; everyone knows what they did last Tuesday), and show the seeded estimate so skipping still yields loads.
- **Alternative:** move it to the first workout ("what did you lift?") — costs a weaker preview plan, buys a cleaner funnel. **This is a genuine A/B test, not a settled question.**

### 7.2 Structured limitations vs. free text

- **For:** free text cannot drive the §11.3 decision tables; a checklist can.
- **Against:** checklists miss the long tail (hernia, post-surgical, cardiac, pregnancy) and can feel clinical/off-putting.
- **Mitigation:** checklist **plus** the existing free-text field, with the free text still passed to the AI as context. Also note the report's own framing: this is training-science principle, not medical advice, and the UI should say so.

### 7.3 Keeping the 2-days/week option

The `training_days` validator allows 2, but §3 puts total sessions at **3–6**. Two days/week is not covered by the split templates and forces a full-body prescription at the per-session ceiling. Options: (a) keep 2 and prescribe full-body at 6–10 sets/muscle/session with an honest "this is a maintenance-plus dose" message; (b) raise the minimum to 3. (a) is better for the `build_habits` goal and for retention; (b) is better science. **Recommend (a) with explicit framing.**

### 7.4 Per-set RIR capture

- **For:** RIR is #2 on the report's list of variables that move the needle and is the input to nearly every autoregulation rule.
- **Against:** it adds a tap to every set, and novice RIR estimates carry ±1–3 reps of error — so early data is noisy, and acting on it confidently would be worse than ignoring it.
- **Mitigation:** default the chip to the prescribed target (accepting is zero taps), introduce it from session 3, and apply R9's confidence discount for the first 8–12 weeks. Consider a short in-app RIR explainer, since the report notes accuracy improves specifically with *anchored practice*.

### 7.5 Deterministic prescription vs. AI creativity

- **For determinism:** reproducible, testable against the research tables, auditable, cheaper (a tighter prompt), and it is the only way to *guarantee* evidence alignment.
- **Against:** it constrains the model to exercise selection, which is a narrower job than "AI coach" marketing implies, and a rigid envelope can produce mechanically-correct but joyless programs.
- **Mitigation:** the constraints are **bands**, not points (14–18 sets, not 16). The AI chooses within them, plus exercise selection, ordering, day naming, variation, and coaching notes — which is where a plan actually feels human. The numbers were never the part users experienced as "creative."

### 7.6 Onboarding length generally

Going from 12 → 11 screens is roughly neutral on friction while materially raising information content. But the *content* gets harder: replacing a tap-a-card question (`motivation`) with a type-a-number question (strength anchors) increases per-screen cost even as the count drops. Screen count is the wrong metric; **time-to-plan and per-screen drop-off** are the right ones, and they should be instrumented before and after any change here.

### 7.7 Scope of what this proposal does not address

The findings contain extensive nutrition (§9), sleep (§8), and supplement guidance. This proposal uses sleep only as a volume cap and bodyweight trend only as a recovery marker; it does not propose a nutrition feature. That is a deliberate scope boundary — nutrition would need its own data model, its own onboarding questions (dietary pattern, TDEE inputs, food logging), and carries a different risk profile. Worth a separate strategy document; folding it in here would double the onboarding.
