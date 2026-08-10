# Fat Loss Integration Strategy (`goal == lose_fat`)

**Status:** Proposal for review. No code, migrations, or config have been changed. Nothing here is approved.

**Inputs:** `docs/research/fat-loss-findings.md` (ground truth for every number below; bare `§` references point at that document), `docs/research/coach-integration-strategy.md` (the `build_muscle` proposal whose prescription-layer architecture this extends — referenced as `C§`), `docs/research/strength-integration-strategy.md` (`S§`) and `docs/research/habits-integration-strategy.md` (`Hab§`) for shared infrastructure already proposed, plus the current state of `apps/onboarding`, `apps/workouts`, `apps/adaptation`, `apps/progress`, `apps/ai_engine`, and `frontend/lib/features/{onboarding,progress}`.

**Scope:** what a numerically-grounded fat-loss prescription requires, the honest position on the nutrition-tracking gap, what to ask at onboarding versus infer later, and how the plan-generation and adaptation layers must change. Extending the shared architecture, not forking it.

---

## 0. Recommendation summary (read this if nothing else)

Three structural facts about the current codebase determine everything below.

1. **`lose_fat` reaches the model as the four characters `Lose Fat` inside one f-string.** `_build_prompt()` in `plan_generator.py` renders `- Goal: {profile.get_goal_display()}` and nothing downstream — not the plan schema, not the adaptation engine, not the progress screen — ever reads `profile.goal`. A `lose_fat` user and a `build_muscle` user with identical other answers get the same prompt shape and, predictably, near-identical plans.

2. **The plan schema physically cannot express a fat-loss plan.** The AI response schema is `days[].exercises[]` with `{name, sets, reps_min, reps_max, rest_seconds, order}`. There is no way to represent "35 minutes Zone 2 cycling," no way to represent a step target, and no way to represent a calorie or protein number. §5 and §6 — cardio dose and NEAT — are the two largest non-diet levers in the entire research report, and **neither is representable in the current data model at all.**

3. **Nothing in the system stores bodyweight after onboarding.** `OnboardingProfile.weight_kg` is written once and never updated. Every occurrence of `weight` elsewhere in the backend is `SetLog.weight` (barbell load). §12 ranks 7-day rolling-average bodyweight as the **#1 most reliable progress signal**, and §1.4 step 3 makes revision against measured rate of loss mandatory rather than optional. **The app currently cannot tell whether a fat-loss user is losing fat.** That is the defining gap, and it is not a nutrition-logging gap — it is a bodyweight-trend gap, which is much cheaper to close.

There is also a smaller blocker worth naming early: `AdaptationHistory.workout_session` is a **non-nullable FK**. Every fat-loss adaptation decision ("your rate of loss is too fast," "take a diet break") is triggered by a weekly check-in, not by a workout session. As written, those decisions cannot be persisted.

Prioritized:

| # | Change | Effort | Payoff | New user data? |
|---|---|---|---|---|
| 1 | **`BodyMetricEntry`** (date, weight, waist, hip) + a **7-day rolling-average trend service**. The single unblocking change; §12's #1 and #2 signals both land here | S–M | Very high | Yes (2 taps, ideally daily-optional) |
| 2 | **`FatLossStrategy` inside the shared prescription layer** — one `compute_prescription()`, an added `EnergyPrescription` facet emitting TDEE, intake kcal, deficit %, protein/fat/carb grams, target %BW/wk, step floor, cardio dose | M | Very high — this is the "not templated" delta, and it runs with **zero AI calls** | No (with #4) |
| 3 | **Cardio + steps become first-class in the plan schema** (`conditioning` block per day: modality, minutes, intensity zone; plus a weekly `step_target`) | M | Very high — currently inexpressible | No |
| 4 | **3 conditional onboarding screens shown only when `goal == lose_fat`** (daily activity/steps, waist measurement, pace preference) + 2 in-place upgrades | S | High — selects the row of §1.1/§2.1/§11.4 that drives every number | Yes (conditional only) |
| 5 | **Weekly check-in surface** (weight is #1; plus adherence slider, steps, sleep) reusing the `WeeklyCheckIn` already proposed in `C§6.1` | M | High | Yes (~30 s/week) |
| 6 | **Fat-loss adaptation rule set (F1–F12)** operating on the *deficit*, not on the *load* — plus making `AdaptationHistory.workout_session` nullable and adding non-training decision types | M | High — the current `evaluate_reps` gives actively wrong advice to a cutting user (§5.1) | Needs #1, #5 |
| 7 | **`DietPhase` state** (deficit / maintenance / diet break, week index) — the fat-loss analogue of `S§`'s `PeriodizationState`; recommend **one shared phase object**, not three | M | Medium–high — §7 diet breaks and §1.3 block structure are unimplementable without it | No |
| 8 | **Safety gate + floor guard** (BMI <18.5, age <18, pregnancy, ED history → no deficit prescribed; hard clamps on intake floors) | S | High — risk mitigation, non-negotiable before any calorie number ships | Yes (1 line on an existing screen) |
| 9 | **Goal-aware Progress screen** — 7-day weight trend with target band, waist trend, e1RM retention. "Total Volume" is a near-meaningless headline for this goal | M | Medium–high | No (given #1) |

**Recommendation on the nutrition-tracking question (§2, the one the reviewer most needs an answer to):** **do not build a food logger.** Build a **target-out / outcome-in loop**: the app *prescribes* calorie and macro targets computed deterministically, and *measures* the 7-day rolling weight trend plus a one-slider adherence self-report — then revises the target against observed rate of loss. This is not a compromise; it is what §1.4 step 3 and §10.1 actually prescribe. Reserve real intake logging for a **7-day diagnostic audit triggered only at a verified plateau** (§10.3 step 1). Full reasoning and the counterarguments in §2 below.

**Net onboarding change:** the four other goals see zero additional screens. `lose_fat` users see **+3 conditional screens**. Against the 11-screen shared flow proposed in `C§3.2`, a fat-loss user lands at **14 screens** — or **12** if the waist measurement is deferred to the first post-signup check-in (a real tradeoff, discussed in §3.5).

---

## 1. Problem framing

### 1.1 Why `lose_fat` is the hardest of the five goals for this codebase

The other four goals are served, however badly, by data the app already collects. `build_muscle`, `increase_strength`, and `improve_fitness` are all functions of what happens under a barbell, and the app logs sets, reps, and weight. `build_habits` is a function of whether sessions happen, and the app logs sessions.

`lose_fat` is the one goal where **the primary causal lever lives entirely outside the training log**. §5.4 is High-confidence that combined diet plus exercise beats either alone; §1 makes energy balance the first-order variable and resistance training the *protective* variable. The report's own framing of resistance training during a cut (§4) is not "this is how you lose fat" — it is "this is how you avoid losing muscle while the deficit does the fat loss." An app that only knows about training is, for this goal, instrumenting the second-order variable and blind to the first.

This produces a specific failure the product is trying to escape: for a `lose_fat` user, a plan of sets and reps *is* generic advice, because the part that determines the outcome was never addressed.

### 1.2 What the code does today, precisely

- **`_build_prompt()`** interpolates 11 qualitative labels and asks for "a training split." For a `lose_fat` user, the prompt never mentions calories, protein, deficit, cardio, steps, rate of loss, or load maintenance. The words "fat loss" appear only inside the goal label.
- **The schema (`_SCHEMA_INSTRUCTIONS`)** offers exercises with sets and reps. If the model wanted to prescribe §5's "2–4 cardio sessions, 20–45 min," it would have to encode it as a fake resistance exercise. There is no `conditioning` concept, no duration field, no intensity-zone field.
- **`rest_seconds` defaults to 90** in three places (`PlannedExercise.rest_seconds`, `_to_display_shape`, `persist`). §4.2 puts compound rest at 120–180 s. This is a known defect flagged in `C§1.1` and `S§0`; it bites fat loss too, because short rest is exactly the "metabolic circuit" pattern §4.2 warns against substituting for heavy loading.
- **`evaluate_reps()`** fires `DECREASE_LOAD` when `failed >= 2` (two sets below `target_reps_min`). §4.1 is explicit: **during a cut, do not reduce working loads to chase reps** — keep absolute load at 90–100% of pre-diet and let reps drift down by 1–2. The current engine does the opposite of the research recommendation, automatically, for every cutting user. This is the sharpest single example of "muscle-gain logic relabeled."
- **`evaluate_feedback()`** cuts volume after 3 "hard" ratings with no time window. Reduced volume at maintained load is the *correct* direction per §4.1 — but it must not go below the 6–12 sets/muscle/week retention band (floor 4–6), and the engine has no concept of that floor because, per `C§2.1`, sets per muscle are not computable at all (no muscle tags on `PlannedExercise`).
- **`progress/views.py`** headline metrics are streak, total workouts, and **total volume (Σ weight × reps)**. Total tonnage will *fall* during a well-executed cut at a maintained load with reduced volume. The app's most prominent progress number moves the wrong way for a user doing everything right.
- **`ai_engine/insight_generator.py`** builds its prompt from sessions, PRs, and adaptation rows only. Nothing about bodyweight or waist can reach the insight copy.
- **`AdaptationHistory.Decision`** has four choices, all training-load/volume. There is no vocabulary for `adjust_intake`, `diet_break`, `restore_neat`, or `lean_loss_warning`.

### 1.3 What already exists and should be reused

- The **anonymous preview flow** is a genuine asset here. `compute_prescription()` for the energy facet is pure arithmetic — no AI, no I/O, instant. A pre-signup screen that says "your maintenance is ~2,780 kcal; we're starting you at 2,080 with 173 g protein, targeting 0.7 kg/week" is the strongest anti-generic signal available, costs nothing per user, and can be rendered *before* the plan generation spinner rather than after.
- `PersonalRecord` and the `SetLog` history are the substrate for the e1RM lean-retention warning system (§12.6), which is the single highest-value signal the app can compute **from data it already has**.
- `AdaptationHistory` → `_format_adaptation_notes()` → next `generate()` is an existing persist-and-reinject loop; the fat-loss rules should ride it rather than build a parallel one.
- `WeeklyCheckIn` (`C§6.1`), `TrainingBlock` (`C§6.1`), `ScheduledSession` (`Hab§0`), `StrengthEstimate` (`C§6.1`, `S§0`) are all already proposed for other goals and are all needed here. **The marginal infrastructure cost of `lose_fat` is smaller than it looks**, provided these are built once rather than per goal.

---

## 2. Data-needs analysis

### 2.1 What a numerically-grounded fat-loss prescription requires

Each row: the parameter from the report, the inputs needed to compute it for an individual, and current status.

| Parameter (research §) | Value it must produce | Inputs required | Status in the codebase |
|---|---|---|---|
| **TDEE estimate** (§1.4.1) | kcal/day; Mifflin–St Jeor RMR × activity factor 1.3–1.9 | **sex, age, height, bodyweight** (all four are Mifflin inputs) + **activity level** | `gender`, `age`, `height_cm`, `weight_kg` exist. **Activity level missing** — the biggest single source of error, since the multiplier spans 1.3→1.9, i.e. a ±45% swing on the same RMR |
| **Deficit size** (§1.1, §11.4) | % of TDEE (5–35%) → kcal/day | **starting body-fat bracket** (M >30/25–30/18–25/12–18/<12; F offset ~8–10 pts), **sex**, TDEE | **Body fat missing entirely.** This one input selects the row of three separate tables (deficit, rate, protein) |
| **Absolute-deficit sanity check** (§1.1) | avoid >~500 kcal/day sustained for lifters; better expressed as 20–25% TDEE | TDEE, bodyweight | Derivable once TDEE exists |
| **Intake floors** (§1.4.4, §14) | ≥1,200 F / ≥1,500 M; ≥22–28 kcal/kg BW; energy availability ≥30 kcal/kg **FFM** | bodyweight, sex, **FFM** (= BW × (1 − BF%)), exercise energy expenditure estimate | Requires body fat. Currently no floor logic exists at all |
| **Target rate of loss** (§2.1, §11.4) | %BW/week (0.2–1.3 depending on bracket) | body-fat bracket, sex, **age** (≥60 → 0.25–0.5%), **training experience** (novice → 0.4–0.7% and "scale weight is a poor signal") | `age`, `experience` exist; body fat missing. `experience` is the 3-bucket label `C§2.1` already criticises |
| **Protein target** (§3.1, §11.4) | g/day; 1.2–3.1 g/kg BW depending on leanness, or g/kg FFM when BMI >30 | bodyweight, **body-fat bracket**, **age** (≥60 → 1.6–2.2, min 1.2), BMI (from height + weight) | Body fat missing |
| **Protein distribution** (§3.3) | 0.3–0.4 g/kg per meal × 3–5 meals | bodyweight, age (≥60 → 0.4–0.6 g/kg/meal) | Have (derived) |
| **Fat floor** (§9.1) | 0.5–1.0 g/kg BW, ≥15–20% kcal | bodyweight, intake kcal | Derivable |
| **Carb floor** (§9.1) | 3–5 g/kg typical, hard floor ~2 g/kg or 100 g | bodyweight, training modality mix | Derivable |
| **Resistance volume to hold** (§4.2) | 6–12 sets/muscle/week, floor 4–6; 2–3×/wk frequency; 3–5 sessions | training age, `training_days`, session minutes, **muscle tagging on exercises** | `training_days` exists; **muscle tags missing** (`C§2.1` — the shared blocker) |
| **Load maintenance rule** (§4.1) | keep working loads at 90–100% of pre-diet | **pre-diet e1RM per lift** | Missing — `StrengthEstimate` proposed in `C§6.1`/`S§0`; seedable from `SetLog` history for returning users, needs an anchor or session-1 calibration for new ones |
| **Cardio dose** (§5.1) | 150–300 min/wk moderate-equivalent; 2–4 sessions × 20–45 min | TDEE gap after diet, **available cardio modalities**, **current cardio volume**, injury/joint status | **All missing.** `equipment` has no cardio options; `injuries` is free text |
| **Interference constraints** (§5.3) | ≤3 endurance sessions/wk and ≤30 min/session if running; cycling ≈ neutral; ≥6 h separation (≥24 h hard lower-body); resistance first intra-session | modality, session scheduling | Missing — no scheduling model (`ScheduledSession` proposed in `Hab§0`) |
| **Step floor** (§6.2) | 7,000–8,000 floor; 8,000–12,000 standard; 4,000–6,000 start if BMI >35 | **baseline steps**, BMI, joint status | Missing. §6.3 is explicit that unmeasured activity drifts down 15–30% |
| **Sleep gate** (§8.3) | 7–9 h; <6 h is the risk zone and plausibly a larger lever than a further 200 kcal | **habitual sleep hours** | Missing today; **already proposed** as a shared screen in `C§3.2` #10 |
| **Diet-phase duration** (§7.2) | 8–16 weeks continuous (6–8 when lean), then 7–14 days at maintenance | phase state, body-fat bracket, weeks elapsed | Missing (`DietPhase`) |
| **Rate-evaluation window** (§2.4, §12.2) | 7-day rolling average, compared 14–21 days apart; 4-week same-cycle-phase comparison for menstruating women | **serial bodyweight**, sex, optional cycle phase | Missing entirely — the defining gap |
| **Waist trend** (§12.2, §12.3) | ±1.0–1.5 cm noise band; expect 1–3 cm per 4 weeks | **serial waist circumference** | Missing |
| **Lean-retention warning** (§12.6) | e1RM down >5–10% over 3–4 weeks, or reps at fixed load down ≥2 across multiple lifts | `SetLog` history + e1RM computation | **Data exists; computation does not.** Cheapest high-value win in the report |
| **Recomp expectation** (§11.2) | novice/overweight-novice +1 to +3 kg LBM in a 12-wk deficit → de-emphasize the scale | training age, body-fat bracket | Partially have |
| **Safety contraindications** (§13.3) | deficits often contraindicated (pregnancy, ED history, adolescents, active rehab → cap at 0–15%) | screening flags, BMI, age | Missing |

### 2.2 Why body fat is the load-bearing missing input, and how to get it cheaply

Three separate tables (§1.1 deficit, §2.1 rate, §3.1 protein) and the consolidated §11.4 are all keyed on starting body fat. Without it, none of the three headline numbers can be computed for an individual. It is a bigger gap than TDEE, because TDEE has a defensible formula from data already collected.

But the requirement is weaker than it first appears: **the tables are bracketed, not continuous.** §11.4 has five rows. The system needs to land in the right bracket, not to know the number to ±1%. That tolerance changes the options materially:

| Method | Error | Cost to user | Verdict |
|---|---|---|---|
| DXA | ±1–2% BF (§12.2) | Impossible in-app | No |
| Bioimpedance scale | ±3–5% BF absolute, hydration-sensitive (§12.2) | Requires hardware | Accept if the user volunteers a number; never require |
| **Waist circumference + height** | Bracket-level; waist is already needed for §12.2's #2 progress signal | One tape measurement | **Recommended primary** |
| Visual body-fat band picker (5 illustrated bands per sex) | Self-assessment; people systematically under-estimate their own | 1 tap | **Recommended fallback / cross-check** |
| BMI only | Cannot distinguish a 95 kg lifter from a 95 kg sedentary person | Free (have it) | Last-resort default only |

**Recommendation: ask for waist circumference, and use height (already collected) to derive a bracket, with a visual picker as the fallback for anyone who skips.** Two things make this the right trade:

1. Waist is *dual-purpose*. §12.2 ranks waist circumference the **#2 most reliable progress signal** and §10.2 makes "waist unchanged within ±1.0–1.5 cm" one of the three mandatory conditions for declaring a true plateau. The measurement is needed for tracking regardless; getting the starting bracket from it is free.
2. It anchors the measurement protocol early. §12.3 requires a standardized protocol (morning, fasted, post-void, end of normal exhale, 2–3 replicates averaged) for the error to be small enough to be usable. Introducing it at onboarding, with the protocol shown, is the natural moment.

**Caveat to state plainly for the reviewer:** the specific waist→body-fat conversion (e.g. Relative Fat Mass, `64 − 20×(height/waist)` for men, `76 − 20×(height/waist)` for women) is **not from the research report**. The report supplies the waist-measurement error characteristics (§12.3) and the waist-to-height <0.5 anchor (§12.3), but not a conversion equation. Any conversion chosen is an engineering decision layered on top of the evidence and should be labelled as such internally, treated as bracket-level only, never surfaced to the user as "your body fat is 28.7%," and marked with a `source`/`confidence` field so the adaptation engine knows it is acting on an estimate. The safer user-facing framing is a band ("you're in the higher-body-fat range, which means you can run a larger deficit safely").

### 2.3 The nutrition-tracking gap — the honest assessment

**The question:** does serving `lose_fat` require Peak Coach AI to become a calorie/macro tracker?

**The answer: no — and more strongly, a food logger would not solve the problem it appears to solve.** Recommendation is Option B below.

#### The three real options

**Option A — Full intake tracking.** Build or integrate a food database (MyFitnessPal/Nutritionix/Open Food Facts), barcode scanning, meal logging, macro rollups.

- *For:* closes the loop directly; enables §10.3's "audit intake accuracy first"; enables §1.4's preferred method of establishing maintenance from 7–14 days of stable-weight intake logging, which the report says is better than any predictive equation.
- *Against, and this is decisive:* **§10.1 grades at High confidence that self-reported intake is underestimated by 20–40% in plateaued dieters** (doubly-labelled-water evidence). A food logger therefore does not give the system ground truth; it gives the system a *biased* measurement, and the bias is largest exactly in the population where a correction matters most. Meanwhile the outcome variable — rolling bodyweight — is unbiased and cheap.
- *Also against:* it is a product of comparable size to everything currently in the repo. It is a different competency (food data licensing, database quality, portion UX), it roughly doubles daily interaction burden, and it competes directly with entrenched incumbents. The daily-logging drop-off literature is not in the research report and I will not invent a number, but the direction is not seriously contested, and the report's own §1.3/§7 framing that **adherence decays with time and is the binding constraint** applies to tracking burden as much as to dietary restriction.

**Option B — Target-out, outcome-in (RECOMMENDED).** The app *prescribes* a daily calorie target, protein target, and macro floors, computed deterministically. It does **not** ask the user to log food. It measures: (i) 7-day rolling-average bodyweight, (ii) waist circumference biweekly, (iii) a single weekly self-reported adherence slider ("how close did you stay to your calorie target? 0–100%"), (iv) steps, (v) training performance / e1RM. It then revises the calorie target against the *observed* rate of loss.

- *For:* this is literally what §1.4 step 3 prescribes ("subtract the %, then revise after 2–3 weeks against actual rate of loss") and what §10.3 step 3 prescribes ("recalculate TDEE from observed data"). The report treats the initial number as a **starting estimate to be revised against measured rate of change** — it says so in the standing caveat at the top, and repeats it in §1.4 and §10.3. Under Option B the system converges on the individual's true TDEE from outcomes, which routes around both the ±10–15% predictive-equation error (§1.4.2: equations misclassify >200 kcal in 30–40% of people) *and* the 20–40% self-report bias.
- *For:* burden is roughly 2 taps/day (weight) plus ~30 s/week, against several minutes/day for Option A.
- *Against:* without any intake signal, "losing slower than predicted" is ambiguous between *the TDEE estimate was too high* and *adherence was poor*. Those demand opposite responses — the first wants a lower target, the second wants a re-commitment prompt, and cutting calories on a non-adherent user is both ineffective and harmful to trust.
- *Mitigation, and the key design move:* the weekly adherence slider disambiguates them cheaply. It is a noisy, self-serving signal — but it only has to separate "roughly on plan" from "not really on plan," which is a much easier judgement than "how many calories did I eat." Combined with the step average (§6.3 re-audit every 2 weeks; a >10% decline explains plateaus more often than metabolism does) and the objective weight trend, the engine has enough to pick between the branches of §10.3's response hierarchy without ever knowing a food.

**Option C — Training-signals only, no bodyweight tracking.** Infer everything from workout performance.

- *Reject.* §12.2 is explicit that strength/performance trend is a **lean-retention signal, not a fat-loss signal** — it is ranked #3 and is a proxy for whether the deficit is too large, never for whether it is working. Under Option C the app can detect that a diet is going badly and can never detect that it is going well. Bodyweight is not optional for this goal; it is the goal's dependent variable.

**Escalation D — Diagnostic intake audit, on-trigger only (recommended as a companion to B).** When and only when F6 (verified plateau: <0.2–0.3%BW/wk for ≥3 weeks + waist flat within 1.5 cm) fires, offer a **7-day intake audit**: log everything for one week, in whatever tool the user prefers, and enter a daily average. §10.3 ranks this the **first** step of the response hierarchy with expected yield 200–500 kcal/day of unlogged intake, graded High. Framing it as a time-boxed diagnostic rather than a permanent habit preserves the low-burden default while making the highest-yield intervention available exactly where the evidence says it belongs.

#### What Option B costs you, stated plainly

- The first calorie target will be wrong for a meaningful minority of users — §1.4.2 puts it at >200 kcal off for 30–40% of people. The mitigation is not more precision up front; it is **making the revision loop visible and fast**, and setting the expectation in copy at the moment the number is first shown ("this is a starting estimate; we'll correct it from your actual results in about 3 weeks"). An app that says that is more credible, not less.
- Macro compliance is unverifiable. The protein target in particular is the second-highest-leverage number in the report (§3, High confidence), and the app will have no idea whether it is being hit. Partial mitigation: a weekly binary/3-point protein self-check ("did you hit ~170 g most days?") — one extra tap, coarse, but it is an input to F3's "verify protein ≥2.0 g/kg" branch, which otherwise has nothing to check.
- Users who *want* a tracker will bounce to one. That is acceptable and probably correct: the product's differentiator is the coaching loop, not the food database. A read-only import of daily calorie totals from Apple Health / Google Fit (which MyFitnessPal and others already write to) is a much cheaper way to serve those users than building the logger, and would upgrade Option B toward Option A's information content for free. No health-platform integration exists in the repo today; this is worth scoping separately.

---

## 3. Onboarding versus progressive collection

### 3.1 The decision rule (inherited from `C§3.1`)

A data point belongs in pre-signup onboarding if **(a)** the first prescription is undefined without it, **or** **(b)** defaulting it produces a visibly wrong first plan that costs more trust than the question costs friction. Everything else defaults and gets corrected from behaviour.

Applied to fat loss, with a wrinkle the other goals do not have: **the fat-loss first prescription contains a number the user will act on immediately and that has a safety floor.** A training plan that is 20% too aggressive produces a hard week. A calorie target that is 20% too aggressive can breach the §1.4/§14 intake floors. That asymmetry justifies asking slightly more up front here than elsewhere, and it justifies a hard server-side clamp regardless of what is asked.

### 3.2 Essential before the first fat-loss plan can exist

| Data point | Why it cannot be defaulted | Already collected? |
|---|---|---|
| sex, age, height, bodyweight | All four are Mifflin–St Jeor inputs; no TDEE without them | **Yes** (`C§2.8` proposed dropping `height_cm` as unused — **this proposal reverses that**: for `lose_fat`, height is load-bearing twice over, for RMR and for waist-to-height) |
| activity level | The multiplier spans 1.3–1.9; defaulting it is a ±45% error on the single largest number in the prescription | **No — must add** |
| body-fat bracket (or waist proxy) | Selects the row of the deficit, rate, and protein tables simultaneously | **No — must add** |
| training experience | Novice → recomp likely, 0.4–0.7%/wk, and the scale is explicitly a poor signal (§2.1) → changes both prescription and progress UI | Partial (3-bucket `experience`; `C§3.2` #2 upgrades it to training age in months, which this proposal depends on) |
| training days/week, session length, equipment | Determine the retention-volume prescription | **Yes** |
| limitations + safety flags | §13.3: deficits contraindicated or capped at 0–15% in several contexts; §13.2's cardio substitution ladder needs joint status | Partial (free text; `C§3.2` #7 upgrades to a structured checklist — extend it with a nutrition-safety line) |
| sleep hours | §8: <6 h shifts the fat:lean loss ratio from ~50:50 toward ~20:80 at an identical deficit. Must gate the deficit rather than be discovered later | **No** — but `C§3.2` #10 already proposes it as a **shared** screen. Reuse, do not duplicate |

### 3.3 Can be defaulted or estimated, then refined from real data

| Data point | Initial default | Refined by | Refinement latency |
|---|---|---|---|
| **TDEE** | Mifflin–St Jeor × activity multiplier | Observed maintenance back-computed from actual rate of loss vs prescribed intake (§10.3 step 3) | 2–3 weeks (§1.4.3) |
| **Deficit size** | Bracket midpoint from §11.4 | F1/F2 rules from measured %BW/wk | 3 weeks minimum (§2.4: never judge on <2 weeks) |
| **Body-fat estimate** | Waist/height proxy, or visual band | Updated as waist falls; ~1 cm waist ≈ ~1 kg fat (§12.3) | 2–4 weeks |
| **Pre-diet strength baseline** | Bodyweight-multiplier seed (`C§4.2`) | Every logged `SetLog` → e1RM | 1–2 sessions |
| **Cardio tolerance / actual dose** | Prescribed 2–3 × 25 min LISS | Completion rate and session feedback | 2 weeks |
| **Step baseline** | Self-reported band | Health-platform data if available, else self-reported weekly average | 1–2 weeks |
| **Adherence** | Assume 100% | Weekly slider + weight-trend residual | 3 weeks |
| **Diet-break timing** | Scheduled at week 8–16 by bracket | Pulled forward by F4/F6 triggers | Event-driven |
| **Menstrual-cycle phase** | Not collected | Optional post-signup; changes the comparison window to 4 weeks same-phase (§11.1) | Optional, never required |

The asymmetry that makes this work is the same one `C§3.1` identified: **almost everything in this table is measurable from data normal use generates** — with the single exception of bodyweight, which is why item #1 in the recommendation summary is the unblocking change.

### 3.4 Proposed onboarding additions — 3 conditional screens + 2 in-place upgrades

Shown **only when `goal == lose_fat`**, inserted after the shared "About you" screen so that height/weight/sex/age are already known.

| # | Screen | Type | Conditional? | Rationale (research §) | Parameters unlocked |
|---|---|---|---|---|---|
| **F1** | **"How active is your day, outside of training?"** — 4 options (desk job, mostly sitting / on your feet some of the day / on your feet most of the day / physically demanding job) **plus** a steps band selector (<5k / 5–8k / 8–12k / 12k+, "not sure" allowed) | single choice + band | **Yes** | Activity factor 1.3–1.9 is the largest multiplier in the TDEE estimate (§1.4.1). The steps band separately establishes the **baseline** the §6.2 floor is set against and §6.3's "re-audit every 2 weeks, >10% decline explains plateaus" rule compares to | Activity multiplier → TDEE → deficit kcal; step floor (7–8k minimum, 8–12k standard, 4–6k start if BMI >35 per §13.3) |
| **F2** | **"Measure your waist"** — one number in cm, with the §12.3 protocol shown inline (morning, fasted, post-void, end of a normal exhale, tape snug not indenting, take 2 and average). Skippable → falls through to a 5-band visual picker → falls through to BMI | numeric, skippable with fallbacks | **Yes** | Selects the row of §1.1 (deficit %), §2.1 (rate), §3.1 (protein) — three headline numbers from one measurement. Also establishes the §12.2 #2-ranked progress signal and the §10.2 plateau criterion. Dual-purpose, which is what justifies the friction | Body-fat bracket; deficit %, target %BW/wk, protein g/kg; waist baseline; waist-to-height ratio |
| **F3** | **"How fast do you want to go?"** — 3 options rendered **with the computed consequence already filled in** ("Gradual — about 0.4 kg/week, ~20 weeks to your target" / "Standard — 0.7 kg/week, ~12 weeks" / "Faster — 0.9 kg/week, ~9 weeks, harder to train through"), each clamped to the safe band for this user's bracket. Optional target weight and/or event date | single choice, bounded | **Yes** | §1.3's aggressive-short vs mild-long tradeoff is genuinely contested and adherence-dependent, so it is a legitimate preference question — but only *within* the §11.4 band. The options must be computed per user, not fixed: for a lean user "Faster" is 0.5%/wk, for a high-BF user it is 1.0%. Also sets expectations against §12.7's realistic timelines, which is itself an adherence intervention | Deficit % within band; phase length; the target band drawn on the progress chart |

**In-place upgrades to shared screens (0 net new screens, benefits other goals too):**

- **Equipment screen** gains cardio modalities (treadmill, bike/spin, elliptical, rower, pool, outdoor only). §5.3 makes modality a *hard* prescription input, not a preference: running shows significant strength/hypertrophy interference while **cycling does not**, and §13.2's substitution ladder is ordered by joint load. Without this the cardio prescription is unimplementable. Also useful for `improve_fitness`.
- **Limitations screen** gains one line: a nutrition/deficit safety flag ("Do any of these apply? — pregnant or postpartum / history of disordered eating / currently managing a medical condition affecting diet / none"), plus derived checks on BMI <18.5 and age <18. §13.3 states deficits are often contraindicated in these contexts and §13.4 caps the deficit at 0–15% during active rehab. **This must ship before any calorie number does**; it is not optional polish.

**Count: +3 conditional screens for `lose_fat` users only; 0 for the other four goals.** Against the 11-screen shared flow of `C§3.2`, a fat-loss user sees 14. That is the honest number and it is at the upper edge of tolerable for a pre-signup funnel.

### 3.5 The tradeoff on screen F2, stated explicitly

Waist measurement is the highest-value and the highest-friction question in the set. It requires the user to physically find a tape measure mid-onboarding, which many will not have to hand at the moment they are tapping through a signup funnel. Two defensible positions:

- **Ask it pre-signup (proposed).** The first plan contains real, individualized numbers, which is what the whole strategy is for. A user who cannot measure right now falls through to the visual band picker and loses very little — the bracket is what matters, and the visual picker gets most users into the right or adjacent band.
- **Defer it to the first post-signup check-in (12 screens instead of 14).** Cost: the pre-signup prescription is computed from a BMI-derived bracket, which systematically misclassifies muscular users as higher-BF (over-aggressive deficit) and skinny-fat users as lower-BF (under-aggressive). Given the pre-signup plan is doing the conversion work, weakening its central number to save one screen is probably the wrong trade — **but this is an A/B test, not a settled question**, and the metric to watch is per-screen drop-off and time-to-plan, not screen count.

A third option worth considering: **ask F2 pre-signup but make the visual picker the default path and the tape measurement the "more accurate" upgrade.** This keeps the screen at one tap for everyone, captures the tape number from the subset who have one, and prompts the rest at the first check-in when they are at home. This is likely the best version and is what I would build first.

### 3.6 Progressive collection plan

| Data point | Mechanism | Cadence | Feeds |
|---|---|---|---|
| **Bodyweight** | 2 taps, morning prompt. Store every entry; **display only the 7-day rolling average** | Daily-optional (see the tradeoff below) | Rate of loss vs target (F1, F2); observed-TDEE recalculation; plateau detection (F6) |
| **Waist (+ hip optional)** | 1 number, protocol reminder shown | Every 2 weeks | Plateau criterion #2 (§10.2); recomp detection (F5); body-fat re-estimate |
| **Adherence self-report** | One 0–100% slider, "how close to your calorie target?" | Weekly | Disambiguates "TDEE wrong" from "adherence low" — the branch point of the §10.3 hierarchy |
| **Protein self-check** | 3-point ("most days / some days / rarely") | Weekly | F3's "verify protein ≥2.0 g/kg" branch |
| **Steps** | Health-platform read if available; else a weekly average band | Weekly | §6.3 re-audit; F7 NEAT-drift rule |
| **Sleep hours** | Part of the shared `WeeklyCheckIn` (`C§3.4`) | Weekly | F10 sleep gate; §8's fat:lean ratio effect |
| **e1RM per index lift** | Passive, from every `SetLog` (Epley/Brzycki) | Continuous | F3 lean-loss warning — §12.2's #3 signal and §12.6's whole framework |
| **Progress photos** | Optional, standardized-condition guide from §12.4 | Every 2–4 weeks | §12.2's #5 signal; best for long-interval comparison. **Storage is a real problem — see §6.4** |
| **Cardio completion** | From the conditioning block in the session log | Per session | Actual vs prescribed weekly minutes; interference-ceiling check |
| **Menstrual cycle phase** | Optional, opt-in only | Monthly | Switches the comparison window to 4-week same-phase (§11.1); explains 0.5–2.0 kg luteal fluid shifts instead of alarming the user |

**The weighing-frequency tradeoff — the most consequential UX decision in this proposal.**

The obvious design is a weekly weigh-in. It is also close to useless as specified. §12.1 puts daily noise at **±0.5–2.0 kg** against a true tissue change of ~65 g/day at a 500 kcal deficit — signal-to-noise well below 1. A single weekly measurement is one draw from that distribution; two weekly measurements 7 days apart can easily differ by 2 kg in the *wrong* direction during genuine fat loss. §12.2 and §14 are High-confidence that the usable signal is a **7-day rolling average compared 14–21 days apart**, and that requires multiple weigh-ins per week.

- **Daily weighing:** highest fidelity, gives a readable trend in 10–14 days (§12.7), and — counterintuitively — is *less* emotionally volatile when the app shows only the smoothed line, because it teaches the user that the noise is noise.
- **Against:** a daily body-measurement prompt is a genuine risk surface for users with disordered-eating tendencies, and it is the highest-frequency obligation the app would impose on anyone.
- **Recommended middle path:** prompt daily but require nothing; compute the rolling average from ≥3 entries in a 7-day window and widen the confidence band (and lengthen decision windows from 14 to 21 days) when fewer are available; **never display a raw daily number or a day-over-day delta**, only the trend; offer an explicit "weekly only" mode at onboarding with an honest explanation of the accuracy cost; and hard-suppress the weight surface entirely for anyone who flagged an ED history on the safety screen, falling back to waist, photos, and performance.

---

## 4. From qualitative labels to real numbers

### 4.1 Where this lives: one prescription layer, two facets

`C§4.1` proposes `compute_prescription(profile, training_state) -> Prescription`; `S§0` proposes a `StrengthStrategy` alongside a `HypertrophyStrategy` behind that same entry point. **This proposal adds a `FatLossStrategy` behind the same entry point and extends the return object with an `energy` facet** — it does not add a parallel nutrition service.

```
compute_prescription(profile, state) -> Prescription
    .training : TrainingPrescription   # all goals — sets, reps, RIR, rest, loads
    .conditioning : ConditioningPrescription | None   # lose_fat, improve_fitness
    .energy : EnergyPrescription | None               # lose_fat (and later, gaining phases)
```

`EnergyPrescription` fields: `tdee_estimate_kcal`, `tdee_source` (formula | observed), `deficit_pct`, `deficit_kcal`, `intake_kcal`, `protein_g`, `fat_g_min`, `carb_g_min`, `target_rate_pct_bw_wk`, `target_rate_kg_wk`, `floor_binding` (which floor, if any, clamped the result), `phase_length_weeks`, `confidence`.

`ConditioningPrescription` fields: `weekly_minutes`, `sessions` (modality, minutes, intensity zone, placement relative to lifting days), `step_target`, `step_floor`, `interference_notes`.

Deterministic, no AI, no I/O, unit-testable directly against the §14 glance table. Runs on an unsaved `OnboardingProfile`, so the anonymous preview flow keeps working — and, as noted in §1.3, the energy facet can render **before** the AI call, instantly and for free.

### 4.2 The computation chain

```
sex, age, height, weight        → Mifflin–St Jeor RMR                      (§1.4.1)
RMR × activity factor (1.3–1.9) → TDEE estimate                            (§1.4.1)
waist ÷ height (or visual band) → body-fat bracket                         (§11.4 row selection)
bracket + sex + age + pace pref → deficit % of TDEE                        (§1.1, §11.4, §11.3)
TDEE × deficit %                → target intake kcal
   clamp: ≥1,200 F / ≥1,500 M; ≥22–28 kcal/kg (adjusted BW); EA ≥30 kcal/kg FFM   (§1.4.4, §14)
bracket + sex + age + experience→ target rate %BW/week                     (§2.1, §11.3, §11.4)
weight + bracket + age + BMI    → protein g/day                            (§3.1, §11.3)
weight                          → fat floor 0.5–1.0 g/kg, ≥15–20% kcal     (§9.1)
weight + modality mix           → carb floor 3–5 g/kg, hard 2 g/kg / 100 g (§9.1)
   feasibility check: if protein + fat floor + carb floor > intake → REDUCE THE DEFICIT (§9.1)
training age + days + minutes   → sets/muscle/wk 6–12 (floor 4–6), 2–3×/wk (§4.2)
pre-diet e1RM                   → target loads at 90–100% of pre-diet      (§4.1)
deficit gap + modality + joints → cardio sessions/minutes/zone             (§5.1, §5.3, §13.2)
baseline steps + BMI            → step floor and target                    (§6.2, §13.3)
bracket                         → phase length 8–16 wk (6–8 if lean)       (§7.2)
```

Two decisions in that chain are mine, not the report's, and the reviewer should look at them specifically:

**(a) The macro solver ordering.** §9.1's stated method is "protein first, then fat at floor-to-preference, then all remaining calories to carbohydrate," with the note that if protein plus minimum fat consumes most of the budget, *the deficit is too aggressive*. In practice that ordering silently starves carbohydrate below the §9.1 lifter floor before it trips the warning. I propose making the check explicit and ordered: **set protein → reserve the carb hard floor (2 g/kg or 100 g) → reserve the fat floor (0.5 g/kg) → allocate the remainder → if the reservations exceed the intake target, shrink the deficit until they fit and tell the user why.** This is a stricter reading of the same paragraph and it converts an easily-missed narrative caveat into a hard constraint. It also produces genuinely better UX: "we reduced your deficit from 700 to 550 kcal because at 700 you couldn't hit both your protein and the minimum carbohydrate you need to train" is exactly the coaching a user cannot get from a generic app.

**(b) Reconciling the intake floors at high body fat.** §1.4.4 sets a floor of ~25–28 kcal/kg BW/day for men, but §1.1 recommends a 20–30% TDEE deficit for men above 25% BF. These conflict for larger, higher-BF users: a 96 kg man with an estimated TDEE of 2,780 has a 25% deficit target of 2,085 kcal, while 25 kcal/kg of *total* bodyweight is 2,400 — the floor would forbid the recommendation. The report resolves the analogous problem for protein in §3.1 ("Obese (BMI >30) — use FFM or adjusted BW, not total BW"). I propose applying the same resolution here: **evaluate the kcal/kg floor against adjusted bodyweight (FFM + 0.25 × fat mass), while the absolute floors (1,500 M / 1,200 F) and the energy-availability floor (30 kcal/kg FFM/day) remain in force against the true values.** This is consistent with the report's own logic elsewhere, but it *is* an interpretation and should be flagged as such in the code comments and in any clinical review.

### 4.3 The proof: two users, same label, different prescriptions

Both select `lose_fat`. Under today's code they receive the same prompt modulo two numbers the model has no instruction to use.

| | **User A** | **User B** |
|---|---|---|
| Inputs | M, 34, 180 cm, 96 kg, waist 102 cm, desk job ~5,000 steps, trains 4 d/wk, ~30 mo training age, sleeps 7 h | F, 47, 163 cm, 58 kg, waist 74 cm, active job ~11,000 steps, trains 3 d/wk, 4 mo training age, sleeps 5.5 h |
| Mifflin RMR | 1,920 kcal | 1,203 kcal |
| Activity factor | 1.45 (sedentary job, 4 lifting days, low steps) | 1.60 (active job, high steps, 3 lifting days) |
| **TDEE estimate** | **~2,780 kcal** | **~1,925 kcal** |
| Body-fat bracket (waist/height) | 0.57 → high-20s % → §11.4 "M 25–30%" | 0.45 → low-30s % → §11.4 "F 28–35%" |
| **Deficit** | **25% ≈ 700 kcal/day** | **15% ≈ 290 kcal/day** — low end, because §8 puts 5.5 h sleep in the risk zone and §8.3 says fixing sleep is plausibly a bigger lever on *composition* than a further 200 kcal |
| **Intake target** | **~2,080 kcal** | **~1,635 kcal** |
| Floor check | Absolute 1,500 M — clear. Adjusted-BW floor ~1,880 — clear | Absolute 1,200 F — clear. 22 kcal/kg BW = 1,276 — clear |
| **Protein** | **~173 g** (1.8 g/kg, §11.4 row) | **~116 g** (2.0 g/kg, leaner bracket → higher g/kg) |
| Fat / carb | Fat pushed to its 0.5 g/kg floor (~48 g) so carbs clear the 2 g/kg hard floor (~240 g, 2.5 g/kg). Flagged to the user as "your budget is tight — this is what a 25% deficit costs" | Fat ~0.8 g/kg (~46 g), carbs ~170 g (2.9 g/kg) — comfortable |
| **Target rate** | **0.8%BW/wk ≈ 0.77 kg/wk** | **0.5%BW/wk ≈ 0.29 kg/wk** (§2.1 novice row: 0.4–0.7% and recomp likely) |
| **Primary progress metric shown** | 7-day rolling weight trend, with the target band | **Waist + strength retention promoted above the scale.** §2.1 says for novices "scale weight is a poor signal"; §11.2 puts novice recomp at +1 to +3 kg LBM in a 12-week deficit, which can make the scale flat while fat falls |
| **Steps** | Ramp 5,000 → **8,000 floor** over 3 weeks (§6.2, §6.3) | Already 11,000 → **hold, do not increase.** The prescription is defending the baseline against the §6.1 diet-induced 15–30% drift |
| **Cardio** | 3 × 30 min, **cycling or incline walking** (§5.3: cycling ≈ no interference), on non-lifting days, ≥6 h from lifting | **0–2 × 20 min optional.** She already has high NEAT and 3 lifting days; §5.3's ceiling and her recovery capacity at 5.5 h sleep mean the deficit should come from diet, not more cardio |
| **Resistance volume** | Hold 10–12 sets/muscle/wk, load ≥90% of pre-diet, RIR 1–3, no systematic 0-RIR (§4.1, §4.2) | 6–10 sets/muscle/wk (novice tier), 2×/wk frequency, **progressive** — she is in the §11.2 "reliably recomps" group, so this is not purely a retention prescription |
| **Phase** | 14-week deficit block, diet break scheduled at week 12–14 (§7.2) | 12 weeks, with **sleep extension as a first-class prescribed target** (§8.3: +1.2 h/night reduced intake ~270 kcal/day in Tasali 2022 — nearly her entire prescribed deficit, for free) |
| Comparison window | Rolling averages 14 days apart | Rolling averages **21 days / same cycle phase if applicable** (§11.1, §2.4) |

Same qualitative answer, two different products. That difference is the whole point of the work.

### 4.4 Label → number mappings to encode

**Body-fat bracket → the three headline numbers** (§11.4, verbatim):

| Bracket (M / F) | Deficit % TDEE | Rate %BW/wk | Protein g/kg BW | Recomp likely? |
|---|---|---|---|---|
| >30 / >40 | 25–35 | 0.8–1.2 | 1.2–1.6 (or 2.0–2.4 g/kg FFM) | Yes |
| 25–30 / 35–40 | 20–30 | 0.7–1.0 | 1.6–2.0 | Often |
| 18–25 / 28–35 | 15–25 | 0.5–0.8 | 1.8–2.2 | Sometimes |
| 12–18 / 22–28 | 12–20 | 0.4–0.7 | 2.0–2.4 | Rarely |
| <12 / <22 | 5–15 | 0.2–0.5 | 2.4–3.1 | No |

**Modifiers applied on top** (each narrows or shifts the band; never stack beyond the safest binding constraint):

- Age ≥60 → cap deficit at 10–20% TDEE, rate 0.25–0.5%/wk, protein 1.6–2.2 g/kg, per-meal 0.4–0.6 g/kg (§11.3)
- Training age <6–12 months → rate 0.4–0.7%/wk regardless of bracket; demote the scale in the UI (§2.1)
- Sleep <6 h → start at the low end of the deficit band; prescribe sleep extension as an intervention in its own right (§8.3)
- Female below ~20% BF → flag rates >0.7%/wk for menstrual-disruption risk (§2.3); EA <30 kcal/kg FFM is a hard stop (§11.1)
- Active injury rehab → cap deficit at 0–15%, protein at the upper end 2.0–2.5 g/kg (§13.4)
- BMI >35 → non-weight-bearing cardio, step target starts 4,000–6,000 and progresses ~500–1,000/week (§13.3)
- As body fat falls ~8–10 percentage points → halve the target %BW/wk (§2.2)

**`pace_preference` → position within the band, never outside it.** "Gradual" = band minimum, "Standard" = midpoint, "Faster" = band maximum. The user is choosing where in an evidence-bounded range to sit, not choosing a number. The UI should show the consequence of each option in that user's own units.

**Activity level → multiplier.** 4 options mapped to 1.3 / 1.45 / 1.6 / 1.75, with the steps band as a cross-check (a "desk job" answer with a 12k+ steps band should resolve upward). §1.4.1's stated range is 1.3–1.9; reserving 1.9 for cases the questionnaire cannot distinguish is deliberate conservatism, since over-estimating TDEE produces an over-aggressive deficit.

**Cardio modality + injury flags → §13.2's substitution ladder**, in order: swimming → cycling/recumbent → elliptical/arm ergometer → rowing (unsuitable for low back) → incline walking → flat walking → running. Running is prescribed last and capped hard at ≤3 sessions/wk and ≤30 min/session per §5.3.

---

## 5. Adaptation engine for fat loss

### 5.1 Why this is a genuinely different rule set, not a relabel

The muscle-gain engine's decision space is `{increase_load, decrease_load, decrease_volume, maintain}` — every output is a change to what happens under the bar, triggered by what happened under the bar. Fat-loss adaptation inverts both halves:

| | `build_muscle` (current + `C§5.2`) | `lose_fat` (proposed) |
|---|---|---|
| **Trigger source** | A finished workout session (`evaluate_reps`) or a feedback submit | A **weekly check-in** — weight trend, waist, steps, adherence. Training data is a *secondary*, corroborating input |
| **Trigger latency** | Per session; `C§5.2` R2 requires 2 consecutive exposures | **≥2–3 weeks.** §2.4: never judge rate on <2 weeks; §10.2: a true plateau requires ≥3 weeks. Faster reaction is not more responsive, it is noise-chasing |
| **Primary lever** | Load (±2.5–5%) and volume | **Energy intake** (±5–20%), **NEAT/steps**, **cardio dose**, **phase** (deficit ↔ maintenance) |
| **What load does** | Progresses upward | **Held.** §4.1: "do not reduce working loads to chase reps"; keep 90–100% of pre-diet |
| **What falling reps mean** | Under-recovery → reduce load (`C§5.2` R2) | **A diagnostic about the diet, not the training.** §12.6: e1RM down >5–10% over 3–4 weeks means reduce the *deficit*, verify protein, verify sleep — not reduce the load |
| **What a flat scale means** | Nothing (weight isn't the outcome) | Ambiguous and requires three-signal disambiguation (§10.2, §12.6): flat + waist falling + strength rising = **success**; flat + strength falling = **worst quadrant, diet break** |
| **Success definition** | Load/volume/e1RM going up | Weight trending down **at the target rate** while e1RM stays flat. **Flat strength is a win here and a failure there** |

Concretely: today, `evaluate_reps` sees a cutting user's normal 1–2 rep drift, fires `DECREASE_LOAD`, and that decision is folded into the next `generate()` call via `_format_adaptation_notes()`. The user's programme is progressively de-loaded across a cut — which §4.1 identifies as the specific mechanism that turns fat loss into muscle loss. **The most urgent adaptation change is not adding fat-loss rules; it is stopping the existing rule from firing for this goal.**

### 5.2 Proposed rules (F1–F12)

All thresholds are from the cited sections. Every rule evaluates on 7-day rolling averages compared 14–21 days apart (§2.4), never on raw weekly values.

| Rule | Trigger | Action | § |
|---|---|---|---|
| **F0 — Guard** | `goal == lose_fat` and a `DietPhase` is active | **Suppress `evaluate_reps`'s `DECREASE_LOAD`.** Reps drifting down 1–2 at maintained load is the expected trajectory, not a fault | §4.1 |
| **F1 — Too slow** | Rolling-avg rate <50% of target for **≥3 weeks**, AND adherence ≥80%, AND steps within 10% of the floor | Recompute TDEE from observed data (observed maintenance = intake + implied deficit), then reduce intake **5–10% (100–250 kcal)** *or* add 2 cardio sessions of 20–30 min — never both, never more. Clamp at all floors | §10.3.3, §10.3.4 |
| **F2 — Too fast (lean-mass risk)** | Rolling-avg rate **>1.0%BW/wk** (trained or lean) or **>1.4%** (anyone), across two comparisons 14–21 days apart | Increase intake **10–20%**; verify protein at bracket target; surface an explicit warning explaining the Garthe 2011 result (slow group gained ~2.1% lean mass and 1RM; fast group did not) | §2.1, §14 |
| **F3 — Lean-loss warning (performance)** | e1RM on index lifts down **>5–10%** over 3–4 weeks, **or** reps at fixed load down ≥2 for 2+ consecutive sessions across multiple lifts, **while weight is falling** | Reduce deficit **10–20%**; verify protein ≥2.0 g/kg; verify sleep ≥7 h; prescribe a deload (−40–60% volume, load held). **Do not reduce load** | §12.6, §4.1 |
| **F4 — Worst quadrant** | Weight flat **and** strength falling | **Diet break, 7–14 days at maintenance** (+20–30% kcal, mostly carbohydrate). §12.6 names this the worst quadrant explicitly | §12.6, §7.2 |
| **F5 — Recomposition detected** | Weight flat, waist down ≥1.0–1.5 cm, strength rising | **No change to the prescription.** Switch the primary progress metric away from the scale in the UI and say why | §12.6 |
| **F6 — Verified plateau** | **All three:** <0.2–0.3%BW/wk for ≥3 weeks; waist unchanged within ±1.0–1.5 cm over the same window; adherence verified (intake and steps within ~10%) | Run §10.3's hierarchy **in order, one step at a time**: (1) offer the 7-day intake audit; (2) restore steps to the floor; (3) recompute TDEE and cut 5–10%; (4) +2 cardio sessions under the interference ceiling; (5) if ≥8–12 weeks in deficit or intake is at a floor, **diet break instead of cutting further**. Never skip to step 3 | §10.2, §10.3 |
| **F7 — NEAT drift** | 14-day step average down **>10%** from baseline | Restore steps **before** touching calories. §6.3 and §10.1: a step decline explains a plateau more often than "metabolic damage," and self-report error accounts for much of the rest | §6.3, §10.1 |
| **F8 — Scheduled diet break** | **8–16 weeks** continuous deficit (6–8 when lean or on a large deficit) | 7–14 days at estimated maintenance. Present with the honest caveat: MATADOR showed a large advantage, several systematic reviews show equivalence, and both camps agree breaks are not harmful and help adherence | §7.1, §7.2, §15.1 |
| **F9 — Floor guard** | Any computed intake below the absolute floor (1,500 M / 1,200 F), the kcal/kg floor, or EA <30 kcal/kg FFM | **Hard clamp.** Shift the deficit to activity, or extend the timeline, or refuse to increase the deficit further. Non-advisory; this is a safety stop | §1.4.4, §11.1, §14 |
| **F10 — Sleep gate** | Reported sleep <6 h sustained over 2 weeks | **Do not increase the deficit.** Prescribe sleep extension as the intervention: §8.2's sleep-extension RCT found ~270 kcal/day of spontaneous intake reduction from ~1.2 h more sleep | §8.2, §8.3 |
| **F11 — Adherence-driven volume cut** | Session completion <60–70% over 14 days | Cut resistance **volume** 20–40% but **never below 4–6 sets/muscle/week**, and **never cut load**. Contrast with the muscle-goal version of this rule, which may cut either | §4.2, §4.1 |
| **F12 — Female LEA / rate guard** | Female, estimated BF below ~18–20%, rate >0.7%/wk; or EA approaching 30 kcal/kg FFM | Reduce deficit; surface the menstrual-disruption and bone-density risk framing from the RED-S consensus | §2.3, §11.1 |

**Suppression rules that matter as much as the triggers:**

- Never act on a single flat week (§10.3 closing line, stated as an absolute).
- Never fire F1 and F6 in the same window — F6's ordered hierarchy supersedes F1's simple cut.
- For menstruating users, compare rolling averages at the same cycle phase on a 4-week window rather than 14–21 days (§11.1); a 0.5–2.0 kg luteal fluid shift will otherwise trigger F1 and then F2 in consecutive months.
- Expect and pre-explain the +1–2 kg scale rebound on a diet break (§7.2, High confidence), resolving in 3–7 days. If the app does not say this in advance, F8 will read to the user as the app making them fat.

### 5.3 Model changes the rules require

- **`AdaptationHistory.workout_session` must become nullable.** F1, F2, F4, F6, F7, F8, F10, F12 are all triggered by check-ins, not sessions. As written the FK makes them unpersistable.
- **`AdaptationHistory.Decision` needs fat-loss members:** `adjust_intake_down`, `adjust_intake_up`, `diet_break_start`, `diet_break_end`, `restore_neat`, `add_cardio`, `lean_loss_warning`, `intake_audit_requested`, `hold` (distinct from `maintain`, which currently means "training load unchanged").
- **`reason` is a `CharField(max_length=255)`.** Fat-loss reasons carry numbers and evidence caveats ("rate 0.31%/wk vs 0.7% target over 21 days at 86% adherence; TDEE re-estimated 2,780 → 2,590; intake 2,080 → 1,950"). 255 characters will bind. Prefer a structured `payload` JSONField alongside the human-readable reason, which also lets `_format_adaptation_notes()` pass **resolved numeric deltas** into the next prompt rather than prose — a point `C§6.4` already makes.

---

## 6. Architecture implications

### 6.1 Data model (proposal, not implementation)

**`apps/onboarding` — `OnboardingProfile`:**
- `activity_level` (choices → multiplier) and `baseline_steps_band`
- `waist_cm` (nullable), `body_fat_estimate_pct` (nullable), `body_fat_source` (`waist_proxy` | `visual_band` | `user_reported` | `bmi_fallback`), `body_fat_confidence`
- `pace_preference` (`gradual` | `standard` | `faster`), `target_weight_kg` (nullable), `target_date` (nullable)
- `cardio_modalities` (JSON list) — folded into the equipment screen
- `deficit_safety_flags` (JSON list) — feeds the §13.3 contraindication gate
- **Keep `height_cm`.** `C§2.8` proposes it as removable-if-nutrition-is-out-of-scope. Nutrition is now in scope; height is a Mifflin input and the denominator of waist-to-height. This proposal explicitly reverses that recommendation.
- Reuse rather than duplicate: `sleep_hours_band` and structured `limitations` from `C§6.1`; `training_age_months` from `C§3.2` #2.

All new fields must be **nullable and conditionally validated** (`required if goal == lose_fat`), because the same serializer serves the anonymous preview endpoint for all five goals. `OnboardingProfileSerializer` is a flat `ModelSerializer` today; goal-conditional validation is new behaviour it will need.

**New — `BodyMetricEntry`:** `(user, measured_on, weight_kg, waist_cm, hip_cm, source, note)`, one row per measurement, append-only in the spirit of the existing workout history. This should be **the canonical store**, with the `WeeklyCheckIn` proposed in `C§6.1` referencing it rather than carrying its own `bodyweight_kg` column — otherwise the same fact lives in two places. The rolling-average computation belongs in a service (`apps/progress/services/body_trend.py`), not in views.

**New — `EnergyPrescription`** (versioned, never updated in place): `(user, effective_from, tdee_estimate_kcal, tdee_source, deficit_pct, intake_kcal, protein_g, fat_g_min, carb_g_min, target_rate_pct_bw_wk, floor_binding, confidence, superseded_by)`. Versioning is not optional: §1.4.3 and §10.3.3 both require revising the target against observed data, and computing "observed maintenance" requires knowing what the target *was* during the window being measured.

**New — `DietPhase`:** `(user, phase_type: deficit|maintenance|diet_break, started_at, ended_at, planned_weeks, week_index)`. **Recommend unifying this with the `TrainingBlock` proposed in `C§6.1` and the `PeriodizationState` proposed in `S§0` into a single phase object with a type enum.** Three parallel phase models for three goals is exactly the disconnected-parallel-system outcome this work is meant to avoid.

**New — `AdherenceCheckIn`** or added columns on the shared `WeeklyCheckIn`: `intake_adherence_pct`, `protein_adherence` (3-point), `steps_daily_avg`. Prefer extending `WeeklyCheckIn`; one weekly surface, one row.

**`apps/workouts`:**
- **A `ConditioningBlock` concept** — either a sibling of `PlannedExercise` on `WorkoutDay` or a standalone weekly prescription: `(modality, minutes, intensity_zone, placement, notes)`. Without this, §5 is unimplementable. Its logged counterpart (`ConditioningLog`: modality, minutes, avg HR or RPE) is needed for the interference-ceiling check.
- `PlannedExercise` gains `target_load_kg` and `primary_muscle`/`secondary_muscles` (already proposed in `C§6.1`) — needed here for the 90%-of-pre-diet load rule and the 6–12 sets/muscle floor respectively.
- `SetLog` gains `rir` and `is_warmup` (already proposed in `C§6.1`).
- Fix the `rest_seconds=90` default in all three locations (already proposed in `C§0` and `S§0`).

**`apps/progress`:** a `ProgressPhoto` model is the natural home for §12.4, but **no media storage is configured in the backend at all** (no `MEDIA_ROOT`, no `STORAGES`, no file backend). Progress photos would require object storage, a signed-URL scheme, and a privacy/retention policy for what is among the most sensitive data a fitness app can hold. §12.2 ranks photos #5 with a 4–8 week latency. **Recommendation: defer photos entirely, or ship them as device-local-only with a standardized-conditions capture guide and no upload.** The local-only version delivers most of §12.4's value at a fraction of the risk.

### 6.2 Prompt restructuring for `lose_fat`

Following `C§6.2`'s three-section structure, with fat-loss-specific content:

1. **Hard numeric constraints (computed, non-negotiable).** Weekly sets per muscle (6–12, floor 4–6) and per-session caps; **explicit load-maintenance directive** ("prescribe loads at 90–100% of the athlete's pre-diet working loads; do NOT reduce load to accommodate the deficit; reps may drift down 1–2"); rest by exercise class; RIR 0–3 with an explicit prohibition on systematic 0-RIR work; the conditioning block (sessions, modality, minutes, zone) with placement constraints (≥6 h from lifting, ≥24 h for hard lower-body endurance, resistance-before-endurance if same-session); the weekly step target.
2. **Exercise and modality selection (delegated judgement).** Equipment-legal exercise choice and ordering; cardio modality preference order from §13.2's ladder given the user's joints and available equipment; **an explicit instruction that high-rep "metabolic" circuit work must not displace heavy loading** (§4.2, and one of the most common failure modes in generic fat-loss programming — worth stating negatively in the prompt because it is the model's likely prior).
3. **Extended output schema.** Add a `conditioning` array per day and a plan-level `weekly_step_target`. Add `target_load_kg`, `target_rir_min/max`, `primary_muscle` per `C§6.2`.

**The energy prescription must not pass through the model.** Calorie and macro numbers are computed, rendered directly, and injected into the *display layer* — never asked for and never restated by the AI. The prompt should include a short instruction that the athlete's nutrition targets are already set and must not be mentioned or altered in exercise notes, because an unconstrained model will otherwise volunteer its own calorie advice inside a `notes` field, and that advice will not match the computed number. A post-generation check for calorie-like strings in free-text fields is cheap insurance.

**Coaching copy** (the insight generator, `_format_adaptation_notes`, check-in responses) is where the AI genuinely adds value for this goal: explaining why the scale went up 1.4 kg after a high-sodium weekend, why waist matters more than weight this month, why flat strength during a cut is a win. That requires `insight_generator._build_prompt()` to receive body-metric trend data, which today it cannot — it reads only sessions, PRs, and adaptation rows.

### 6.3 Post-generation validation

Extend `_validate_display_shape()` (currently a key-presence check) with fat-loss constraint checks against the computed `Prescription`:

- weekly resistance sets per muscle within the 6–12 band and never below the 4–6 floor
- total weekly cardio minutes within 150–300, and within the user's prescribed dose
- running-modality sessions ≤3/week and ≤30 min/session (§5.3)
- no cardio session scheduled within 6 h of a lifting session (24 h for hard lower-body work)
- prescribed loads within 90–100% of the stored pre-diet e1RM where one exists
- rest values in the class-appropriate bracket (rejecting the silent `default=90`)
- no calorie/macro claims in any free-text field

On failure: one repair round-trip naming the specific violations, then a deterministic trim — same pattern as `C§6.3`.

### 6.4 Frontend implications

- **New check-in surface** (`frontend/lib/features/checkin/`): a daily 2-tap weight entry and a weekly ~30 s screen (adherence slider, steps, sleep, protein 3-point, waist every 2 weeks). Routing follows the existing centralized `redirect` in `core/router/app_router.dart` — a check-in prompt must not be added as an ad hoc `context.go()` elsewhere.
- **Progress screen is goal-conditional.** For `lose_fat`, the primary card becomes the 7-day rolling weight trend with the target band overlaid, then waist trend, then e1RM retention on index lifts. `fl_chart` is already a dependency, so a line chart with a shaded target band is straightforward. **"Total Volume" must not be the headline for this goal** — it falls during a correctly executed cut. `ProgressSummary` in `progress_models.dart` and `/api/progress/summary/` both need goal-aware payloads.
- **Onboarding flow** (`onboarding_flow_screen.dart`) currently switches on `_step` against a hardcoded `_stepCount = 12`, with every step a `case` in one method. Conditional per-goal screens are not expressible in that structure without branching arithmetic on both `_step` and `_stepCount`. `C§6.4` already suggests a declarative step list; **conditional screens make that refactor a prerequisite rather than a nice-to-have**, and `S§` needs the same thing for its three strength screens. One declarative step-list refactor serves all three proposals.
- **`OnboardingDraft`** gains the new fields and its `toJson()` grows correspondingly; the preview endpoint payload shape follows.
- **A pre-signup "your numbers" screen.** Because the energy prescription needs no AI call, it can render instantly between the questionnaire and `/onboarding/generating`. This is a conversion asset, not just a data display — it is the moment a user sees something a generic app cannot produce.

### 6.5 Suggested sequencing

- **Phase 0 — stop the bleeding (no new data, small):** guard `evaluate_reps` so `DECREASE_LOAD` does not fire for `lose_fat` users (F0); fix the `rest_seconds=90` default; make `AdaptationHistory.workout_session` nullable.
- **Phase 1 — measurement:** `BodyMetricEntry`, the rolling-trend service, the daily/weekly check-in surface, goal-aware progress display. **This is worth shipping before any prescription work** — it is the only way to know whether anything later is working, and it delivers standalone user value.
- **Phase 2 — prescription:** `FatLossStrategy` + `EnergyPrescription` behind the shared `compute_prescription()`; the 3 conditional onboarding screens; the safety gate and floor guard; the pre-signup numbers screen.
- **Phase 3 — conditioning:** schema extension for cardio and steps, prompt restructuring, the validator.
- **Phase 4 — adaptation:** F1–F12, `DietPhase` (unified with the other goals' phase objects), the plateau audit escalation, trend-aware insight copy.

---

## 7. Tradeoffs, stated explicitly

**7.1 Prescribing calorie numbers at all.** Shipping a number a user eats to is a materially different product-risk posture than shipping a set-and-rep scheme. It invites comparison to nutrition apps, it interacts with app-store health-claim policies, and it can cause harm in a population the app cannot screen well. Against that: the report is unambiguous that energy balance is the primary lever, and a fat-loss product that omits it is offering the generic advice the whole exercise is meant to escape. The middle position — prescribe a target with the estimate framed honestly, clamp hard at the §1.4/§14 floors, screen for contraindications, and never gamify eating less — is defensible, but it is a decision the reviewer should make deliberately rather than inherit from a doc.

**7.2 Daily weighing.** Covered in §3.6. Higher fidelity and a faster feedback loop, against a daily obligation and a real risk surface. The recommended compromise (prompt daily, require ≥3/week, show only the trend, explicit weekly-only mode, hard-suppress on ED flag) preserves most of the statistical value; the honest cost is a wider confidence band and a 21-day rather than 14-day decision window for users who weigh less often.

**7.3 Three extra onboarding screens.** 14 screens pre-signup for `lose_fat` users against 11 for the shared flow. Every one is before the user has an account. §3.5's alternative — defer waist to the first check-in, land at 12 — is a genuine option; the hybrid (visual picker default, tape as an upgrade) is probably better than either. The right metric is per-screen drop-off, not screen count, and it should be instrumented before any of this ships.

**7.4 Bracket-level body fat from a tape measure.** The conversion is not from the research report and carries meaningful individual error, particularly for very muscular or very tall/short users. Mitigations: it selects a *bracket*, and adjacent brackets differ by ~5 percentage points of deficit rather than by a categorical change in approach; the estimate is corrected by observed rate of loss within 3 weeks anyway (F1/F2); and it is never displayed as a precise number. Still, this is the weakest link in the computation chain and should be labelled as such in code.

**7.5 No intake data means an irreducible ambiguity.** The adherence slider is self-reported and self-serving. There will be users the engine tells to eat less who were actually eating more than they said — the exact scenario §10.1 documents at 20–40% under-reporting. F6's ordered hierarchy mitigates this by putting the intake audit *first* and the calorie cut *third*, which is the right ordering precisely because it assumes measurement error before it assumes metabolism. But the ambiguity does not go away without Option A, and the reviewer should accept that consciously.

**7.6 Deterministic prescription versus AI coaching.** Same tension as `C§7.5`, with a sharper edge: for this goal the AI is barred from the headline numbers entirely. That is correct — a language model should not be inventing calorie targets — but it narrows the AI's role to exercise selection, conditioning-modality choice, and explanatory copy. The counter-argument is that explanatory copy is where fat-loss coaching is *actually experienced*: explaining a 1.4 kg water swing, or that flat strength during a cut is a win, is the difference between a user who quits in week 3 and one who finishes. The numbers were never the part users experienced as coaching.

**7.7 Diet breaks are a genuinely contested recommendation.** §15.1 is explicit: MATADOR shows a large advantage, several systematic reviews show equivalence, and the honest consensus floor is "not harmful, probably helpful for adherence, metabolic advantage unproven." F8 should therefore be presented as a *recommendation with a stated rationale*, not an automatic prescription, and `AdaptationHistory.reason` should carry the confidence grade — which, per `C§5.4`, is also better coaching UX than false certainty.

**7.8 What this proposal does not address.** Meal planning, recipes, food databases, supplements, alcohol tracking, hydration tracking, and micronutrient coverage (§9.3–§9.5) are all out of scope. §9's macronutrient composition findings are used only to set floors, not to prescribe a dietary pattern — which is consistent with §9.1's High-confidence finding that low-carb versus low-fat makes no meaningful difference when protein and calories are matched, so pattern should be chosen by adherence, i.e. by the user.
