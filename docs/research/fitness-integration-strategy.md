# General Fitness Integration Strategy (`goal == improve_fitness`)

**Status:** Proposal for review. No code, migrations, or config have been changed.
**Inputs:** `docs/research/fitness-findings.md` (treated as ground truth for every number below), the current state of `apps/onboarding`, `apps/workouts`, `apps/adaptation`, `apps/progress`, and `frontend/lib/features/{onboarding,progress}/`, plus the three existing goal proposals: `coach-integration-strategy.md` (`build_muscle`), `strength-integration-strategy.md` (`increase_strength`), `habits-integration-strategy.md` (`build_habits`).
**Scope:** what a numerically-grounded general-fitness prescription needs, whether the current plan data model can represent it (it cannot), what to ask at onboarding vs. infer, and how adaptation/progress should work when the goal is not driven by load progression.

---

## 0. Recommendation summary (read this if nothing else)

Three of the four existing proposals share a diagnosis: the pipeline never computes a number, so the AI falls back on priors. That diagnosis holds here too — but for `improve_fitness` there is a **second, larger problem that the other goals do not have**:

> **The app cannot represent this goal's plan at all.** `WorkoutPlan → WorkoutDay → PlannedExercise` is shaped `(exercise_name, target_sets, target_reps_min, target_reps_max, rest_seconds)`, and `SetLog` is shaped `(weight, reps)`. There is no field anywhere in the schema that can hold "30 minutes at 64–76% HRmax," "4 × 4 min at 85–95% HRmax with 3 min recovery," or "single-leg stance, eyes open, 3 × 30 s each side." Meanwhile the research is unambiguous that the correct prescription for this goal is **150–300 min/week of cardio + 30–60 min/week of resistance + age-gated balance/mobility**, and that the *combination* is what delivers ~40% lower all-cause mortality versus ~15–25% for either component alone (§2.2, §4.1).

So for this goal the honest framing is: the other four goals need a prescription layer bolted onto an existing chassis. This one needs the chassis widened. **A "lighter hypertrophy plan" is not a degenerate version of the right answer — it is a different prescription that omits the single highest-value component (cardio/CRF, §3.1: −10–15% all-cause mortality per +1 MET, a stronger mortality predictor than smoking, hypertension, or BMI).**

Prioritized:

| # | Change | Effort | Payoff | Needs new user data? |
|---|---|---|---|---|
| 1 | **Extend the plan model with a block-type discriminator** — `PlannedExercise` gains `block_type ∈ {resistance, cardio_steady, cardio_interval, mobility, balance, power, isometric}` plus nullable duration/intensity fields; `SetLog` gains nullable `duration_seconds`, `distance_m`, `avg_hr`, `rpe` and its `weight`/`reps` become nullable | M–L | **Blocking.** Nothing else in this document is implementable without it | No |
| 2 | **`GeneralFitnessStrategy` in the shared prescription layer** — computes weekly moderate-equivalent minutes, vigorous share, resistance sessions/sets, balance minutes by age band, steps target, from onboarding fields | M | Very high — turns the goal from "a vaguer split" into a real dose | Partly (needs #4) |
| 3 | **Restructure the prompt for this goal** — the AI is asked to fill a *weekly time budget across block types*, not to design a split; extended output schema with duration/intensity fields | S | Very high | No |
| 4 | **2 net-new conditional onboarding screens** (current activity baseline + submaximal self-assessment; cardio modality access), plus a health-conditions section added to the existing limitations screen | S | High — without baseline activity the starting dose is a guess with a 5× range | Yes (conditional on this goal only) |
| 5 | **New `ActivityLog` model** for non-session activity (walks, steps, bike commutes, "exercise snacks") that should count toward the weekly target but is not a `WorkoutSession` | M | High — this is where most of a general-fitness user's weekly minutes actually come from | Yes (lightweight logging) |
| 6 | **New `HealthMarker` model + 8–12-week milestone check-ins** (RHR 7-day avg, home BP, 30-s chair stand, single-leg stance, submaximal step test / fixed-route walk) | M | High — this goal has no scale weight and no 1RM; without these the app can never show the user it is working | Yes (opt-in, periodic) |
| 7 | **Rework `/progress` for this goal** — `total_volume` (Σ weight × reps) is structurally ~0 for a correct general-fitness plan; replace the headline with weekly MVPA minutes vs. target, sessions, steps, and marker trends | M | High — today this user's progress screen shows an empty bar chart | No (given #1/#5/#6) |
| 8 | **Goal-conditional adaptation rules** — progression axis becomes cardio minutes/intensity, not load; the existing rep-based `DECREASE_LOAD` rule is largely the wrong axis and should be desensitized here | M | Medium–high | Partly |

**Scope honesty, stated up front.** Items 1, 5, 6, and 7 are new plumbing — roughly two new models, ~10 new nullable fields, a new in-session logging surface for timed/cardio work, and a new progress surface. That is **meaningfully more product and engineering investment than the other four goals require**, all of which reuse the resistance-training chassis largely unchanged. This should be a deliberate decision, not something discovered mid-implementation. §8 sets out a reduced-scope option and what it costs.

---

## 1. Problem framing

### 1.1 What the code does today for an `improve_fitness` user

`goal` reaches exactly one place in the backend: `_build_prompt()` in `plan_generator.py` interpolates `profile.get_goal_display()` → the string `"Improve Fitness"` into a prose paragraph. There is no branch on goal anywhere in the codebase (verified — `Goal.IMPROVE_FITNESS` appears only in the model, the migration, and the frontend option list). The prompt then says:

> "You are an expert strength and conditioning coach designing a personalized workout program… Design a training split with exactly `{training_days}` training days…"

and the response schema is `{name, sets, reps_min, reps_max, rest_seconds, order}`.

So an `improve_fitness` user today receives a resistance-training split, generated by a prompt that frames the coach as a strength coach, expressed in a schema with no representation for time or intensity. The most likely model behavior is a slightly higher-rep, slightly-more-circuit-flavored lifting plan — possibly with a "cardio" line item smuggled in as an exercise with fabricated sets and reps, which then corrupts every downstream computation (see §2.2).

Four further specifics from the current code that bite this goal in particular:

1. **`priority_muscles` is required.** `onboarding_flow_screen.dart` case 9 sets `nextEnabled: draft.priorityMuscles.isNotEmpty`. A user whose goal is "feel better and improve health markers" is forced to nominate favorite muscle groups before they can proceed. The research says coverage of **all major muscle groups, ~6–8 compound movements** (§2.1, §2.4) — specialization is not a concept in this goal at all.
2. **`equipment` options are resistance-only** (`barbell, dumbbells, machines, cables, pull_up_bar, resistance_bands`). There is nowhere to say "I have a bike," "I can walk outdoors," "I have a pool," "I have stairs." Yet §1.4 and §13.2 make modality selection load-bearing: high-BMI and knee-OA users need low-impact modalities (running is ~2.5–3× bodyweight per step), and novice runners carry ~17–33 injuries/1,000 h vs. ~8 for regulars.
3. **`workout_duration` is a per-session `CharField`** including the non-numeric string `'90+'`. This goal's core parameters are all *weekly* time (150–300 min cardio, 30–60 min resistance). There is no weekly budget concept anywhere.
4. **`training_days` is validated 2–6.** The research puts the adherence sweet spot at **3–4 sessions/week**, with dropout rising materially above 4–5 (§4.3). For this goal 6 days is actively contraindicated by the adherence evidence, and 2 days is below the aerobic-frequency floor of ≥3 days/week (§1.1) unless non-session activity is counted — which the app cannot currently count.

### 1.2 Why "a lighter hypertrophy plan" is the wrong answer, in numbers

| Parameter | What a scaled-down hypertrophy plan gives | What the research prescribes for this goal | Reference |
|---|---|---|---|
| Weekly cardio | 0 min | **150–300 min moderate** (or 75–150 vigorous), floor 60–75 min | §1.1, §1.4 |
| Weekly resistance time | 90–150 min (3 × 30–50 min) | **30–60 min** — the peak of the J-shaped mortality curve; benefit *attenuates* above ~130–140 min/week | §2.2 |
| Sets/muscle/week | 12–20+ | **4–10** | §2.4 |
| Rep range | 6–12 emphasis | **8–15**, and rep range is a **free parameter** (5–30 all viable) | §2.4 |
| Proximity to failure | 0–2 RIR | **2–4 RIR**; failure not required | §2.1, §2.4 |
| Balance work | none | **age-gated: 0 → 30 min × 3/wk from <40 to 80+** | §5.2 |
| Mobility | none | 10 min, 2–3+ d/wk, folded into warm-up/cool-down | §5.1 |
| Load precision | tracked, progressive | **±10–15% is fine** | §2.4 |

Note the direction of the resistance error: a scaled-down hypertrophy plan does not merely under-serve this goal, it **over-prescribes the resistance component** relative to the mortality-benefit curve while prescribing zero of the component with the strongest evidence. §2.4's framing is the one to internalize: *every parameter that requires precision in a hypertrophy program is a wide, forgiving band here.* The precision this goal needs is entirely in the **weekly time allocation across modalities**, which is exactly the axis the current system has no representation for.

---

## 2. Data-needs analysis

### 2.1 What a numerically-grounded first prescription requires

Each row: the parameter, the input needed to compute it, why, and whether the input exists today.

| Parameter to compute | Input needed | Why (research anchor) | Status today |
|---|---|---|---|
| **Starting weekly MVPA minutes** (60–75 floor → 150–300 target) | **Current activity level** — approximate current weekly minutes of brisk activity | §1.4 sets the floor at 60–75 min/wk and the target at 150–300; §11.2 sets a *complete beginner* at 60–90 min/wk building to 150 over 6–12 weeks, while an already-active user starts at 150+ and the highest-yield addition becomes resistance or vigorous work. This single input spans a **5× range of correct starting doses** (60 vs. 300 min) and changes *which component is the priority*. | **Missing.** `experience` (beginner/intermediate/advanced) measures resistance-training skill, not aerobic activity level, and the two dissociate constantly (a marathon runner who has never lifted is "beginner") |
| **Progression rate and consolidation cadence** | Same as above + weeks elapsed | +5–10%/week aerobic volume with a non-progressing week every 3–4 weeks (§10.1); long-deconditioned (≥6–12 mo inactive) starts at **50% of guideline**, 10–15 min bouts, 2–3×/wk (§13.2) | Missing |
| **Vigorous/interval share** (0 → 1–2 sessions/wk) | Current activity level + age + health conditions | §1.4: 1–2 vigorous/interval sessions/week is "the highest-leverage single addition for VO2max." But §10.4: self-selected/moderate intensity produces a **10–20 percentage point adherence advantage** in sedentary populations, so vigorous work should be *added later*, not prescribed at week 1 to a sedentary user | Missing |
| **Resistance dose** (2 sessions × 20–30 min, 1–3 sets, 8–15 reps, 60–70% 1RM, RIR 2–4) | Days available, session minutes, age, experience | §2.1, §2.2. Largely computable from existing fields | **Have** (days, duration, experience, age) |
| **Rep range and load band** | **Age** | §2.1: **10–15 reps** specifically for older/deconditioned adults; ≥50% 1RM produces meaningful benefit in older adults; §11.3: 60–79 → 1–3 sets × 10–15 at 50–80% 1RM | **Have** |
| **Balance training dose** | **Age** (the sharpest gate in the whole report) | §5.2: <40 → 5 min/wk incidental; 40–59 → 5–10 min 2×/wk; 60–69 → 10–20 min 3×/wk; 70–79 → 20–30 min 3×/wk; 80+ → 30 min 3×/wk, co-equal with resistance. Inflection at **60–65**. Multi-component (balance + functional + resistance) is the best-performing category at **−34% fall rate** | **Have** (age) — but no way to express the output |
| **Power training inclusion** | **Age** | §11.3: ≥60 → 2×/wk, 3 × 6–10 reps at 40–60% 1RM at **maximal concentric velocity**; power correlates with function more strongly than strength. 40–59: "begins to earn its place" | **Have** (age); no representation in the schema (this is a *tempo/intent* prescription, and `PlannedExercise` has no tempo field) |
| **Bone-loading emphasis** | **Age + sex** | §11.1: women lose ~1–2%/yr bone mass around menopause → **loading-focused resistance + impact becomes disproportionately valuable from ~age 45**. §2.3: BMD needs ≥80–85% 1RM and/or impact (10–50 impacts/session, 3–5×/wk). This is one of only three defensible sex-linked adjustments in the entire report | **Have** (age, sex) |
| **Cardio modality** | **Available cardio environment/equipment** | §13.2: obesity/high BMI → prefer non-weight-bearing (cycling, swimming, elliptical, rowing) initially; §4.2: cycling/rowing interfere less than running with lower-body strength; §10.1: novice runners need run/walk intervals for the first 4–8 weeks | **Missing.** The `equipment` list has no cardio options at all |
| **Impact permission** | **Health conditions** (osteoporosis, knee OA, joint pain, high BMI) | §13.2: osteoporosis → avoid loaded spinal flexion and rapid trunk twisting, include impact *where safe*; knee OA → exercise is first-line, land-based ≈ aquatic; high BMI → low-impact first | **Partial.** `injuries` free text; not structured, not health-condition-shaped |
| **Isometric BP adjunct** | **Hypertension flag** | §6.3: isometric is the *top-ranked* modality for BP (−8.24/−4.00 mmHg), protocol 4 × 2 min at 30–40% MVC, 3×/wk. §13.2 adds: avoid maximal Valsalva-heavy lifting if BP uncontrolled. Effects ~2× larger in hypertensives | Missing |
| **Activity-spacing constraint** | **T2D/prediabetes flag** | §13.2 (ADA-specific): **no more than 2 consecutive days without activity**, because insulin-sensitivity effects last 24–72 h. This is a *scheduling* constraint no other goal has | Missing |
| **Steps target** | **Age** | §1.3: 6,000–8,000/day (≥60); 8,000–10,000 (<60) — mortality plateaus there | **Have** (age); nothing consumes or displays it |
| **Session count and length caps** | Days available + adherence evidence | §4.3: 3–4 sessions/week is the 12-month adherence sweet spot; dropout rises above 4–5; session duration >60 min is a stronger dropout predictor than frequency | **Have** |
| **Baseline CRF (for expectation-setting and marker targets)** | **Submaximal self-assessment** (a proxy) | §3.2 gives expected ΔVO2max by training status (+15–20% untrained vs. +2–5% well-trained in 8–12 wk); §12.1 gives the timeline of noticeable signals. Getting the user's expectations wrong is the documented dropout mechanism (§12.3: "expectation-setting here is the single highest-leverage retention intervention") | **Missing.** A lab VO2max test is obviously out of scope — see §4.4 for the proxy |
| **Sleep** | Sleep hours band | §8.2: exercise improves sleep (+15–25 min TST, ~0.5–0.7 SD PSQI) at 8–12 weeks — for this goal sleep is more valuable as a **trackable outcome** than as a volume cap | Missing (already proposed in `coach-integration-strategy.md` §3.2 screen 10 — reuse, do not duplicate) |

### 2.2 The plan-model gap — assessment and recommendation

**Direct answer: no, `WorkoutPlan`/`WorkoutDay`/`PlannedExercise` cannot represent a cardio session or a balance block, and there is no way to force it that does not corrupt data the rest of the system depends on.**

The three workarounds someone will propose, and why each fails:

**(a) Encode cardio as a `PlannedExercise` with `sets=1, reps=minutes`** (e.g. "Brisk Walk, 1 × 30").
- `evaluate_reps()` in `adaptation/services/engine.py` compares `SetLog.reps` against `target_reps_min/max`. A user who walks 25 min instead of 30 registers as a **rep failure** and, on two such logs, receives a `DECREASE_LOAD` adaptation decision — which is then folded verbatim into the next plan-generation prompt via `_format_adaptation_notes`. The coach would literally tell the model to reduce the load on a walk.
- `SetLog.weight` is a **non-nullable `FloatField`**. Logging a walk requires `weight=0`.
- `log_set()` in `session_service.py` computes `previous_best` and creates a `PersonalRecord` when `previous_best is None`. So the **first ever log of any zero-weight item creates a `PersonalRecord` of "Brisk Walk: 0.0kg x 30"**, which then appears on `/progress`. (Worth flagging separately: this first-log-always-a-PR behavior already affects any bodyweight exercise across all five goals, and general-fitness plans are bodyweight- and balance-heavy, so this goal will surface it constantly.)
- `total_volume` (`Σ weight × reps`, `progress/views.py`) counts it as 0, and the `/progress` bar chart plots 0.

**(b) Encode cardio as free-text in `PlannedExercise.notes` or the day name.** The plan becomes unloggable, uncountable, and unadaptable — it is a printed PDF inside a database. No weekly-minutes number can ever be computed, which means the central parameter of the entire goal is unverifiable.

**(c) Keep cardio out of the plan entirely and tell the user to "also walk 150 minutes."** This is the current de facto behavior and it is the thing the research most directly contradicts (§2.2: the combination is the intervention). It also means the app's plan and the app's progress screen are both silent about the majority of the user's prescribed weekly training time.

**Recommendation: extend `PlannedExercise` in place with a block-type discriminator plus nullable modality-specific fields, rather than creating a parallel `PlannedBlock` table.**

```
PlannedExercise  (conceptually: PlannedItem; no table rename needed)
  + block_type ∈ {resistance, cardio_steady, cardio_interval, mobility, balance, power, isometric}
                 default 'resistance'  ← every existing row is correct under this default
  + duration_seconds            (null)   steady cardio, mobility holds, balance holds, isometrics
  + intensity_kind ∈ {rpe, hr_pct_max, hr_pct_reserve, talk_test, pct_1rm, self_selected}  (null)
  + intensity_low / intensity_high  (null)   e.g. 64–76 with hr_pct_max; 4–6 with rpe (0–10)
  + interval_work_seconds / interval_rest_seconds / interval_rounds  (null)  → Norwegian 4×4 etc.
  + tempo_intent ∈ {controlled, maximal_concentric}  (null)  → §11.3 power training for ≥60
  + per_side (bool, default false)      → balance work is prescribed per side
  target_sets / target_reps_min / target_reps_max  → become nullable
```

**Why extend rather than add a parallel table:** the ordering, day membership, skip/replace flow, `ExerciseLog` linkage, and the session-execution UI all already key off `PlannedExercise`. A parallel table doubles every one of those code paths and forces an ordering merge across two tables inside a day. The cost of the discriminator approach is a table with legitimately-nullable columns per variant — a normal, acceptable trade for a small domain with 7 variants, and it means the migration is purely additive with a safe default.

**Correspondingly, `SetLog` must widen** (this is the part with real ripple effects):

```
SetLog
  weight  → nullable
  reps    → nullable
  + duration_seconds   (null)
  + distance_m         (null)
  + avg_hr / peak_hr   (null)
  + rpe                (null, 0–10)   ← the intensity currency when no HR device exists
```

Ripple effects to plan for, all of which are real work: `log_set()`'s PR logic must guard on `weight is not None` (and should be fixed so a first log is not automatically a PR); `progress/views.py`'s two `Σ weight × reps` aggregates must exclude non-resistance blocks; `evaluate_reps()` must skip non-`resistance` blocks entirely; and the workout-execution screen needs a timer/duration input mode alongside the weight×reps input mode.

**A `WorkoutDay` also needs a `day_type`** (`resistance | cardio | mixed | mobility_balance | rest`) so the plan UI and the session-execution screen can pick the right presentation before iterating items, and so the generator can be validated against "≥2 resistance days, ≥3 activity days."

**Separately — and this is the part that does *not* belong in the plan model at all — a new `ActivityLog`.** Most of a general-fitness user's weekly minutes will not come from a planned in-app session. §7.1 (the 10-minute-bout rule was removed), §7.2 (VILPA: 3 bouts/day of 1–2 min vigorous), §7.3 (post-meal walking, sitting breaks), and §1.3 (steps) all describe activity that is *countable toward the weekly target* but is not a `WorkoutSession` with a plan, exercises, and sets. Forcing a 12-minute walk through `WorkoutSession → ExerciseLog → SetLog` is three writes and a full session-execution UI for something that should be two taps.

```
ActivityLog (new, apps/workouts or a new apps/activity)
  (user, date, kind ∈ {walk, run, cycle, swim, row, hike, sport, other, steps, snack},
   duration_minutes (null), intensity ∈ {light, moderate, vigorous},
   distance_m (null), steps (null), avg_hr (null), rpe (null),
   source ∈ {manual, planned_session, healthkit, google_fit}, notes)
```

`source` matters: the weekly-minutes total must sum planned sessions *and* ad-hoc activity without double-counting, so completed cardio blocks inside a `WorkoutSession` should either project into `ActivityLog` rows with `source='planned_session'` or be unioned at read time. Recommend **computing the weekly total on read** initially (union query), and denormalizing only if it gets slow — same reasoning as the habits proposal's `ConsistencySnapshot`.

Finally, **`HealthMarker`** for the tracked outcomes (§6.4, §12.2):

```
HealthMarker (new, apps/progress)
  (user, measured_at, kind ∈ {resting_hr, systolic_bp, diastolic_bp, hrr1,
   chair_stand_30s, single_leg_stance_s, six_min_walk_m, rockport_time_s,
   step_test_recovery_hr, waist_cm, energy_1_10, sleep_quality_1_5},
   value, context (json: protocol/notes), source)
```

One generic table rather than columns-per-marker, because the marker set will change and because §6.4 explicitly ranks markers by signal-to-noise — the product should be able to add and retire them without migrations.

### 2.3 Explicitly out of scope

The findings contain substantial **nutrition** (§9) and **sleep** (§8) material. Consistent with `coach-integration-strategy.md` §7.7, this proposal does not propose a nutrition feature. Two narrow exceptions are worth flagging as cheap, high-value *coaching copy* rather than features: the ≥65 protein floor (**1.0–1.2 g/kg/day minimum, ~0.4 g/kg per meal** for anabolic resistance, §9.1) and the sodium/BP link for users who flag hypertension (§9.2). Both are one-line insights, not data models.

---

## 3. Onboarding vs. progressive collection

### 3.1 The decision rule for this goal

Inheriting and adapting the rule from the other proposals:

> Ask pre-signup **only** if the first plan's *dose* would otherwise be wrong by more than a factor of ~2, or if omitting it risks prescribing something contraindicated. Everything else defaults, and is corrected from logged behavior within 2–4 weeks.

Applying it:

**Must ask pre-plan (dose is undefined or unsafe without it):**
- **Current activity baseline.** Spans 60 → 300 min/week of correct starting dose and flips which component is the priority (§11.2). No default is defensible.
- **Cardio modality access.** Prescribing "30 min cycling" to someone without a bike, or "brisk walking outdoors" to someone who cannot, makes the plan unexecutable. The existing `equipment` field cannot answer this.
- **Health conditions.** Impact permission, low-impact-first gating, the isometric BP adjunct, and the T2D ≤2-consecutive-days rule are all condition-triggered, and two of them (osteoporosis spinal flexion, uncontrolled hypertension + Valsalva) are *safety* gates, not optimizations (§13.1, §13.2).

**Can default and refine (with the default stated honestly):**
- **Baseline CRF.** A lab VO2max test is out of the question; even a Rockport walk is a 15-minute homework assignment before the user has an account. Default: **estimate the band from age + sex + activity baseline**, and refine from a **submaximal self-assessment** (§4.4) asked as two taps on the same screen as the activity baseline. Then replace the estimate with a real measurement at the first milestone check-in (§5.3).
- **Resting HR, blood pressure, chair stand, single-leg stance.** Valuable, but post-signup. §12.3 is clear that nothing measurable changes in weeks 0–3 anyway, so a baseline captured in week 1 rather than at signup loses almost nothing.
- **Steps.** Inferred from a wearable if connected, otherwise a self-reported band at the first check-in. Not worth a pre-plan screen — §1.3's value is that steps are *passively measurable*, and asking someone to estimate them defeats the point.
- **Actual vs. stated session length, adherence, which days land, modality preference (from skip/replace behavior), post-session affect.** All already inferable from data the app generates, per the habits proposal §4.4.

### 3.2 Proposed onboarding additions — 2 net-new conditional screens

Shown **only when `goal == improve_fitness`**, immediately after the goal branch point. As `strength-integration-strategy.md` §3.3 notes, conditional branching requires converting `onboarding_flow_screen.dart`'s flat `switch (_step)` with `const _stepCount = 12` into a computed `List<OnboardingStep>` built from the draft's goal — a prerequisite refactor shared across all goals, worth doing once.

| # | Screen | Type | Rationale (research anchor) | Unlocks |
|---|---|---|---|---|
| **G1** | **"Where are you starting from?"** — (a) *"In a typical week right now, how much brisk activity do you get — enough to raise your breathing?"* → `none / <1 h / 1–2 h / 2–4 h / 4+ h`; (b) *"Two flights of stairs at a normal pace leaves you…"* → `fine / slightly out of breath / needing a pause`; (c) *"Could you walk 30 minutes briskly without stopping today?"* → `yes / probably / no` | 3 taps, one screen | (a) is **the single highest-value question in this proposal**: §1.4 + §11.2 make the correct starting dose range from 60–90 min/wk (complete beginner, build to 150 over 6–12 wk) to 300+ (already active, where the priority shifts to adding resistance or vigorous work). (b)+(c) are the submaximal CRF proxy — §12.1 lists everyday breathlessness on stairs as a real, trackable marker (~1–2 Borg points at the same flight count in 3–6 weeks), so this doubles as a **baseline for a marker the user will actually notice improving** | Starting weekly minutes, progression rate, whether vigorous work appears in block 1, expectation-setting copy, first-marker baseline |
| **G2** | **"What can you actually do for cardio?"** — multi-select: `walk outdoors / treadmill / stationary bike or spin / outdoor bike / rowing machine / elliptical / pool / stairs / none of these` | multi-select, one screen | §13.2 (obesity/high BMI → non-weight-bearing first; joint loading in running ~2.5–3× BW/step), §4.2 (cycling/rowing interfere least with lower-body strength), §10.1 (novice runners 17–33 injuries/1,000 h — run/walk intervals for 4–8 weeks). Without this the generator either guesses or prescribes the modality with the highest injury risk to the least-prepared population. "Stairs" specifically unlocks the §7.3 stair-snack protocols (3 × 20 s, 3×/wk → +5% VO2peak) which are the best-evidenced zero-equipment option | Modality selection, impact gating, interval-protocol feasibility, snack prescriptions |

**Not a new screen — an addition to an existing one.** The `coach-integration-strategy.md` §3.2 screen 7 ("Limitations", a structured region checklist replacing free-text `injuries`) should gain a **health-conditions section shown for all goals but expanded for this one**: `high blood pressure / type 2 diabetes or prediabetes / heart condition or cardiac event / osteoporosis or low bone density / joint arthritis (knee, hip, back) / pregnant or postpartum / recent fall (shown if age ≥60) / none of these`, plus a non-negotiable clearance note. Rationale: §13 opens by stating that unstable cardiac disease, uncontrolled hypertension (≥180/110), recent surgery, or new/undiagnosed symptoms warrant clinical clearance, and this is universal ACSM/AHA guidance. Every other goal benefits from this too; this goal *requires* it.

**Screen-count arithmetic, honestly:**

| Flow | Count |
|---|---|
| Today, all goals | 12 |
| Under `coach-integration-strategy.md` pruning (drops `motivation`, `coach_personality`, `training_style`, `training_environment`; adds strength anchors, sleep, summary) | 11 |
| `improve_fitness` path: 11 − `priority_muscles` (meaningless here, §1.2) − strength anchors (not needed; ±10–15% load precision is fine per §2.4, so bodyweight-seeded loads are sufficient) + G1 + G2 | **11** |

So the `improve_fitness` flow lands at **11 screens — the same as the shared flow**, because two questions that carry no weight for this goal are dropped in exchange for the two that do. That is a favorable trade and worth stating clearly: this proposal does not add onboarding friction for these users.

### 3.3 Progressive collection plan

| Data point | Mechanism | When | Feeds |
|---|---|---|---|
| **Weekly MVPA minutes actually accumulated** | Union of completed cardio blocks + `ActivityLog` | Continuous | The primary progress metric; the input to every adaptation rule in §5 |
| **Ad-hoc activity** | 2-tap `ActivityLog` quick-add (kind, minutes, intensity) on the home screen | Ad hoc | Weekly total; reveals modality preference |
| **Steps** | HealthKit / Google Fit if the user connects; otherwise a weekly self-reported band | Passive, opt-in | §1.3 targets (6–8k ≥60, 8–10k <60); also the best "you're already doing more than you think" retention message for sedentary users |
| **Session RPE and per-block RPE** | One 0–10 tap; for cardio blocks this is the intensity currency when no HR data exists | Every session | Verifies prescribed intensity was hit (§1.1: moderate = RPE 4–6/10, vigorous = 7–8/10); drives interval progression |
| **Submaximal HR at fixed workload** | If the user has a wearable: HR during a repeated cardio block at the same prescribed pace/resistance. Otherwise the standardized step test at check-in | Continuous / 8–12-weekly | §6.4 ranks this the **most sensitive early fitness marker** (−5 to −15 bpm in 4–8 weeks) and calls it underrated. It is the single best "it's working" signal available in weeks 3–8 |
| **Resting HR** | Wearable overnight minimum, or manual first-morning entry; **7-day rolling average only** | Weekly | §6.1: −3 to −7 bpm at 8–12 weeks, but confounded by alcohol (+3–10), sleep (+2–8), illness (+5–15). Must never be shown as a daily number |
| **Home BP** | Manual, monthly, with protocol prompt (seated, 5 min rest, 2–3 readings averaged) | Monthly | §6.4 ranks it #1 for clinical validity; meaningful change ≥5 mmHg sustained 2+ weeks |
| **Field tests** (30-s chair stand, single-leg stance, 6MWT or Rockport) | Guided in-app protocol at milestone check-in | Every **8–12 weeks** | §12.3: "retest cadence of every 8–12 weeks matches the signal rate; retesting more often mostly measures noise." This is a rule the product should enforce, not just suggest |
| **Energy / sleep quality 1–10** | One tap on the weekly check-in | Weekly | §12.1: energy detectable at 3–6 weeks (~0.4–0.6 SD), sleep at 2–4 weeks — both **before** any fitness test moves. These carry the weeks 3–8 narrative |
| **Post-session affect** | One optional tap on the existing `/workout/:sessionId/reflection` screen | Every session | §12.1: mood improves **after session 1** (+1–2 points on a 10-point scale). §10.4: affective response during exercise predicts 6–12-month adherence better than intentions or knowledge. Shared with the habits proposal — build once |
| **Modality preference** | Inferred from `ExerciseLog.replaced_with_name` / skip behavior on cardio blocks | Continuous | §10.4: variety (2–4 rotating modalities) modestly improves adherence; a consistently-skipped modality should stop being prescribed |

**Design constraint, inherited:** never more than one new question per session, never before the workout is complete, always dismissible.

---

## 4. From qualitative labels to real numbers

### 4.1 Where this lives

Same architecture as the other proposals — `compute_prescription(profile, training_state)` dispatching on `profile.goal` to a strategy. This adds `GeneralFitnessStrategy`. What is genuinely shared and what genuinely diverges:

| Component | Shared | General-fitness-specific |
|---|---|---|
| Age/sex modifiers, equipment→increment rounding, limitation→substitution ladder, session time-budget arithmetic, validator contract | **Shared** | — |
| e1RM / `StrengthEstimate` | **Shared but low-priority** — §2.4: ±10–15% load precision is fine, so bodyweight-seeded loads are adequate and the onboarding anchor screen can be skipped for this goal | — |
| `SetLog.rir` | **Shared** | Target band is a flat **2–4 RIR**; the RIR-tightening logic of the hypertrophy strategy does not apply |
| Adaptation plumbing (`AdaptationHistory`, finish/feedback hooks) | **Shared** | New rule set (§5), new `Decision` values |
| `ScheduledSession` (habits proposal §7.1) | **Shared** — the completion-rate denominator | Denominator here is *weekly minutes*, not just sessions |
| **Organizing unit** | — | **Diverges fundamentally.** Hypertrophy: sets per muscle. Strength: sets per lift. **General fitness: minutes per week per intensity band, allocated across modalities.** This is why a new strategy is needed rather than a parameter tweak |
| **Balance / power / isometric blocks** | — | **Unique to this goal** (balance is age-gated; power appears at ≥60; isometric is a hypertension adjunct) |
| **Progress metric** | — | **Diverges.** Not volume, not e1RM — weekly minutes, marker trends, functional tests |

### 4.2 Activity baseline → weekly targets

The primary table. `G1a` is the key; everything downstream keys off it.

| G1a answer | Assumed current MVPA | Block-1 weekly target (moderate-equivalent) | 12-week target | Vigorous sessions in block 1 | Resistance | Progression |
|---|---|---|---|---|---|---|
| **None** | ~0 min | **60–75 min/wk** (§1.4 floor), in 10–20 min bouts, 3 d/wk | 150 min | **0** — self-selected intensity only | 2 × 20 min, 1–2 sets × 8–15, RIR 3–5 | +5–10%/wk, consolidation week every 3–4 wk |
| **<1 h** | ~30 min | **90 min/wk**, 3 d/wk | 150–200 min | 0 in wk 1–4, then 1 | 2 × 20–25 min | +5–10%/wk |
| **1–2 h** | ~90 min | **120–150 min/wk**, 3–4 d/wk | 200–250 min | 1 | 2 × 25–30 min | +5–10%/wk |
| **2–4 h** | ~180 min | **180–210 min/wk**, 3–5 d/wk | 250–300 min | 1–2 | 2–3 × 30 min | +5%/wk, then hold |
| **4+ h** | 240+ min | **hold current volume** | 300 min | 1–2 | **2–3 × 30 min — this is the priority addition** | Hold aerobic; add the missing component |

Two research points encoded here that are easy to get wrong:

1. **Vigorous work is deliberately absent from block 1 for sedentary users.** §1.4 calls 1–2 vigorous sessions/week "the highest-leverage single addition for VO2max," and §3.3 shows SIT producing +12–19% VO2max in 6–12 weeks — but §3.3 also flags HIIT's higher free-living dropout (~15–20% vs. ~10%), and §10.4 gives self-selected intensity a **10–20 percentage point adherence advantage** in sedentary populations. The defensible synthesis (§3.3, Moderate confidence) is *1–2 vigorous sessions embedded in a mostly-moderate base* — with the base established first.
2. **For the "4+ h" user the correct answer is mostly to add resistance training, not more cardio.** §11.2: ~30–35% of adults meet aerobic guidelines but only ~24–30% meet both; the ordered list of highest-yield additions is (1) resistance if absent, (2) 1–2 vigorous sessions, (3) balance if ≥50, (4) non-exercise activity. This is a case where the app's most valuable output is *not adding volume*, and the coaching copy should say so.

### 4.3 Age → balance, power, rep range, bone loading

Directly from §5.2, §11.3, §2.1:

| Age band | Balance | Power (max concentric intent) | Resistance reps | Static hold duration | Extra |
|---|---|---|---|---|---|
| <40 | 5 min/wk, incidental (single-leg work folded into lifting) | — | 8–15 | 10–30 s | — |
| 40–59 | 5–10 min, 2×/wk | "begins to earn its place": 30–60% 1RM, 3–6 reps, 2–3 sets | 8–15 | 10–30 s | ≥80% 1RM or impact 1–2×/wk for bone; **from ~45 for women this becomes a priority** (§11.1) |
| 60–69 | **10–20 min, 3×/wk**, progressively challenging | **2×/wk, 3 × 6–10 @ 40–60% 1RM** | **10–15** | **30–60 s** | 50–80% 1RM, start low; steps target drops to 6–8k |
| 70–79 | **20–30 min, 3×/wk** | 2×/wk | 10–15 | 30–60 s | 48–72 h between hard same-pattern sessions |
| 80+ | **30 min, 3×/wk (Otago-style)** — co-equal with resistance | 2×/wk | 10–15, chair-based options legitimate | 30–60 s | **Priority order reverses: balance ≥ resistance > aerobic volume**; supervised start warranted |

§5.2's mechanism note must survive into the prompt: **balance training done at a comfortable level produces little benefit** — progression means reducing base of support, removing hand support, adding head turns/dual tasks, unstable surfaces, closed eyes. A static "stand on one leg for 30 s" prescribed unchanged for 12 weeks is a null intervention.

Also from §5.3, and important for the time budget: balance work should be **folded into resistance sessions** (single-leg RDL, split squats, step-ups, farmer's carries are simultaneously resistance and balance stimuli) and mobility into warm-up/cool-down. Total added time ~15 min/session with **no reduction in cardio or resistance minutes**. §5.1 is blunt that mobility work must not displace the main dose — ROM improves reliably (+5–20% in 4–8 weeks) but stretching shows **~0% injury reduction** (§10.2), so it is justified for comfort and function, not for health outcomes or injury prevention.

### 4.4 Submaximal self-assessment → CRF band

No lab test, no pre-signup homework. G1b + G1c map to a coarse band used only for expectation-setting copy and the choice of first field test:

| G1b + G1c | CRF band | First field test offered at check-in 1 | Expected 12-week change to communicate |
|---|---|---|---|
| Stairs: needing a pause / walk 30 min: no | Low | **30-s chair stand** + fixed 6-min walk | §3.2: +15–20% VO2max in 8–12 wk; §12.1: 6MWT +30–60 m, chair stand +2–4 reps. Largest absolute gains in the population — §3.1: low → below-average fitness ≈ 50% mortality risk reduction |
| Stairs: slightly out of breath / walk 30 min: probably | Moderate | 3-min step test (YMCA) or fixed-route walk with HR | §3.2: +10–20%; §12.1: submaximal HR −5 to −15 bpm at 4–8 wk |
| Stairs: fine / walk 30 min: yes | Above-average | Rockport 1-mile walk | §11.2: further gains smaller (+5–10% over 12–24 wk); frame progress around **process metrics and functional markers**, not test deltas |

### 4.5 Time budget → session composition

Given `training_days` D and session minutes M, weekly budget = D × M. Allocation order (resistance first, because §2.2's 30–60 min/week is a narrow band with a J-shaped curve, whereas cardio has a wide plateau):

1. **Reserve 2 resistance sessions** of `min(M, 30)` minutes → 40–60 min/wk. (3rd session only if D ≥ 4 *and* baseline is "2–4 h" or "4+ h".)
2. **Fold in mobility (5–10 min dynamic warm-up / static cool-down) and balance (per the age table) inside those sessions** — §5.3, no separate time cost.
3. **Allocate the remainder to cardio**, split into the prescribed number of sessions of 20–60 min each.
4. **If the remainder is below the target**, prescribe the shortfall as `ActivityLog`-tracked accumulation: daily steps, post-meal walks (2–5 min within 60–90 min of eating, §7.3, −17–30% postprandial glucose AUC), sitting breaks (3 min per 30 min), and 3–5 daily 1–3 min vigorous snacks (§7.2 VILPA). This is the mechanism that makes a 3 × 45 min plan reach 150 min/week without inventing a fourth session — and §7.1 confirms it counts, since the ≥10-minute-bout rule was removed in 2018.

Templates directly from §4.3, used as validation targets:

| Weekly budget | Template |
|---|---|
| ~90 min (floor) | 2 × 30 min full-body resistance + 1 × 25–30 min brisk walk + daily steps |
| ~150 min (recommended) | 2 × 35 min resistance + 2 × 30 min moderate cardio + 1 × 20 min vigorous/interval |
| ~200–240 min (optimal) | 3 × 40 min resistance + 2 × 30 min moderate + 1 × 25 min vigorous + 10 min/day mobility |
| Absolute minimum "still worth it" | 2 × 20 min resistance + 7,000 steps/day |

Hard caps applied last: **≤4 planned sessions/week** and **≤60 min/session** for this goal (§4.3: dropout rises above 4–5 sessions; duration >60 min is a stronger dropout predictor than frequency). If the user selected 5 or 6 `training_days`, the correct response is to prescribe 4 sessions plus accumulation targets and say why — not to fill the extra days.

### 4.6 Health conditions → constraints

| Condition | Constraint |
|---|---|
| **Hypertension** | Add isometric adjunct: **4 × 2 min at 30–40% MVC (wall squat or handgrip), 3×/wk** (§6.3, −8.24/−4.00 mmHg, the top-ranked modality). Avoid Valsalva-heavy maximal lifting if uncontrolled. Expect −5 to −9 mmHg, ~2× the normotensive effect. Surface home BP as the headline marker |
| **T2D / prediabetes** | **No more than 2 consecutive days without activity** — a scheduling constraint (§13.2, ADA). Prioritize post-meal walking (§7.3). Target 150 min aerobic + 2–3×/wk resistance; expect HbA1c −0.5 to −0.7 pp |
| **Osteoporosis / low BMD** | Exclude loaded spinal flexion and rapid loaded trunk rotation. Include progressive resistance and impact **where safe** and balance training. Note LIFTMOR was supervised (§2.3) — an unsupervised app should prescribe the loading principle, not the 5×5 @ >85% protocol |
| **Knee/hip OA or joint pain** | Exercise is first-line (SMD ~0.5 for pain and function, comparable to NSAIDs). Low-impact cardio; land-based ≈ aquatic; 2–3×/wk for ≥12 weeks. Pain-guided loading: ≤5/10 settling within 24 h and not worsening week to week is acceptable (§13.1) |
| **High BMI** | Non-weight-bearing or low-impact first (cycle, swim, elliptical, row); build toward 200–300 min/wk |
| **Recent fall (≥60)** | Escalate to the Otago-style prescription regardless of the age band (§5.2, ~35% fall reduction in ≥80s or those with prior falls); flag that unsupervised high-challenge balance work carries genuine in-training fall risk |
| **Cardiac history** | Clearance gate. If proceeding: 3×/wk, 20–60 min at 40–80% HRR / RPE 11–14 (§13.2). No vigorous/interval prescription without clearance |
| **Pregnancy/postpartum** | 150 min/wk moderate across ≥3 days; avoid supine-heavy positions after ~16 weeks and fall-risk activities; resistance training safe and encouraged |

### 4.7 Proof: two `improve_fitness` users with identical current answers

Both answer today: goal `improve_fitness`, experience `beginner`, 3 days/week, 45 min, limited equipment. Today they get the same prompt and, predictably, near-identical lifting splits.

| | User A | User B |
|---|---|---|
| Inputs (new) | M, 34, 88 kg. Activity: none. Stairs: needs a pause. Cardio access: walk outdoors, stairs. No conditions | F, 67, 63 kg. Activity: 1–2 h. Stairs: slightly out of breath. Cardio access: stationary bike, pool. High BP, knee OA |
| Weekly cardio target, block 1 | **60–75 min**, 3 × 20–25 min, self-selected/moderate | **120–150 min**, 3 × 30 min + 1 × 20 min |
| Vigorous work | **None in block 1.** Introduced wk 5+ if adherence ≥80% | 1 × 20 min interval **on the bike**, added wk 3 (already active) |
| Modality | Brisk walking; stair snacks 3 × 20 s, 3×/wk (§7.3) | **Cycling and pool only** — knee OA + low-impact gating |
| Resistance | 2 × 20 min, 6–8 compounds, 1–2 sets × 8–15, RIR 3–5 | 2 × 25 min, 1–3 sets × **10–15** @ 50–70% 1RM, RIR 2–4 |
| Power work | None | **2×/wk, 3 × 6–10 @ 40–60%, maximal concentric intent** (§11.3, ≥60) |
| Balance | 5 min/wk incidental (single-leg RDL folded into lifting) | **10–20 min, 3×/wk, progressive** — folded into resistance sessions + a standalone block |
| Bone loading | Not emphasized | Emphasized (§11.1, postmenopausal), impact **omitted** pending OA/BMD context; loading via resistance |
| Special protocol | — | **Isometric wall squat 4 × 2 min @ 30–40% MVC, 3×/wk** (§6.3) |
| Steps target | 8,000–10,000/day | 6,000–8,000/day |
| Headline marker | Stair breathlessness + submaximal HR at fixed pace | **Home BP (monthly)** + 30-s chair stand + single-leg stance |
| 12-week expectation copy | "+15–20% cardio fitness; stairs noticeably easier by week 4–6" | "−5 to −9 mmHg systolic by week 8–12; +2–4 chair stands by week 12" |
| Session count | 3 planned + accumulation targets | 4 planned |

These are different programs. Today they are one program with a different word in the prompt — and neither of them contains any cardio at all.

---

## 5. Adaptation and progress for this goal

### 5.1 Does the existing engine apply? Mostly not.

`evaluate_reps()` is the wrong axis for this goal, for reasons stated directly in the research rather than as a matter of taste:

- §2.4: **load precision of ±10–15% is fine**, progression is "add reps/load when RIR drifts to 4+," and periodization/deloads are "not needed." The engine's premise — that missing or exceeding a rep target is a meaningful signal warranting a load change — assumes a precision this goal explicitly does not require.
- The current rule fires `DECREASE_LOAD` after `failed >= 2` within a **single session**. `coach-integration-strategy.md` §5.1 already establishes this is wrong for hypertrophy (the marker requires two *consecutive exposures*); for a general-fitness user training 2×/week at RIR 2–4, it is close to pure noise, and its effect is to systematically under-load a population whose main risk is doing too little.
- It cannot fire at all on cardio, balance, or mobility blocks — which under this proposal are the majority of the plan.

**Recommendation:** keep the shared engine, but for `goal == improve_fitness`, (a) restrict `evaluate_reps` to `block_type == 'resistance'` items only, (b) require two consecutive exposures before any `DECREASE_LOAD`, and (c) treat `INCREASE_LOAD` as the double-progression trigger (top of the rep range on all sets), which is a genuine and welcome signal here. Load progression is not *wrong* for this goal — it is just not the primary axis, and it should be low-sensitivity.

`evaluate_feedback()` has an additional problem inherited from the shared code: it queries the last 3 `WorkoutFeedback` rows with **no time window**, so three "hard" sessions spread over months trigger a volume cut. For a user training 2–3×/week that window can span six weeks.

### 5.2 Proposed rule set

| Rule | Trigger | Action | Reference |
|---|---|---|---|
| **F1 — Cardio volume progression** | Weekly MVPA target met (≥90% of prescribed minutes) for the week | **+5–10% weekly minutes**, with a **non-progressing consolidation week every 3–4 weeks** | §10.1 |
| **F2 — Volume ceiling** | Weekly minutes reach the 12-week target for the user's band | Stop progressing volume; shift the lever to intensity or variety | §1.2: the curve flattens between 300 and 600 min/wk; ~50% of achievable benefit is captured by ~75 min/wk |
| **F3 — Vigorous introduction** | ≥4 consecutive weeks at ≥80% adherence, no condition contraindication, no unresolved pain flag | Convert **one** moderate session to a vigorous/interval session (4×4, 10-20-30, or short intervals per §3.3), at the low end of the protocol | §1.4, §3.3, §10.4 (base-first ordering to protect adherence) |
| **F4 — Intensity progression within intervals** | Interval session completed at prescribed RPE/HR for 2–3 exposures | Add one interval round, or raise the work interval toward the top of the band — **one variable at a time** | §3.3, §10.1 |
| **F5 — Submaximal-HR improvement detected** | HR at the same prescribed cardio workload drops ≥5 bpm across a 2–4 week window | **Increase the prescribed workload** (pace/resistance/incline) to hold the intensity band; surface it to the user as the headline "it's working" signal | §6.4 (most sensitive early marker), §12.1 (−5 to −15 bpm at 2–4 wk) |
| **F6 — Adherence-driven dose reduction** | Weekly minutes <60–70% of prescribed for 2 consecutive weeks | **The prescription is wrong, not the user.** Reduce toward the 60–75 min/wk floor and re-offer; do not reduce below the floor. Consider converting a session into accumulation targets | §1.4 (floor), §10.4 (~50% drop out within 6 months), mirrors R7 in the hypertrophy proposal |
| **F7 — Session-count guard** | Prescribed sessions would exceed 4/week, or session length would exceed 60 min | Cap and reallocate to accumulation/steps | §4.3 |
| **F8 — Balance progression** | Balance block completed comfortably for 2–3 exposures (user reports "easy" or holds the full duration without support) | Progress the **challenge**, not the duration: narrow base → remove hand support → add head turns/dual task → compliant surface → eyes closed | §5.2 — comfortable balance work produces little benefit |
| **F9 — Detraining / return** | ≥2 weeks with no logged activity | Restart at **50–60% of previously tolerated volume**, rebuild over 4–6 weeks. Explicitly cap enthusiasm in weeks 1–3 | §10.1, §11.2. Note §10.4: a single missed session has **no measurable physiological consequence**, and 1 session/wk or 1/3 volume maintains strength for months — so F9 must not fire on small gaps, and the copy should say so |
| **F10 — Pain / soreness** | Pain >5/10 during loading, or not back to baseline within 24 h, or rising week over week | Regress volume ~50%, **hold frequency constant**; modify the movement rather than delete the pattern | §13.1 |
| **F11 — Variety rotation** | Same cardio modality for 6+ weeks, or a modality skipped/replaced ≥3 times | Offer an alternative from the user's G2 access list | §10.4 (variety modestly improves adherence and reduces single-tissue overuse) — **Low–Moderate confidence, and should be framed as an offer, not an imposition** |
| **F12 — Milestone check-in** | Every **8–12 weeks** | Prompt the field-test retest set + BP; regenerate the plan against updated markers and a re-asked activity baseline | §12.3: retesting more often mostly measures noise |

New `AdaptationHistory.Decision` values needed: `increase_cardio_volume`, `hold_cardio_volume`, `add_vigorous_session`, `progress_interval`, `increase_cardio_workload`, `reduce_prescribed_dose`, `progress_balance_challenge`, `rotate_modality`, `restart_reduced`.

### 5.3 Progress tracking — what to show, and when

The critical framing problem, stated by the research itself (§12): **this goal has no headline number.** No scale weight, no 1RM. §12.3 identifies two distinct dropout points caused by the mismatch between physiological change and subjective awareness. The progress screen has to be built around the *timeline*, not around a single metric.

Today `/progress` for this user would show: streak (works), total workouts (works), **total volume = ~0** and an **empty bar chart** (both structurally broken, since `Σ weight × reps` over a correct general-fitness plan is near zero), and **no personal records** (or, worse, spurious 0 kg PRs per §2.2).

Proposed, by phase:

| Weeks | Primary display | Rationale |
|---|---|---|
| **0–3** | **Process metrics only**: weekly minutes vs. target (a ring), sessions completed, steps, current streak. Plus elicited post-session mood ("how do you feel compared to before?") | §12.3: almost nothing measurable changes except mood and post-session affect. §12.1: mood improves after session 1 (+1–2 points). §10.4: self-monitoring + one other self-regulatory technique has the largest behavior-change effect sizes (High confidence) |
| **3–8** | Add **submaximal HR at fixed effort** (−5 to −15 bpm), **stairs/breathlessness self-report**, **energy and sleep 1–10 trends** | §12.3: "the first credible 'it's working' signals, and should be surfaced deliberately, because a scale and a 1RM will both be flat" |
| **8–16** | Add **field tests** (30-s chair stand +2–4 reps, 6MWT +30–60 m, single-leg stance +5–15 s), **home BP** (−4 to −9 mmHg), **RHR 7-day average** (−3 to −7 bpm), waist circumference | §12.1 timeline table |
| **Ongoing** | Cumulative minutes; "you have accumulated X hours since starting" | §1.2: effect sizes are far larger at the low end — a previously sedentary user reaching 75 min/wk has captured ~half the achievable mortality benefit, and telling them so is both true and motivating |

Two display rules worth encoding:
- **RHR is a weekly/monthly trend metric and a poor daily metric** (§6.1: confounded by alcohol +3–10, sleep +2–8, illness +5–15 bpm). Never show a daily number; always a 7-day rolling average with a noise band.
- **Show measurement error explicitly** on field tests (+2 chair stands exceeds measurement error; 6MWT MCID ~30 m). A user who improves by 1 chair stand should not be told they improved.

`total_volume` should not be shown for this goal at all. It is not a bug to fix; it is a metric that does not apply.

---

## 6. Architecture implications

Proposal level. No implementation here.

### 6.1 Data model

**`apps/onboarding` — `OnboardingProfile`:**
- `activity_baseline` (choices: none/<1h/1-2h/2-4h/4h+) — **the highest-value new field**
- `stairs_response`, `can_walk_30min` (small choice fields) — CRF proxy
- `cardio_access` (JSON list) — walk_outdoors, treadmill, stationary_bike, outdoor_bike, rower, elliptical, pool, stairs
- `health_conditions` (JSON list) — shared across goals; extends the structured-limitations screen already proposed
- All nullable, all conditional; existing rows and the other four goals are unaffected.
- Also worth revisiting for this goal: `training_days` max of 6 (§4.3 caps the useful value at 4–5), and `priority_muscles`'s frontend-required constraint.

**`apps/workouts` — `PlannedExercise`, `WorkoutDay`, `SetLog`:** the block-type discriminator and nullable duration/intensity fields set out in §2.2. Purely additive with `block_type` defaulting to `resistance`, so every existing row is correct and no backfill is needed.

**New — `ActivityLog`** (§2.2). The non-session activity record. Note this is genuinely new surface area with no analogue in the other four proposals.

**New — `HealthMarker`** (§2.2). Generic `(kind, value, measured_at, context)`.

**New — `MilestoneCheckIn`** (or a `kind` on the habits proposal's check-in): `(user, taken_at, prompted_tests, results FK→HealthMarker, activity_baseline_reasked, next_due_at)`. The 8–12-week cadence needs somewhere to live, and F12 needs a `next_due_at` to fire against.

**Shared with the habits proposal:** `ScheduledSession` and the background job runner. Both proposals need scheduled-vs-actual, and this goal needs a weekly rollup job to compute minutes-vs-target and fire F1/F6. Build once.

**Bugs/gaps to fix regardless of this proposal:**
- `log_set()` creates a `PersonalRecord` whenever `previous_best is None` — so the first log of any exercise is a PR, including at `weight=0`. Affects all goals; will be highly visible here.
- `WorkoutSession.Status.ABANDONED` is declared but never written (already flagged in the habits proposal).
- `_to_display_shape()` and `persist()` both default `rest_seconds` to 90 (already flagged in the hypertrophy proposal).

### 6.2 Prompt restructuring for this goal

The current prompt's opening line — "You are an expert strength and conditioning coach designing a personalized workout program… Design a training split with exactly N training days" — is wrong for this goal in both role and task. The restructured version, gated on `goal == improve_fitness`:

1. **Role reframe.** "You are an exercise physiologist designing a general health and fitness program combining cardiovascular training, resistance training, and mobility/balance work."
2. **Computed weekly budget as hard constraints** (non-negotiable, emitted by `GeneralFitnessStrategy`): weekly moderate-equivalent minutes and their split by intensity band; number and length of cardio sessions; number of vigorous/interval sessions and which protocol; resistance sessions, minutes, sets/exercise, rep range, RIR, load band; balance minutes and frequency; mobility placement; power-work inclusion and parameters; permitted cardio modalities; banned movements from conditions/limitations; the daily steps target and accumulation targets.
3. **Selection guidance delegated to the model:** which specific cardio modality per session from the permitted list, 6–8 compound resistance movements covering **all** major muscle groups (§2.1 — not priority muscles), which balance drills at the appropriate progression level, folding balance into resistance sessions where the movement does double duty (§5.3), and day sequencing honoring ≥6 h separation or separate days for hard cardio + heavy lower-body work (§4.2) and the ≤2-consecutive-days-off rule if T2D is flagged.
4. **Extended output schema** carrying `block_type`, `duration_seconds`, `intensity_kind`, `intensity_low/high`, the interval fields, `tempo_intent`, and `per_side` — mirrored through `_SCHEMA_INSTRUCTIONS`, `_to_display_shape()`, `_validate_display_shape()`, and the `PlannedExercise` write in `persist()`.

Design intent, same as the other proposals: **the model chooses modalities, movements, and ordering; it never chooses the dose.**

### 6.3 Post-generation validation

`_validate_display_shape()` currently only checks that required keys exist. For this goal it must additionally recompute from the returned plan and reject/repair on:
- total weekly moderate-equivalent minutes within the computed band (using the 1 min vigorous = 2 min moderate conversion, §1.1)
- ≥2 resistance sessions, and total weekly resistance time within **30–60 min** (§2.2 — the plan should be rejected for *too much* resistance work, which is the failure mode a strength-coach-flavored model will produce)
- resistance movements cover all major muscle groups (legs, hips, back, chest, abdomen, shoulders, arms)
- cardio sessions spread over ≥3 days (§1.1)
- balance minutes match the age band; power blocks present if age ≥60
- no banned modality (impact for osteoporosis; weight-bearing for high-BMI block 1; vigorous for uncleared cardiac)
- ≤4 sessions/week, ≤60 min/session

On failure: one repair round-trip naming the specific violations, then a deterministic template fallback from the §4.5 table. Without this, everything upstream is a suggestion.

### 6.4 Frontend

| Surface | Change |
|---|---|
| `onboarding_flow_screen.dart` | Flat `switch (_step)` + `const _stepCount = 12` → a computed step list keyed on goal (shared prerequisite with the strength proposal). Add G1, G2; skip `priority_muscles` for this goal; extend the limitations screen with health conditions |
| **Workout execution** (`/workout/:sessionId`) | **Genuinely new UI**: a timer/duration mode for cardio, mobility, balance, and isometric blocks alongside the existing weight×reps input; an interval runner (work/rest/rounds) for `cardio_interval`; per-side handling for balance |
| **Plan detail** (`/plan`) | Must render four block types with different shapes, not a uniform exercise list |
| **Home** | A 2-tap `ActivityLog` quick-add ("logged a 25-minute walk") — the single most-used surface for this goal |
| `progress_screen.dart` | Replace the `total_volume` tile and volume bar chart for this goal with a weekly-minutes ring, marker trend charts, and the phase-appropriate metric set (§5.3). `ProgressSummaryView`, `progress_models.dart`, and the serializer change together |
| **Milestone check-in** | New guided flow: protocol instructions for chair stand / single-leg stance / 6MWT / step test, entry fields, before-after comparison with a measurement-error band |
| **Health marker entry** | Manual RHR/BP entry with protocol prompts; optional HealthKit/Google Fit connection for RHR and steps (**does not exist in the repo today** — new dependency and platform permissions work) |
| `insight_generator.py` | Goal-conditional copy rules: no physique framing; lead with process metrics in weeks 0–3; use the §12.1 timeline to set expectations ahead of each signal rather than after; explicit "this is training-science guidance, not medical advice" framing wherever conditions are involved |

### 6.5 Suggested sequencing

- **Phase 1 — model + prescription (unblocks everything).** `block_type` + nullable fields on `PlannedExercise`/`SetLog`; `WorkoutDay.day_type`; `GeneralFitnessStrategy`; restructured prompt + validator. At this point plans are *correct* but partially unloggable.
- **Phase 2 — onboarding.** G1, G2, health conditions; computed step list; drop `priority_muscles` for this goal. Plans become individualized rather than defaulted.
- **Phase 3 — logging.** Timer/interval execution UI; `ActivityLog` + quick-add; fix the PR-on-first-log and volume-aggregate issues. Plans become executable and countable.
- **Phase 4 — progress and markers.** `HealthMarker`, milestone check-ins, progress screen rework, optional HealthKit/Google Fit.
- **Phase 5 — adaptation.** F1–F12 against the weekly rollup; new `Decision` values; desensitize `evaluate_reps` for this goal.

Phases 1–2 alone deliver a defensible, individualized *prescription*. Phase 3 is what makes it a coached program rather than a document. **Shipping Phase 1 without Phase 3 leaves users with a plan containing blocks they cannot log — arguably worse than today's honest-but-wrong lifting split.** They should be planned as one release.

---

## 7. What should NOT change for this goal

Being explicit, because the temptation is to build a parallel `improve_fitness` pipeline:

1. **The prescription-layer architecture.** `compute_prescription` + strategy dispatch, exactly as the hypertrophy and strength proposals define it. New strategy, not a new system.
2. **The anonymous preview → save-preview flow.** `GeneralFitnessStrategy` runs fine on an unsaved `OnboardingProfile` with empty training state. The extended schema round-trips through `save-preview` unchanged in mechanism (with the same re-validation caveat the hypertrophy proposal raises).
3. **The AI provider interface.** Untouched.
4. **Streaks, adherence, `ScheduledSession`, notifications.** Shared with the habits proposal; this goal is a consumer, not an owner.
5. **The resistance-training science itself.** A general-fitness user doing squats, rows, and presses is doing the right movements — just fewer sets, further from failure, covering everything rather than specializing.
6. **PR detection.** Keep it (with the first-log bug fixed) — §12.1 lists strength/everyday-carrying gains at 4–8 weeks (+20–40% in beginners) as a real, noticeable signal. Just do not make it the headline.
7. **Free-text `injuries`.** Keep alongside the structured fields; the long tail is real and the free text is still useful prompt context.

---

## 8. Tradeoffs, stated explicitly

### 8.1 The scope tradeoff — the big one

The other four goals reuse the resistance-training chassis. This one requires widening it: a discriminated plan-item model, a widened `SetLog`, two new models (`ActivityLog`, `HealthMarker`), a new in-session timer/interval UI, a new progress surface, and — for the passive markers that make this goal's feedback loop work — an optional HealthKit/Google Fit integration that does not exist anywhere in the repo. That is plausibly **comparable in effort to everything the hypertrophy proposal asks for, on top of it**.

The counter-argument for doing it anyway: (a) `improve_fitness` is likely a large share of real users, since "feel better and be healthier" is the modal reason people download fitness apps; (b) cardio session logging and health markers are reusable by `lose_fat` (which has its own cardio needs) and partially by `build_habits`; (c) the alternative — continuing to ship a lifting split to users who asked for general fitness — is the clearest instance in the product of the AI-generated plan being confidently wrong.

**A reduced-scope option exists and should be considered on its merits:** ship Phases 1–2 only (correct prescription, cardio blocks rendered read-only in the plan with "log this as an activity" as a manual note), defer `ActivityLog`, markers, and the progress rework. Cost: the user sees the right plan but the app cannot verify or adapt to whether they did the cardio, and the progress screen still shows an empty volume chart. That is a defensible interim state but **not** a defensible end state, and it should be labeled as interim rather than quietly becoming permanent.

The option that should be rejected: **removing `improve_fitness` from the goal list.** It is the goal with the strongest evidence base behind it and the largest achievable health effect (§3.1: low fitness carried an adjusted HR of 5.04 vs. elite, a risk magnitude comparable to or exceeding smoking or diabetes).

### 8.2 Two new onboarding questions vs. the funnel

- **For:** without the activity baseline the starting dose ranges over 5× with no defensible default, and the pre-signup preview plan — the plan doing the conversion work — would be visibly generic in exactly the way the product is trying to escape.
- **Against:** every pre-signup screen is top-of-funnel drop-off.
- **Mitigation:** the net count for this goal is **0** (11 screens either way), because `priority_muscles` and strength anchors are dropped. And G1 is a cheap tap-a-card question, not a type-a-number one.
- **Instrument, don't assume:** per the hypertrophy proposal §7.6, time-to-plan and per-screen drop-off are the right metrics, not screen count.

### 8.3 Self-reported activity baseline is noisy

Self-reported physical activity is well known to be over-reported, and §2.2 of the findings notes self-reported exposure is exactly why the resistance-training mortality dose-response is graded Moderate rather than High. A user who says "2–4 h" may be doing 1 h.

- **Mitigation:** the error is *bounded and self-correcting* — F6 reduces the dose within two weeks if the prescription isn't being met, and the correction is toward the floor, which is the safe direction. Also worth biasing the mapping conservatively: prescribe at the low end of each band's range, since §1.2's dose-response means the cost of starting slightly low is small (~50% of achievable benefit sits at ~75 min/wk) while the cost of starting too high is dropout.

### 8.4 Health-condition collection

- **For:** two of the constraints are safety gates, and the isometric/BP and T2D-spacing prescriptions are among the highest-value personalizations available.
- **Against:** it makes the app feel clinical, it collects sensitive health data (with privacy, storage, and possibly regulatory implications that are outside this document's scope but must be resolved before implementation), and there is a real risk of users reading the output as medical advice.
- **Mitigation:** optional with a prominent "none of these," explicit non-medical-advice framing (the findings' §13 preamble is the right model), a clearance prompt rather than a block for the high-risk flags, and — importantly — **do not build condition-specific prescriptions the app cannot supervise**. §2.3 and §5.2 both note their strongest protocols (LIFTMOR, high-challenge balance) were supervised and carry non-zero in-training risk.

### 8.5 Balance training without supervision

§5.2 is clear that balance work must be **progressively challenging** to work at all, and equally clear that unsupervised high-challenge balance training carries genuine fall risk during the training itself. For an 80+ user, the evidence-optimal prescription (Otago, supervised initially) is not something an app can deliver safely.

- **Recommendation:** prescribe the full progression ladder up to ~age 79, but for 80+ or anyone flagging a recent fall, cap the app's unsupervised progression at a conservative level (hand support available, no eyes-closed work), surface the Otago programme as a referral rather than an in-app prescription, and say plainly why. Under-prescribing here is the correct error.

### 8.6 Wearable dependence

The best markers for this goal (submaximal HR at fixed workload, RHR 7-day average, HRR1) are dramatically easier with a wearable, and §6.1 notes wrist-wearable overnight RHR is reasonably valid (±2–3 bpm vs. ECG).

- **Risk:** building the feedback loop around wearables makes the product worse for users who don't have one, which correlates with the sedentary population this goal serves best.
- **Mitigation:** every marker must have a device-free path — RPE instead of HR zones (§1.1 gives RPE and talk-test equivalents for every intensity band, which is why the report bothers to list them), the 3-min step test with a manual pulse count instead of continuous HR, manual BP entry, and self-reported stairs/breathlessness. Treat wearable data as an accelerant, never a prerequisite.

### 8.7 Confidence labelling

Several parameters here rest on Low or Low–Moderate confidence: the +5–10%/week aerobic progression rate (§10.1 notes the 10% rule is *not* well supported by RCTs), the variety-improves-adherence claim, exercise-snacking magnitudes (§7.2's VILPA effect sizes are "almost certainly inflated"), and the balance age-gating dose. Where the engine acts on these, `AdaptationHistory.reason` and the user-facing copy should say so. As the hypertrophy proposal notes, honest uncertainty is better coaching UX than false precision — and for a health-framed goal it is also the ethically safer default.
