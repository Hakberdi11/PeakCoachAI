# Peak Coach AI — audit checklists by subsystem group

Loaded during the Hunt phase of `/full-codebase-audit`. Each group below is one
subagent dispatch. Copy the matching section verbatim into that agent's prompt
— don't just point the agent at this file, since a fresh subagent has no
reason to weigh these checks over generic ones otherwise.

Every item here exists because it is a *specific, real* risk in *this*
codebase, not a generic "check for bugs" reminder. If a hunter can't tie a
finding to one of these (or an equally concrete, project-grounded observation
of their own), it does not belong in the report.

## Contents
- Group 1: users + onboarding (backend)
- Group 2: workouts models/services (backend)
- Group 3: workouts views/urls/serializers (backend)
- Group 4: progress + adaptation (backend)
- Group 5: ai_engine (backend)
- Group 6: core/ plumbing (frontend)
- Group 7: auth + onboarding (frontend)
- Group 8: workouts (frontend)
- Group 9: progress (frontend)
- Cross-cutting checks (apply to every group)

---

## Cross-cutting checks (apply to every group, backend and frontend)

- **App-label drift**: Django `AppConfig.name` is `apps.<name>` but `app_label`
  is the bare `<name>` (e.g. `AUTH_USER_MODEL = 'users.User'`, not
  `'apps.users.User'`). Grep for any FK/`ForeignKey('...')` string reference or
  `app_label` usage that got this backwards.
- **Migration/model drift**: does every model field have a matching, applied
  migration? Would `makemigrations --check --dry-run` report anything?
- **No test suite exists** (documented in CLAUDE.md) — don't flag "add tests"
  as a generic finding, but DO flag specific pure-function logic added
  recently with no other verification path (e.g. `estimate_1rm`,
  `compute_prescription`, `_grace_days`) if you find a case where it's
  actually wrong, since nothing else would catch it before production.
- **Ownership checks**: any endpoint or query touching a user's own data
  (plans, sessions, sets, streaks, coaching notes) must filter by the
  requesting user. Look for a query that trusts a client-supplied ID without
  a `user=request.user` (or equivalent) constraint — that's an IDOR.
- **Silent `except`/broad catches** that could hide a real failure rather than
  surface it.
- **Dead code from the recent prescription-layer rewrite**: anything left over
  that referenced the old `training_style` field, the old string
  `workout_duration` choices (`'30'`/`'45'`/`'60'`/`'90+'`), or the old
  `_validate_display_shape`/flat structural-only validation.

---

## Group 1: users + onboarding (backend)

Scope: `backend/apps/users/`, `backend/apps/onboarding/` (models, serializers,
views, migrations — read every `.py` file except migrations, which you may
skim for drift only).

- Custom `User` model: is `USERNAME_FIELD='email'` handled consistently
  everywhere a username might normally be assumed (Django admin, serializers,
  JWT claims)?
- JWT issuance/refresh: token lifetimes, whether refresh tokens are rotated
  or blacklisted on logout, whether `password` ever leaks into a serialized
  response.
- `OnboardingProfileSerializer` — since `GeneratePlanPreviewView` reuses this
  *exact* serializer for an anonymous, unsaved profile, check that no field
  validation implicitly depends on the profile already having a `user`/`pk`
  (e.g. a validator that queries `OnboardingProfile.objects.get(user=...)`
  would break the anonymous path).
- `workout_duration` is now a `PositiveSmallIntegerField` (15–120) and
  `training_style` was removed — confirm nothing in this app still reads or
  writes either the old string values or the removed field.
- `OnboardingProfileView.post` uses `update_or_create` — confirm partial
  payloads can't silently null out fields that were previously set.

## Group 2: workouts models/services (backend)

Scope: `backend/apps/workouts/models.py`,
`backend/apps/workouts/services/{plan_generator,prescription,estimation,session_service,plan_edit_service}.py`.

- `prescription.py`: for every goal × experience combination, do the
  `sets`/`reps`/`rest`/`rir` tuples make internal sense (min ≤ max, no
  accidentally swapped bounds)? Does `_estimate_exercise_count` ever produce
  `low > high` or a range below `_MIN_EXERCISES_PER_DAY`?
  `validate_against_prescription`'s slack math (`sets_lo - 1`, `reps_hi + 4`,
  etc.) — verify it can't go negative or invert min/max after the slack is
  applied.
- `plan_generator.py`: `persist()` now calls `compute_prescription` and
  requires an `OnboardingProfile` to exist — confirm every caller path
  (`generate`, `revise`, `save-preview` via the view) actually has a saved
  profile *before* `persist()` runs, otherwise a real user hits
  `PlanGenerationError` where they shouldn't.
- `revise()`: builds `_build_revision_prompt` from
  `_plan_to_display_shape(current_plan)` — confirm this round-trips the same
  shape `_to_display_shape` produces from a fresh AI response, so a second
  revision doesn't silently drop `target_rir` or reorder days.
- `session_service.log_set`: the e1RM/warmup-aware PR query
  (`Q(exercise_log__exercise_name=active_name) |
  Q(exercise_log__replaced_with_name=active_name)`) — construct the concrete
  case where a user replaces exercise A→B, then later in a *different*
  session replaces C→B. Does the OR-query now conflate B's history across two
  unrelated original exercises?
- `plan_edit_service`: `add_exercise`/`remove_exercise`/`reorder_exercises`
  operate on a `WorkoutDay` fetched by the view as
  `plan__user=request.user, plan__is_active=True` — confirm every function in
  this file that takes a `day`/`exercise` object never needs its own
  ownership check bypassed by a caller that skips the view layer.
- `estimation.estimate_1rm`: verify the `reps <= 1` branch and the Epley
  formula don't produce a *lower* estimated 1RM for more reps at the same
  weight (which would invert PR ranking).

## Group 3: workouts views/urls/serializers (backend)

Scope: `backend/apps/workouts/views.py`, `urls.py`, `serializers.py`.

- Every view that mutates a `WorkoutPlan`/`WorkoutDay`/`PlannedExercise` must
  scope its lookup to `plan__user=request.user` (or via
  `plan__is_active=True` where that matters) — check
  `PlanDayExercisesView`, `PlanDayExercisesReorderView`,
  `PlanExerciseDetailView`, `RevisePlanView` specifically, since these are new.
- `ExerciseListView`: the equipment filter builds a Python list from a
  queryset (`[exercise for exercise in queryset if ...]`) — confirm this
  doesn't break pagination/ordering assumptions elsewhere, and isn't an N+1 in
  disguise if the catalog grows.
- `StartSessionView`'s stale-session-abandon update — confirm the
  `WorkoutSession.objects.filter(...).update(...)` runs *before* the new
  session is created and can't race with a concurrent request from the same
  user (double-tap "start workout").
- `SavePreviewPlanView` passes `request.data` straight into
  `WorkoutPlanGenerator().persist()` — confirm `persist()`'s prescription
  validation actually runs before any DB write in all cases (not just the
  happy path), so a malformed/malicious payload can't create partial
  `WorkoutDay`/`PlannedExercise` rows before validation fails.
- Do all serializers exclude fields that shouldn't reach the client (internal
  IDs that leak cross-user information, raw AI response internals)?

## Group 4: progress + adaptation (backend)

Scope: `backend/apps/progress/`, `backend/apps/adaptation/` (models, services,
views — all files).

- `streak.py` `_grace_days`: verify the `math.ceil(7 / training_days) + 1`
  formula against each valid `training_days` value (2–6) — construct the
  boundary case where a user trains on their last allowed day of the grace
  window vs. one day past it, and confirm the streak behaves as intended in
  both directions (increment vs. reset).
- `rolling_completion_rate`: uses `WorkoutSession.status=COMPLETED` and
  `started_at__gte=window_start` — a session started before the window but
  finished inside it, or vice versa, is excluded/included how? Is that the
  intended edge?
- `engine.evaluate_reps`/`evaluate_feedback`: `_athlete_goal` does a fresh
  query per call — fine functionally, but check whether `evaluate_reps`
  iterating `session.exercise_logs.all()` triggers an N+1 on
  `log.sets.all()` and `log.planned_exercise` per iteration (no
  `select_related`/`prefetch_related`).
- `CoachingNote`: confirm nothing ever queries this without
  `user=request.user`/`user=session.user` — a leaked note from another user
  folded into a prompt would be a real privacy bug, not just a style issue.
- `PersonalRecord` creation in `session_service.log_set` — is it ever
  possible to create two `PersonalRecord` rows for the same
  session+exercise+weight+reps (double submission, retry after timeout)?

## Group 5: ai_engine (backend)

Scope: `backend/apps/ai_engine/` (all files).

- `OpenAIProvider.generate_completion`: no timeout is set on the OpenAI
  client call — confirm what happens to the request (and the DB transaction
  state in `persist()`, if called from within one) if OpenAI hangs.
- Prompt construction anywhere in this app: is any raw user-supplied free
  text (onboarding `injuries`, the new `revise` `instruction` field)
  interpolated into a prompt without limiting length — could a very long
  instruction blow the context or cost budget unbounded?
- `_try_parse`'s JSON parsing — is `json.loads` ever called on
  attacker-influenced input in a way that could raise something other than
  `JSONDecodeError`/`TypeError` and escape the except clause?
- `AIInsight`/`insight_generator` caching (24h, per CLAUDE.md) — confirm the
  cache key is scoped per-user and can't return one user's insight to
  another.

## Group 6: core/ plumbing (frontend)

Scope: `frontend/lib/core/` (network, router, theme — all files).

- `AuthInterceptor`: refreshes and retries once on 401. Construct the case
  of two concurrent requests both getting 401 at the same time — does each
  independently trigger its own refresh (wasting a refresh token / racing),
  or is there a shared in-flight-refresh guard? If there's no guard, that's a
  real bug, not speculative — trace the actual code to confirm either way.
- `app_router.dart`'s centralized `redirect` callback — does every new route
  added recently (if any) actually go through this, or does anything call
  `context.go()`/`context.push()` in a way that bypasses a guard the redirect
  callback is supposed to enforce?
- `dioProvider` — is the base URL/timeout config read once at provider
  creation in a way that would go stale if `AppConfig` changes at runtime
  (unlikely to matter here, but confirm there's no such assumption being
  silently violated)?

## Group 7: auth + onboarding (frontend)

Scope: `frontend/lib/features/auth/`, `frontend/lib/features/onboarding/`
(all files).

- `onboarding_flow_screen.dart`'s new `_buildSteps` is computed fresh on every
  `build()` — confirm no step's `child` widget loses `TextEditingController`
  state across rebuilds (the age/height/weight/injuries controllers are
  field-level, not step-level, so check they still map correctly to the
  right step after the switch→list refactor).
- `OnboardingDraft.workoutDuration` changed from `String?` to `int?` — grep
  the whole frontend tree for any remaining place that might still treat it
  as a string (string interpolation that silently "works" either way is a
  common place this kind of migration hides a bug).
- `signup_screen.dart`: confirms the actual call order is
  `onboardingRepository.submit(draft)` before `workoutRepo.savePreview(preview)`
  — re-verify this ordering is still intact, since the backend's `persist()`
  now depends on the profile already existing (see Group 2's finding on
  this exact dependency).
- Token storage (`token_storage.dart` wrapping `flutter_secure_storage`) — is
  the token ever logged (the `LogInterceptor` is added in debug builds only —
  confirm it doesn't log the Authorization header in plaintext).

## Group 8: workouts (frontend)

Scope: `frontend/lib/features/workouts/` (all files — data, state,
presentation, widgets, including the new `add_exercise_sheet.dart`,
`edit_exercise_dialog.dart`, `plan_overview_screen.dart`,
`plan_days_list.dart`).

- `PlanOverviewScreen`: every mutation handler (`_deleteExercise`,
  `_editExercise`, `_addExercise`, `_submitRevision`) calls
  `ref.invalidate(activePlanProvider)` — confirm none of the paths can return
  early (an error, a cancelled dialog) while still appearing to have
  succeeded, i.e. that the UI never shows stale data after a failed edit.
- `AddExerciseSheet`/`EditExerciseDialog`: `int.tryParse(...) ?? <default>`
  on every numeric field — if the user clears a field entirely and submits,
  does it silently fall back to a default instead of showing a validation
  error? Decide if that's actually the intended UX or a swallowed-error bug.
- `WorkoutRepository`: does any new method (`revisePlan`, `addExercise`,
  etc.) fail to surface a `DioException` distinctly from other errors the way
  `fetchActivePlan` does for 404 — i.e., would a network failure and a 422
  validation failure look identical to the UI?
- `plan_preview_screen.dart` (the pre-signup read-only reuse of
  `PlanDaysList`) — confirm the new `editable`/`onEditExercise`/etc.
  parameters default to inert (`false`/`null`) so this screen's behavior is
  provably unchanged, not just assumed unchanged.
- Session execution screens (workout/reflection) — do they still match what
  `SetLogSerializer` and `log_set` now return/accept (`rir`, `is_warmup`), or
  is there a UI gap where the backend supports these fields but nothing in
  the app can ever set `is_warmup=true` yet (worth noting even if it's an
  intentional scope gap, per the project's phased plan)?

## Group 9: progress (frontend)

Scope: `frontend/lib/features/progress/` (all files).

- Does the progress screen consume the new `rolling_completion_rate` field
  from `/api/progress/summary/`, or is it silently ignored client-side
  (i.e., backend ships it but no UI surfaces it yet)?
- `total_volume`/streak display — any client-side assumption that streak is
  still a naive "consecutive calendar days" count (e.g. UI copy that says
  "day streak" in a way that would mislead given the new grace-window
  behavior)?
