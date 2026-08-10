# Habits Integration Strategy (`goal == build_habits`)

**Status:** Proposal for review. No code, migrations, or config have been changed.
**Inputs:** `docs/research/habits-findings.md` (treated as ground truth for all claims and confidence grades), the existing `docs/research/coach-integration-strategy.md` (the `build_muscle` integration proposal, whose architecture this extends), and the current state of `apps/onboarding`, `apps/workouts`, `apps/progress`, `apps/adaptation`, and `frontend/lib/features/{onboarding,progress}`.
**Scope:** what makes the `build_habits` path actually work, why it is a different *kind* of problem from the other four goals, and what would have to change to serve it.

---

## 0. Recommendation summary (read this if nothing else)

**The headline: for this goal, the training prescription is almost the least important thing, and the app's single most visible "habit feature" — the streak — is currently both broken and, per the evidence, pointed in the wrong direction.**

Three findings drive everything below.

1. **`progress/services/streak.py` counts consecutive *calendar* days.** A `build_habits` user training the modal 3 days/week can never have a streak above 1. The number the Progress screen shows most prominently is, for the exact population this goal serves, mathematically pinned at 1 no matter how perfectly they adhere. It is not a weak metric; it is a non-functional one.

2. **The streak also never decays,** because it is only written on session finish. A user who last trained 40 days ago still sees "Current Streak: 3." When they finally return, the counter silently resets to 1 — i.e. the app delivers its only punishment signal at precisely the moment the research identifies as the highest-leverage moment in the entire product (Finding 21: the top-performing intervention out of 54 in the Milkman megastudy rewarded *returning after a missed workout*).

3. **The app has no concept of a scheduled session.** `WorkoutSession` rows are created ad hoc by `StartSessionView`; there is no date a session was *supposed* to happen. Without that, there is no denominator, so rolling completion rate, missed-session detection, and lapse re-engagement are all currently uncomputable. This one missing object gates most of the proposal — and it is also required by rule R7 (adherence) in the existing `build_muscle` proposal, so it is shared infrastructure, not habits-specific cost.

Prioritized:

| # | Change | Effort | Payoff | Habits-only? |
|---|---|---|---|---|
| 1 | **`ScheduledSession`** — materialize planned sessions with dates from the user's chosen days. The denominator everything else needs | M | Very high — unblocks 3, 4, 5, 6 | No (all goals; also needed by R7 in the muscle proposal) |
| 2 | **Fix + demote the streak.** Redefine on *scheduled* days rather than calendar days, stop it silently resetting on return, and move it out of the primary slot | S | Very high — today's implementation is worse than nothing for this goal | No (the calendar-day bug affects everyone) |
| 3 | **Rolling 4-week completion rate + weekly frequency as the primary consistency display**, with streak demoted to secondary | S | High — the evidence-preferred framing (Finding 31); degrades gracefully | Primary for habits, useful for all |
| 4 | **Implementation-intention capture: which days, what routine anchor, what has broken it before** — placed *after* the plan reveal, not in the pre-signup funnel | M | High — best-evidenced cheap intervention available (d ≈ 0.24–0.31) | Yes (+ `motivation == consistency`) |
| 5 | **Lapse-detection rules + a return-after-miss re-engagement flow** with a reduced-scope "floor session" | L | Highest per the evidence, but gated on notification infrastructure that does not exist | Yes |
| 6 | **A "floor version" of every workout day** the AI must emit alongside the full version | S | High — makes re-entry and bad-day completion possible at all | Mostly habits; useful everywhere |
| 7 | **Modest plan-generation changes:** lower first-block per-session demand, self-selectable intensity, hold frequency | S | Moderate — real, but the smallest lever here | Yes |
| 8 | **Monthly 4-item SRBAI automaticity check** | S | Moderate — the only direct measure of the actual target construct | Yes |
| 9 | **Notification/scheduling infrastructure** (none exists in the repo today) | L | Prerequisite for 5 | No |

**Net onboarding change: zero additional pre-signup screens.** One existing screen is upgraded in place (the 2–6 days slider becomes a day-of-week picker, which benefits all five goals), and the habits-specific questions move to a post-signup "lock in your plan" step where they are both cheaper and, per the evidence on self-generated plans, better answered.

**What explicitly should *not* change:** exercise selection logic, the muscle/volume prescription work proposed in `coach-integration-strategy.md`, PR detection, the adaptation engine's load rules, and the plan JSON schema beyond one added field. See §6.

---

## 1. Problem framing: why this goal is different in kind

### 1.1 The other four goals are precision problems; this one is not

`coach-integration-strategy.md` diagnosed the `build_muscle` failure precisely: the pipeline never computes a number, so the AI falls back on priors and every user gets a template. The fix is a deterministic prescription layer. The same diagnosis holds for `increase_strength`, `lose_fat`, and `improve_fitness` — different tables, same architecture.

`build_habits` does not fit that shape. The research report's own summary of the field is that **"the problem is almost never 'wanting to'; it is translation, friction, and maintenance"** (§2.1, High confidence: ~46% of people who intend to exercise don't). Roughly 50% of people who start a structured program quit within 3–6 months, attrition is front-loaded in weeks 2–6, and ~66% of dropouts in the STRRIDE trials left *before reaching prescribed intensity* (§2.2, Findings 8–9).

None of those failures are caused by a set count being wrong by two. A user who never opens the app on Wednesday is not experiencing a programming problem. **For this goal the product surfaces — what the app asks at onboarding, when it speaks, what it says after a miss, and what number it puts on the Progress screen — are the intervention.** The workout content is the substrate, not the lever.

### 1.2 A second, harder framing point: the honest ceiling

The report is unusually blunt about its own evidence base, and the proposal should inherit that. Findings 19, 20, and 22 together say: gamification adds a *trivial* increment (+489 steps/day over non-gamified digital comparators); only 8% of 54 tested programs in the largest field experiment produced measurable effects after they ended; and streaks have essentially **no** isolating RCT evidence for exercise adherence. Meanwhile implementation intentions — the best-evidenced cheap technique available — run d ≈ 0.24–0.31 for physical activity, and the report flags that publication bias makes those plausible *upper* bounds (Finding 34).

So the realistic claim for anything built here is: **small effects, on a behavior that takes months not weeks to automatize (Findings 3, 51), with most of the upside concentrated in avoiding own-goals** — the guilt-framed notification, the punishing streak reset, the over-prescribed week-one plan. A meaningful share of the value of this work is *removing* harm the current design can do, not adding a new mechanic.

This also sets a product-copy constraint: the app must not promise a habit in 21 days, 30 days, or 66 days. Finding 1 is High confidence that "21 days" traces to a 1960 trade book about plastic-surgery patients, and Finding 2 notes the 66-day median came from a 39-participant curve-fitted subset. Any countdown-to-habit UI would be actively misinformative.

### 1.3 What the target construct actually is

Finding 6 (Moderate): exercise habit attaches to **instigation** — the act of starting — not to execution. Nobody performs a 45-minute session on autopilot. This has a direct product consequence: the thing to make automatic, cue, reward, and measure is *opening the app and starting the session*, not finishing a prescribed volume. It argues for a very low-friction start action and for a session design where "started" is already most of the win.

---

## 2. What an adherence-optimized first experience requires

### 2.1 The evidence stack for day one

| Requirement | Research basis | Confidence |
|---|---|---|
| Early per-session demand deliberately below what the physiology tables would prescribe | ~66% of STRRIDE dropouts left before reaching prescribed intensity (§2.2, F9); affect turns reliably negative above the ventilatory threshold (F13); affect *during* exercise predicts future PA, post-exercise affect does not (F12) | Moderate |
| Frequency preserved, not reduced | Automaticity is a function of cue-paired repetitions; Kaushal & Rhodes ~4×/wk × ~6 wk threshold (F4); §3.2 favours "higher frequency, lower per-session demand" | Moderate for the direction, Low for the number |
| Self-selectable intensity | Self-selected intensity improves affect and enjoyment vs imposed at matched workload (F14); also an SDT autonomy lever | Moderate |
| A concrete if-then plan (when, where, how) with a coping plan attached | d = 0.31 post / 0.24 follow-up for PA (F15); barrier planning is the moderator that raises the effect (F16); problem-solving BCT β = 0.36 | High that it exists, Moderate on size |
| Routine-anchored cue preferred over clock time | Keller et al. 2021 RCT (F17); converges with Buyalskaya finding day-of-week/context out-predicted time-of-day for gym habits | Low-Moderate (single RCT) |
| Early wins that are *reliably completable but non-trivial* | Bandura: mastery is the strongest efficacy source, but effortless success is a weak one (§5) | Moderate for the principle, Low for any specific difficulty target |
| Wins should build **scheduling** and **coping** self-efficacy, not just task self-efficacy | Scheduling self-efficacy predicts maintenance; coping self-efficacy predicts lapse resilience (§5) | Moderate |
| Proximal mood/energy effects surfaced as *elicited noticing*, never as promised outcomes | F32; promising them sets up disconfirmation | Moderate |
| No physique/weight framing as the reinforcement channel | Appearance motives map to introjected regulation → short-term-only adherence, worse well-being (F24, §12.4) | Moderate-High |

### 2.2 Concretely, what the app should do differently from day one

**Pre-signup (the preview flow), minimal change:**
- Generate the plan at a **deliberately conservative first-block dose**: same training frequency the user chose, shorter per-session demand, RIR targets at the easy end (3–4), and an instruction that intensity is user-selectable within a band.
- Emit a **floor version of each day** — 1–2 exercises, ~10 minutes — alongside the full version. This is the "can I do this on my worst realistic day?" threshold from §3.3 (explicitly labelled expert-consensus reasoning, not a tested prescription). It exists so that a bad day produces a *completed reduced session* rather than a miss.
- **Do not** add if-then questions here. See §4.

**Immediately post-signup, before the first session:**
- Capture the implementation intention: which specific days, what routine anchor precedes the session, and what has derailed past attempts → one coping plan per named barrier (§4.2).
- Set expectations honestly: months not weeks; misses are normal and one miss does not set you back (this is a *true* statement per F5, and stating it up front is the cheapest available inoculation against the what-the-hell effect).

**First 4–8 weeks (the hazard window, F8):**
- Escalate load on **evidence of tolerance** — high completion rate plus non-"hard" feedback — not on a calendar. This directly serves the §5 tension: keep success probability high while the increments remain genuinely felt.
- Elicit the affective/energy read after sessions rather than asserting benefits.

### 2.3 The tension, stated plainly

**An easier early plan is better-supported for adherence and worse for physiology, and the preview plan is also the conversion surface.**

- *Against making it easier:* the pre-signup plan is what sells the product. A 25-minute, 4-exercise week-one plan can read as thin AI output — exactly the "generic" tell the muscle proposal is trying to eliminate. A user who chose `build_habits` may still expect an impressive-looking program, and under-delivering on that expectation is its own churn risk (before the adherence machinery ever gets a chance to work).
- *For making it easier:* dropout concentrates in the ramp (F9), in-session affect predicts future behavior (F12), and a session repeated 40 times beats a better session repeated 8 times (§3.1, item 4 — labelled Low-Moderate, a corollary rather than a tested claim).
- *The evidence is genuinely incomplete here.* §3.1 states outright that there are "surprisingly few head-to-head RCTs directly randomizing 'reduced early dose' vs 'full dose' with long-term adherence as the primary outcome." This is a reasoned bet, not a settled one.

**Recommendation:** make the first block easier, but **resolve the conversion tension through presentation rather than through dose.** Show the preview as a phased program — "Weeks 1–4 (deliberately conservative), Weeks 5–8, Weeks 9+" — with the later phases visible. The user sees an ambitious program and starts on the tolerable ramp. This costs one UI element and gives up nothing scientifically. Explicitly state the rationale in-plan ("we start below your capacity on purpose; most people quit during the ramp, not at the start") — rationale-giving is itself an SDT autonomy support (§8.3).

**Secondary recommendation:** treat the conservative-vs-standard first block as an A/B test on 8-week retention rather than shipping it as settled. The report does not license confidence here, and the app will have better data on its own users than the literature has.

---

## 3. Verdict on the existing `WorkoutStreak` / streak service

### 3.1 What the code does

`update_streak_on_finish(user)` is 15 lines. Its entire logic is: if the last workout was yesterday, increment; if it was today, no-op; **otherwise reset to 1.**

Three consequences, in ascending order of severity.

**(a) It is a consecutive-*calendar*-day counter, applied to a product that prescribes 2–6 days a week.** `training_days` is validated to `MinValueValidator(2), MaxValueValidator(6)`. For any user not training 7 days a week, the `else` branch — reset to 1 — is the branch that fires on essentially every session. A user with a perfect 3×/week record for six months has `current_streak == 1` and `longest_streak == 2` (from any accidental back-to-back pair). **The metric the Progress screen shows first is, for the target population of this goal, permanently and misleadingly near zero.** This is not an evidence question; it is a defect.

**(b) It only ever moves forward, on finish.** Nothing decays it. A user dormant for 40 days still reads "Current Streak: 3" on `/progress`. The number is stale and biased upward — which, incidentally, is the same direction as the self-report inflation the report warns about in Finding 33, except here the app is doing the inflating.

**(c) The reset lands on the return.** The user who comes back after two weeks off gets their counter zeroed at the moment they re-engage. Finding 21 (High confidence) is that the best-performing of 54 megastudy interventions **rewarded returning after a missed workout**. The current implementation does the precise inverse: it applies its only negative signal exactly when the strongest available evidence says to apply a positive one.

### 3.2 What the evidence says about streaks generally

Even a correctly-implemented streak is weakly supported:

- Finding 22 (Low confidence for the popular claim): there are **essentially no rigorous RCTs isolating streak counters** for exercise adherence. Observational "long-streak users exercise more" data is tautological.
- Finding 5 (Moderate): **missing a single day did not measurably impair the automaticity trajectory** in Lally et al. §7.3 draws the conclusion directly — "a mechanic that treats one miss as total failure is therefore misinformative about the user's actual habit progress." A streak is a *poor estimator of the construct it appears to measure* (§12.1).
- Finding 23 (Moderate-High in dieting/addiction; Low-Moderate transfer to exercise): the what-the-hell / abstinence-violation effect. A binary standard is violated → guilt → abandonment. Self-compassion counteracts it (28g vs ~70g in Adams & Leary). The report is honest that direct exercise tests are scarce.
- §7.3 adds **streak-induced rigidity**: a daily binary is physiologically inappropriate for resistance training, which requires rest days. The app's own plan generator prescribes 2–6 days, so its plan and its streak metric are in direct contradiction.
- Counterweight: streaks are partly just **self-monitoring**, which *is* a well-evidenced BCT in its own right (High confidence, §7.3). That is the honest reason not to delete streaks entirely.

### 3.3 Verdict

**Change the primary framing, and fix the streak rather than deleting it.** Specifically:

1. **Primary consistency metric becomes rolling completion rate + frequency.** Sessions completed ÷ sessions scheduled over a rolling 4 weeks, displayed alongside absolute sessions/week. Rationale (Finding 31, Moderate): it degrades gracefully — one miss moves it a few percentage points, which is *an accurate representation of what one miss actually does to habit formation* per Finding 5; it matches how the adherence literature itself measures adherence; and its trend is the actionable signal. §12.2's caveat applies and must be handled: **the denominator is manipulable**, so rate must always be shown with absolute frequency, or a user reducing their schedule reads as improving.

2. **Redefine the streak on scheduled sessions, not calendar days.** "4 planned sessions in a row" is both a coherent number and honest. This alone fixes defect (a).

3. **Demote it.** Secondary position on the Progress screen, neutral styling, no loss-framed language, no red on break.

4. **Add forgiveness mechanics**, with the honesty that §12.1 requires: rest days are excluded by construction once the streak is scheduled-based; add a grace/"freeze" allowance. Note explicitly that forgiving variants have **no direct trial evidence** in exercise — they are principled mitigations of a documented mechanism, not proven features.

5. **Never reset on return.** When a user comes back after a gap, the correct product behavior is to acknowledge the return, not to zero a counter. Add a **`returns_after_miss` count** as a first-class, positively-framed statistic. §12.5 item 4 proposes exactly this — "recovery speed is arguably a *better* maintenance indicator than uninterrupted performance" — and flags it as a novel synthesis at Low confidence, but it is the synthesis best aligned with the single strongest exercise-specific result available (F21).

6. **Add a periodic direct measure.** Monthly 4-item SRBAI (Finding 30, Moderate-High psychometrics; the authors explicitly recommend it for tracking habit formation over time). Caveat from §12.3 that must be respected: its motivational effect *when shown to users* is unstudied (Low confidence), so introduce it as a private trend, not a headline score.

**What not to do:** do not build leaderboards, comparative rankings, or competitive social mechanics on top of this. Finding 26 and §6 note competitive/comparative features can demotivate low-performing, low-self-efficacy users — precisely this population — and the 2023 habit meta-regression found "social reward" BCTs *negatively* associated with effectiveness (β = −0.40, one small analysis, hypothesis-generating only).

---

## 4. Onboarding vs. progressive collection

### 4.1 The decision rule, adapted for this goal

The muscle proposal's rule was: ask it if the plan is undefined without it. For `build_habits` that rule under-collects, because the highest-value inputs (days, anchor, barriers) aren't needed to *generate* a plan at all — they're needed to *execute* one. So the rule becomes:

> Ask pre-signup only if the plan cannot be generated without it. Ask immediately post-signup if it materially changes whether the user does the first four weeks. Infer from logs otherwise.

There is also a specific evidence reason to move the if-then questions *after* the plan reveal: **self-generated plans outperform experimenter-assigned plans** (§4.2, Low-Moderate), and a user cannot meaningfully self-generate "I'll train Monday, Wednesday and Friday after work" before they have seen what a session actually is. Asking at screen 3 of 12, pre-signup, produces a guess. Asking after the plan reveal produces a commitment.

### 4.2 Proposed additions

**Pre-signup: zero new screens. One upgraded in place.**

| Change | Type | Conditional? | Rationale |
|---|---|---|---|
| **Days per week → which days** | Replace the 2–6 slider (`onboarding_flow_screen.dart` case 6) with a weekday multi-select; `training_days` derives from `len(selection)` | **Unconditional — all five goals** | The "when" half of an implementation intention (§4.2: plans lacking when/where/how show weaker effects), at zero screen cost. Buyalskaya found **day-of-week was often more informative than time-of-day** for gym habits (§1.3), so day selection is the higher-value half. It is also the only way to build a `ScheduledSession` denominator, which rule R7 in the muscle proposal needs too. |

**Post-signup, immediately after the plan is saved — 2 screens, conditional.**

| # | Screen | Trigger | Rationale |
|---|---|---|---|
| H1 | **"What happens right before?"** — routine-anchor picker per training day (after work / after morning coffee / after the school run / after my shower / custom text), with an optional clock time as fallback | `goal == build_habits` (optionally also `motivation == consistency`) | Completes the if-then plan. Keller et al. 2021 RCT: **routine-based cues produced stronger habit formation than time-based cues** (F17, Low-Moderate, single RCT), converging with Buyalskaya. §10 adds the under-discussed constraint that **anchor quality matters** — the anchor must itself be reliable and occur when the workout is feasible — so the UI should validate rather than accept anything ("does that happen most weeks?"). Critical for shift workers and caregivers (§11.3), where clock cues are structurally unusable. |
| H2 | **"What has stopped you before?"** — multi-select barrier checklist (no time / too tired after work / travel or irregular schedule / childcare / gym feels intimidating / got sick or injured / lost motivation / other), then one if-then coping response per selected barrier, offered as pickable defaults | Same | This is the highest-value single question in the set. Barrier/coping planning is **the moderator that increased implementation-intention effect sizes** in Bélanger-Gravel (F16), and the habit meta-regression found problem-solving BCTs positively associated (β = 0.36). §9.2 item 4: "planning *for* the lapse before it happens is better-evidenced than reacting well after it." The stored coping plans are also the **content** of the re-engagement message in §5 — this is what lets a lapse notification say something specific and user-authored rather than generic encouragement. |

**Question count: +0 pre-signup, +2 post-signup, +1 upgraded in place.** For a `build_habits` user the pre-plan flow stays at 12 screens today (or 11 under the muscle proposal's pruning), and the two habits screens sit after signup where drop-off costs an activated feature rather than a conversion.

### 4.3 Where this would double-count with existing fields — and the recommendation

Three overlap risks, and I would resolve all three toward *not* adding a field.

**(a) `motivation == consistency` — is a new field needed?** No. `Motivation` already offers `consistency` alongside `looking_better`, `lifting_heavier`, `health`, `athletic_performance`. But it is not sufficient either, and the reason is worth being precise about: **`motivation` captures *why*, and everything above needs *when*, *where*, and *what blocks me*.** Knowing a user is motivated by consistency tells you nothing actionable — per §2.1, ~46% of intenders never act, so a stated consistency motive is close to zero information about behavior. It is also largely redundant with the goal (a user selecting `build_habits` will very often also select `consistency`).

Recommendation: **use `goal == build_habits` as the primary trigger, and `motivation == consistency` as an optional secondary trigger** to offer H1/H2 to users pursuing another goal who nonetheless flag consistency as their driver. Do not build anything that *depends* on `motivation`, because the muscle proposal recommends pruning it from the pre-plan flow entirely; if that lands, `goal` must be sufficient on its own. And note the mirror risk: `looking_better` maps to appearance motives, which F24 associates with **introjected regulation → short-term initiation, poor maintenance**. That is a signal worth acting on (bias the coaching copy toward identified regulation for those users), but it is a copy/tone decision, not a new field.

**(b) "Have you exercised regularly before?" — is a new field needed?** No, if the muscle proposal's `training_age_months` change lands. §11.1 segments users into never-sustained / previously-consistent-now-lapsed / existing-but-inconsistent, and these have genuinely different priorities: relapsers have the **best prognosis** (F11: prior exercise history is the single strongest predictor) but need load deliberately regressed below perceived capability and need the original lapse cause addressed; never-exercisers need the longest timeline and the lowest entry threshold. But `training_age_months` plus a single "are you training now?" toggle yields all three segments for free. The current `experience` field (beginner/intermediate/advanced) does **not** — it measures skill, not consistency history, and an "intermediate" user could be in any of the three segments. Recommendation: get this from the training-age upgrade already proposed; do not add a habits-specific field.

**(c) Session length.** `workout_duration` already exists. The habits-specific need — a floor session — is not another question; it is a generation-side output (§6.2). No new field.

### 4.4 What to infer progressively rather than ask

| Signal | Mechanism | Feeds |
|---|---|---|
| Rolling completion rate + trend | `ScheduledSession` status vs `WorkoutSession` | Primary progress display; lapse rules L3 |
| Which scheduled days actually get done | Same, grouped by weekday | Re-specification: "Wednesdays aren't landing — want to move it?" This is far better than asking upfront which day is fragile; the user doesn't know yet |
| Actual vs stated session length | `finished_at − started_at` | Detects a plan that is too long in practice; feeds dose reduction |
| Start-but-don't-finish rate | Requires `ABANDONED` to actually be written — see §6.1 | Session design is too demanding; a distinct failure mode from not starting at all |
| Time-of-day pattern | `started_at` | Confirms or corrects the declared anchor; can suggest a better one after ~8 sessions |
| Perceived difficulty | Existing `WorkoutFeedback.difficulty` | Escalation gate: only progress the dose when completion is high *and* difficulty is not "hard"/"very_hard" |
| Elicited proximal benefit (mood/energy) | One optional post-session tap, added to the reflection screen | The immediate-reinforcement channel (F25, F32). Must be **elicited, not promised** (§12.4) |
| Automaticity | Monthly 4-item SRBAI | The only direct measure of the target construct (F30) |
| Life-transition / cue disruption | Inferred from an abrupt pattern break, or a light "has something changed?" prompt at L4 | §10: life transitions are documented habit-discontinuity points and are windows of unusual openness to re-planning |

Design constraint, inherited from the muscle proposal and reinforced by §10 (friction is a reliable lever): **never more than one new question per session, never before the workout is complete, always dismissible without penalty.**

---

## 5. Lapse detection and re-engagement

### 5.1 What the app can and cannot see today

Available now: `WorkoutSession.started_at`, `finished_at`, `status`, `ExerciseLog.status` (including `skipped`), `WorkoutFeedback.difficulty`.

Missing and load-bearing:
- **No scheduled date on anything.** A miss is currently invisible — there is no row representing a session that should have happened.
- **`ABANDONED` is declared in `WorkoutSession.Status` but never written anywhere in the codebase.** Sessions the user starts and quits stay `in_progress` forever. That is a discarded dropout signal and, notably, it also silently inflates any naive "sessions started" count.
- **No notification, push-token, scheduling, or background-job infrastructure exists** anywhere in the repo (no Celery, no cron, no FCM, no token storage). Every rule below assumes a delivery channel that must be built.

### 5.2 Proposed detection rules

All thresholds are grounded where the report supports it and labelled as inference where it does not. §9.2 item 5 is explicit that **no direct evidence establishes an optimal re-engagement window** — the timing below is reasoned from the attrition-hazard shape, and should be treated as a starting hypothesis to be tuned on the app's own data.

| Rule | Trigger | Response | Basis |
|---|---|---|---|
| **L0 — Cue reminder** | It is a scheduled day and no session started by the anchor time | One neutral, pre-lapse reminder tied to the user's own anchor wording ("after work — your 20-minute session is ready"). Not a lapse response | §10: a pre-specified session removes a decision at the moment of lowest willpower; this is the mechanism implementation intentions exploit |
| **L1 — First miss** | One scheduled session missed | **Deliberately no failure message.** At most, a neutral re-offer of the next session. Optionally a one-tap reschedule ("move it to tomorrow?") | F5 (Moderate): missing a single day did not measurably impair the automaticity trajectory. Messaging a single miss as a problem is **factually wrong** and manufactures the violation that triggers the what-the-hell cascade |
| **L2 — Second consecutive miss** | Two consecutive scheduled sessions missed, or ~7 days with no completed session | **The core re-engagement flow** (§5.3). Offer the floor session; surface the user's own coping plan for their stated barrier; explicitly normalize | §9.1: "repeated/consecutive misses are the real risk." F21: rewarding return-after-miss was the top of 54 megastudy interventions. §9.2 item 5's inference: intervene "before a multi-week gap consolidates a non-exercise identity" (Low confidence) |
| **L3 — Declining trend** | Rolling 4-week completion rate drops >20 percentage points vs the prior window, or falls below ~50% | Treat as **a prescription error, not a user failure.** Reduce prescribed frequency/duration toward what the user is actually doing, then offer re-specification: "your Wednesdays aren't landing — move it, or shorten it?" | Mirrors R7 in the muscle proposal ("If completion is low, the *prescription* is wrong, not the user"). §3.1: dropout concentrates where the dose exceeds tolerance. Thresholds here are **product judgment, not from the report** |
| **L4 — Dormancy** | 14+ days with no completed session | **One** low-frequency, self-compassion-framed message offering a restart at a reduced dose, plus an explicit re-planning prompt ("has something changed — schedule, travel, injury?"). Then back off hard; cap total messages | §10: life transitions are documented habit-discontinuity points that break plans *and* open windows for new ones. §4.2: "plan fragility is real… plans need periodic re-specification." Escalating nags have no support and plausibly accelerate uninstall |
| **L5 — Abandonment pattern** | ≥2 sessions started but not finished in a rolling 2 weeks (requires writing `ABANDONED`) | Distinct diagnosis: they *are* showing up, the session is too much. Cut per-session demand; do not touch frequency | F9/F13: the ramp is where people are lost; imposed intensity above threshold produces negative in-session affect, which predicts less future exercise. Instigation is working; execution is not |
| **L6 — Rate/frequency divergence guard** | Completion rate rising while absolute weekly frequency falls | Suppress "you're improving" messaging; surface both numbers | §12.2's explicit caveat: the denominator is manipulable. Prevents the app congratulating a user for shrinking their commitment |

### 5.3 What the L2 re-engagement intervention should be

**Timing.** Same-day or next-morning after the second missed scheduled session, delivered at the user's own anchor time. Labelled inference (§9.2 item 5, Low confidence) — worth instrumenting rather than assuming.

**Framing, per §9.2:**
1. **Normalize, do not moralize.** Lapses are normative (High confidence, §9.1). Guilt framing maps to introjected regulation → worse well-being, higher dropout (F24). Self-compassion is associated with faster resumption (F23, Adams & Leary — Low confidence transfer to exercise, stated honestly).
2. **Attribute to specific, temporary, controllable causes.** "Busy week" not "no discipline" (§9.2 item 6, Low-Moderate — strong theory, thin exercise trials).
3. **Make re-entry the lowest-friction action available.** The message's CTA is the **floor session**, one tap, ~10 minutes — not the full missed workout. §9.2 item 3: after a lapse the barrier is psychological as much as practical, and a reduced-scope option "produces a mastery experience rather than a second failure."
4. **Reward the return.** Log and acknowledge it as a `returns_after_miss` event. This is the direct product analogue of the megastudy's top-performing lever (F21). Keep the acknowledgement intrinsic and specific rather than a points award — F19/F20 show extrinsic incentives produce trivial effects that don't outlive their removal, and §7.3 notes the SDT motivation-crowding risk (mixed evidence, Low-Moderate, but a real risk if a reward becomes the reason for showing up).
5. **Use the user's own coping plan.** If they selected "too tired after work" at H2 and chose "then I do the 10-minute version at lunch," the message says that back to them. This is why H2 exists.

**A concrete contrast.**

| Naive / guilt-based | Evidence-aligned |
|---|---|
| "You broke your 12-day streak. Don't lose your progress!" | "Two sessions missed this week — that's normal, and it doesn't undo anything you've built. Want the 10-minute version tonight?" |
| Loss framing on an accumulated possession | Normalizes, states the true fact (F5: a miss doesn't set the trajectory back), offers the lowest-friction re-entry |
| Implies the miss destroyed something. Manufactures the violation that triggers the abstinence-violation cascade (F23) — and the claim is **not even true** per F5 | Preserves the honest record via completion rate, which degrades gracefully (F31) |
| Produces guilt → introjected regulation → short-term compliance at best, dropout at worst (F24) | Supports autonomy (a choice), competence (an achievable ask), relatedness (non-judgmental) — the three SDT needs (§8.3) |
| Zeroes the counter at the moment of return — **which is exactly what `update_streak_on_finish` does today** | Increments a `returns_after_miss` statistic at the moment of return |

**Frequency governance.** A `NotificationLog` should exist from day one, both to hard-cap message volume per user per week and — more importantly — to make the interventions *measurable*. Given that only 8% of 54 megastudy programs had effects that outlived them (F20), the app should assume its own notifications are ineffective until its own data says otherwise, and it cannot form that judgment without logging what was sent to whom and when.

---

## 6. What should NOT change for this goal

Being explicit here matters, because the temptation is to build a parallel `build_habits` pipeline. Almost none of that is warranted.

**Unchanged, no goal-specific logic needed:**

1. **Exercise selection and the underlying training science.** A habits user doing squats, rows, and presses is doing the right exercises. Nothing in the report suggests exercise choice differs for a consistency goal — §3.2 is explicit that even the HIIT-vs-MICT adherence question has no clean answer, and warns against claiming otherwise.
2. **The prescription layer proposed in `coach-integration-strategy.md`.** It should apply to `build_habits` unchanged, with the goal row simply configured toward the conservative end and the first-block ramp lengthened. Do not build a separate generation path.
3. **The adaptation engine's load rules** (R1/R2/R3 and the proposed rewrite). Progressive overload is not goal-dependent; a habits user who hits the top of a rep range should still get more load.
4. **PR detection and `PersonalRecord`.** These are mastery experiences — Bandura's strongest efficacy source (§5) — and they are already implemented. They serve this goal well as-is.
5. **`WorkoutFeedback.difficulty`.** Adequate for the escalation gate. The 1–10 sRPE upgrade proposed for the muscle goal is fine but not habits-motivated.
6. **The plan JSON schema**, apart from one addition (§6.2). No new per-exercise fields are needed for this goal.
7. **The anonymous preview → save-preview flow.** The habits questions land after signup, so this flow is untouched.
8. **Equipment, injuries, priority muscles, environment handling.** All orthogonal.
9. **Total volume, `total_volume` display, the volume chart.** Keep them — but they should not be the *primary* framing on `/progress` for this goal, and specifically **do not add physique/weight metrics** as the reinforcement channel (§12.4, Moderate-High: appearance motives map to introjected regulation).

**The one thing people will want to change that they shouldn't:** reducing training frequency to make the plan easier. §3.2 and F4 both point the other way — automaticity is a function of repetition count, so **frequency is the habit lever and should be protected**; per-session demand is what gets cut. Cutting from 4 short sessions to 2 long ones is exactly backwards for this goal.

---

## 7. Architecture implications

Proposal level. No implementation here.

### 7.1 Data model

**New — `ScheduledSession` (`apps/workouts`), the keystone object.**
`(user, plan, workout_day, scheduled_date, status ∈ {pending, completed, missed, rescheduled, skipped_intentionally}, session FK nullable, scope ∈ {full, floor})`. Materialized ~2 weeks forward from the user's chosen weekdays, rolled forward by a job. This is the denominator for completion rate, the trigger source for L0–L4, and the fix that makes a scheduled-day streak definable. It also unblocks R7 in the muscle proposal, so it is shared infrastructure. `skipped_intentionally` matters: a user who deliberately takes a rest week should not be counted as lapsing, and offering that option is itself an autonomy support.

**New — `HabitPlan` (new `apps/habits`, or `apps/onboarding`).**
`(user, scheduled_weekdays, anchor_type, anchor_text, fallback_time, barriers JSON, coping_plans JSON, floor_session_enabled, last_respecified_at)`. Recommend a **separate model from `OnboardingProfile`**, for two reasons: it is goal-conditional (bloating a shared profile with nullable habits fields is a smell), and it is *mutable by design* — §4.2 notes plan fragility and the need for periodic re-specification, whereas `OnboardingProfile` is a point-in-time snapshot. `last_respecified_at` supports prompting a re-plan after a detected disruption.

**Changed — `WorkoutStreak` (`apps/progress`).**
Keep the model; change the semantics and add fields: `returns_after_miss` (int), `grace_remaining` (int). `update_streak_on_finish` becomes scheduled-session-based, and **must stop resetting on return** — a gap ends the current streak but the return increments `returns_after_miss` and produces a positive acknowledgement. Consider renaming the user-facing label away from "streak" entirely.

**New — `ConsistencySnapshot`, or computed on read.**
Rolling 4-week completion rate, sessions/week, and the prior-window comparison. Recommend **computing on read initially** (the query is small and the user base is not) and denormalizing only if `/api/progress/summary/` gets slow. Avoids a second source of truth early.

**New — `AutomaticityCheck`.** `(user, taken_at, item1..item4, score)` — monthly SRBAI. Cheap; the only direct measure of the target construct (F30).

**New — `NotificationLog`.** `(user, kind, rule_triggered, sent_at, opened_at, converted_to_session)`. Frequency capping plus effectiveness measurement.

**Changed — `WorkoutSession`.** Add `scheduled_session` FK (nullable — ad-hoc extra sessions remain valid and should count positively). **Start writing `ABANDONED`** — via an explicit user exit and/or a timeout sweep for sessions left `in_progress` past a threshold. Add `scope ∈ {full, floor}` so floor sessions are distinguishable in analytics without being second-class in the completion rate.

**Changed — `OnboardingProfile`.** `scheduled_weekdays` (JSON list of ints) supplementing `training_days`; `training_days` can remain as a derived/denormalized convenience so nothing downstream breaks. Standard additive migration; existing rows keep working with a null weekday list and fall back to today's behavior.

### 7.2 Plan generation — small, bounded changes

This is deliberately the shortest section, which is the point of the whole proposal.

1. **One schema addition:** each `WorkoutDay` gains a `floor_version` — an ordered subset (1–2 exercises, ~10 min) the AI selects from that day's exercises. Everything else in `_SCHEMA_INSTRUCTIONS`, `_to_display_shape`, `_validate_display_shape`, and `persist()` is unchanged in shape.
2. **Prompt additions gated on `goal == build_habits`**, roughly: hold the user's chosen frequency (do not reduce days); target the lower end of the session-duration budget for the first block; RIR 3–4 with an explicit "choose your own intensity within this band" note; avoid exercises with high technique-failure risk in week one (a failed first attempt is an anti-mastery experience per §5); emit the floor version.
3. **Phased presentation**, not a phased prescription: the preview shows the conservative first block plus what weeks 5–8 and 9+ look like, so "easier" doesn't read as "thin" (§2.3).
4. **Escalation gating:** the existing/proposed adaptation engine should require *both* a high rolling completion rate and non-"hard" feedback before ramping a `build_habits` user. This is a condition on an existing rule, not a new rule.

Everything else in `plan_generator.py` — split logic, equipment constraints, injury handling, priority muscles, adaptation-note folding — is untouched.

### 7.3 New product surfaces (the actual work)

| Surface | What it is | Notes |
|---|---|---|
| **Notification delivery** | Does not exist in any form today | **Pragmatic v1: `flutter_local_notifications` scheduled client-side** from the `HabitPlan` schedule. Covers L0 (the cue reminder — the highest-volume, most valuable case) with **no backend scheduler, no push service, no token storage**. Push + a server-side job runner is only needed for L2/L4, which depend on server-side state. Sequencing this way avoids blocking the whole proposal on infrastructure. |
| **Background job runner** | Celery beat / django-q / a management command on cron | Needed to materialize `ScheduledSession` rows, mark `missed`, evaluate L2–L5, and sweep abandoned sessions. Genuinely new infrastructure. |
| **If-then capture (H1, H2)** | Two post-signup screens | New route after `/signup`, before `/`. `app_router.dart`'s single `redirect` callback is where this gate belongs — per `CLAUDE.md`, do not add ad hoc `context.go()` guards. |
| **Progress screen rework** | `progress_screen.dart` currently leads with two `_StatTile`s: Current Streak and Longest Streak | Replace the primary row with rolling completion rate + sessions/week; demote streak; add returns-after-miss. `ProgressSummaryView` and `progress_models.dart` change shape together. |
| **Floor session CTA** | Home screen + the L2 notification deep-link | The lowest-friction start action in the app. Per F6, instigation is the formable construct — this surface *is* the habit intervention. |
| **Re-engagement sheet** | What the L2/L4 deep-link opens | Normalizing copy, the user's own coping plan, floor-session CTA, and a reschedule option. |
| **Re-specification flow** | Triggered by L3/L4 | Change days, change anchor, change dose. Cheap to build (it is H1 re-run) and directly addresses documented plan fragility (§4.2, §10). |
| **Monthly automaticity check** | 4 SRBAI items, one screen | Private trend, not a headline score (§12.3 — its motivational effect when shown to users is unstudied). |
| **Post-session affect elicitation** | One optional tap on the existing `/workout/:sessionId/reflection` screen | "How do you feel compared to before?" **Elicited, never promised** (§12.4). Reuses an existing surface. |
| **Coach copy rules** | Applies to `insight_generator.py` and all notification copy | No guilt, no loss framing, no failure language, no habit-timeline promises, no appearance framing for this goal. `_build_prompt` in `insight_generator.py` currently asks for "encouraging, specific insights" with a `consistency` category — it needs goal-conditional constraints, and it currently has **no visibility into misses at all** (it only sees completed sessions), so it cannot presently say anything intelligent about a lapse. |

### 7.4 Suggested sequencing

- **Phase 0 (defect fix, tiny, ship regardless of this proposal):** fix `update_streak_on_finish` so it does not reset on every non-consecutive day. Even with no other change, today's behavior is wrong for every user training fewer than 7 days a week.
- **Phase 1 (no new infrastructure):** weekday picker replacing the days slider; `ScheduledSession`; rolling completion rate + frequency on `/progress`; streak redefined on scheduled days and demoted; `returns_after_miss`; start writing `ABANDONED`.
- **Phase 2 (habits onboarding):** `HabitPlan`; H1/H2 post-signup screens; client-side local notifications for L0.
- **Phase 3 (plan-side):** floor sessions in the generator + schema; conservative first block; phased preview presentation; escalation gating.
- **Phase 4 (server-side lapse machinery):** job runner; L2–L5 rules; push; re-engagement and re-specification flows; `NotificationLog`.
- **Phase 5 (measurement):** monthly SRBAI; affect elicitation; effectiveness readouts on the Phase 4 interventions.

---

## 8. Tradeoffs, stated explicitly

**8.1 Conservative first block vs. an impressive preview plan.** Covered in §2.3. The evidence for under-prescribing early is Moderate and mechanistically well-supported, but §3.1 concedes there are few direct head-to-head RCTs. The conversion risk is real and immediate; the adherence benefit is diffuse and delayed. Recommendation: make it easier, fix the perception with phased presentation, and A/B it on 8-week retention rather than treating it as settled.

**8.2 Fixing the streak vs. removing it.** Removing it is arguably the most evidence-consistent action (F22: no isolating RCT support; §7.3: known failure modes). But streaks are partly self-monitoring, which *is* well-evidenced (High), and removing a visible feature users may already value is a product cost the science doesn't require. Recommendation: fix, forgive, demote — the middle path. Note honestly that forgiveness mechanics themselves have no direct trial evidence in exercise.

**8.3 Notifications are the main lever and also the main risk.** Everything valuable in §5 requires messaging users. Notifications are also the fastest way to get uninstalled, and F20 says most such programs don't outlive themselves. Recommendation: start with L0 (the user's own requested cue, at their own chosen anchor — the least intrusive and most clearly wanted), hard-cap volume, log everything, and expand only on evidence.

**8.4 Two screens post-signup is still friction, at a moment that matters.** H1/H2 sit between account creation and the first workout — a point where momentum is high but fragile. Alternative: defer H2 (barriers/coping) until after the first *completed* session, when the user has real experience to draw on. Cost: no coping plan is available if they lapse before session two, which is a plausible failure window. Recommendation: keep both post-signup but make H2 skippable and re-offer it after session one if skipped.

**8.5 `build_habits` may be selected by users who don't want a "habits product."** Some who pick it just mean "I'm a beginner." The conditional machinery is therefore firing on an imperfect signal. Mitigation: make the habits surfaces additive and non-blocking rather than a different-looking app, and let the goal be changed later without penalty.

**8.6 Measurement honesty.** Finding 33 (High) is that self-reported PA is heavily inflated versus objective measurement, and the least-active over-report the most. App-logged completion rates will therefore look *worse* than published adherence benchmarks derived from self-report. Do not conclude the product is underperforming on that comparison, and do not show users a benchmark drawn from that literature.

**8.7 Scope boundary.** This proposal does not address social features, group challenges, or human coach check-ins. §6 gives the best evidence to *personalized, low-judgment human contact* (Moderate-High for human-supported digital interventions beating fully automated ones) and the weakest to buddy systems, public commitment, and leaderboards (Low). A human-in-the-loop check-in is therefore the most promising unexplored direction here — and is a separate strategy question, because it is an operations and cost problem, not a software one.
