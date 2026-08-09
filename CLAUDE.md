# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Peak Coach AI — an adaptive AI fitness coach app. Django/DRF backend + Flutter frontend, fully independent projects that talk only over REST/JSON. See `docs/architecture.md` and `README.md` for more.

## Commands

### Backend (`backend/`)

```bash
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env   # then fill in DB creds, OPENAI_API_KEY, etc.
createdb peak_coach_ai

python manage.py makemigrations <app>   # after model changes, per-app
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

There is no written test suite yet (each app has an empty `tests.py` stub). Verification during development has been done via `curl` against the running server — there's no `pytest`/`manage.py test` command to reach for.

No linter/formatter is configured for the backend.

### Frontend (`frontend/`)

```bash
cd frontend
flutter pub get
cp .env.example .env   # API_BASE_URL — use http://10.0.2.2:8000 for the Android emulator, http://localhost:8000 for iOS sim/macOS

flutter analyze         # static analysis — keep this clean
flutter test             # runs test/widget_test.dart (a boot smoke test only)
flutter run -d <device>  # e.g. -d macos, -d emulator-5554
```

`flutter devices` / `flutter emulators --launch <id>` to list/start simulators. macOS debug builds have `app-sandbox` disabled in `macos/Runner/DebugProfile.entitlements` (flutter_secure_storage needs Keychain entitlements the local "sign to run" build doesn't have) — this only affects local macOS desktop testing, not iOS/Android or Release builds.

## Architecture

### Backend: Django apps under `backend/apps/`

Each app's `AppConfig.name` is `apps.<name>` (so imports are `apps.users.models` etc.), but **Django's `app_label` for each is just `<name>`** (the last dotted component) — e.g. `AUTH_USER_MODEL = 'users.User'`, not `'apps.users.User'`. Keep this in mind for any FK/`app_label.Model` string reference.

- **`users`** — custom `User` model (`AbstractBaseUser` + `PermissionsMixin`), email as `USERNAME_FIELD` (no username field). JWT auth via `djangorestframework-simplejwt`; `/api/auth/register|login|refresh|me/`.
- **`onboarding`** — `OnboardingProfile` (one-to-one with `User`), one `APIView` at `/api/onboarding/` (`GET` retrieve / `POST` upsert-and-set-`completed_at`).
- **`workouts`** — the biggest app:
  - `WorkoutPlan` → `WorkoutDay` → `PlannedExercise` (the AI-generated split).
  - `WorkoutSession` → `ExerciseLog` → `SetLog`, plus `WorkoutFeedback` (execution/logging). History is append-only — nothing here is ever overwritten, only new rows added and status fields updated.
  - `services/plan_generator.py` (`WorkoutPlanGenerator`) — builds the OpenAI prompt from an `OnboardingProfile`, parses/validates the JSON response, and either returns it unpersisted (`generate_preview*`) or writes it to the DB (`persist`/`generate`).
  - `services/session_service.py` — set-logging, skip/replace-exercise, PR detection (compares each new set's weight against the user's historical best for that exercise name before creating the `SetLog` row — order matters, see the function body).
- **`progress`** — `PersonalRecord`, `WorkoutStreak` (+ `services/streak.py`, called on session finish). `/api/progress/summary/` and `/history/`.
- **`adaptation`** — `AdaptationHistory` + `services/engine.py`, rule-based (no ML): rep-based load adjustments are evaluated on session finish (`evaluate_reps`), feedback-based volume adjustments on feedback submit (`evaluate_feedback`, since difficulty isn't known until then). Recent `AdaptationHistory` rows are folded into the prompt on the next `generate()` call so regenerated plans reflect prior decisions.
- **`ai_engine`** — the AI service layer: `services/base.AIServiceProvider` (interface) → `services/openai_provider.OpenAIProvider` (real implementation, model name from `OPENAI_MODEL` env var). All AI calls in the codebase (plan generation, insight generation) go through this interface, never call OpenAI directly, so swapping providers later doesn't touch calling code. Also holds `AIInsight` + `services/insight_generator.py`, cached for 24h behind `/api/insights/latest/`.

### Backend: the anonymous-preview plan flow

This is the one non-obvious cross-app design worth understanding before touching onboarding/plan/auth code: **onboarding happens before signup**, and the user sees their AI-generated plan before creating an account (deliberate product decision — show value before asking for a signup). Mechanics:

1. `POST /api/workouts/plans/preview/` (`AllowAny`) — takes onboarding answers directly in the request body (validated via `OnboardingProfileSerializer`, never saved), builds an *unsaved* `OnboardingProfile` instance, generates a plan, returns it in "display shape" (`exercise_name`/`target_sets`/... field names) without touching the DB.
2. `POST /api/workouts/plans/save-preview/` (`IsAuthenticated`) — takes that exact same display-shape JSON back and persists it as a real `WorkoutPlan`. **No second AI call** — this guarantees the plan a user saved is identical to the one they previewed.
3. `POST /api/workouts/plans/generate/` (`IsAuthenticated`) — the "normal" authenticated path (used for later regenerations, e.g. after onboarding is redone), which does hit the AI again and folds in `AdaptationHistory`.

`WorkoutPlanGenerator.generate_preview_from_profile()` is the shared core all three paths funnel through.

### Frontend: `frontend/lib/`

Structured as `core/` (cross-cutting) + `features/<name>/{data,state,presentation}/`:

- **`core/network/api_client.dart`** — the shared `dioProvider`. Requests go through `AuthInterceptor` (`core/network/auth_interceptor.dart`), which attaches the JWT access token and, on a 401, transparently refreshes and retries once before giving up and logging out.
- **`core/router/app_router.dart`** — a single Riverpod-backed `GoRouter` with all navigation-guard logic centralized in one `redirect` callback, driven by `authProvider` (features/auth) and `onboardingStatusProvider` (features/onboarding). Read this file first when changing what route a user lands on after any auth/onboarding state change — don't add ad hoc `context.go()` guards elsewhere.
- **`core/theme/`** — brand constants (`app_colors.dart`) are exact spec values, not to be rederived: background `#07111F`, surface `#0D1B2A`, primary accent `#3B82C4`, platinum accent `#D9D9D9`, text `#F8FAFC`, success `#22C55E`, warning `#F59E0B`, error `#EF4444`. Inter via `google_fonts`.
- **State management**: Riverpod throughout (`Provider`, `AsyncNotifierProvider`, `NotifierProvider`, `StateProvider`, `FutureProvider`/`.family`/`.autoDispose` as appropriate) — no other state management library in use.
- **Token storage**: `features/auth/data/token_storage.dart` wraps `flutter_secure_storage`.
- **`features/onboarding/state/onboarding_draft_provider.dart`** holds the in-progress questionnaire answers client-side across the whole multi-step flow (`OnboardingFlowScreen`) until submission.
- **`features/workouts/state/plan_preview_provider.dart`** holds the raw preview-plan JSON from step 1 of the anonymous flow above, so `SignupScreen` can send it verbatim to `save-preview` after account creation.

### Screen flow (frontend routes)

`/onboarding` (multi-step questionnaire, no auth) → `/onboarding/generating` (calls the anonymous preview endpoint, animated) → `/onboarding/plan` (shows the generated plan, CTA to `/signup`) → `/signup` (creates the account, then persists onboarding + saves the previewed plan) → `/` (home). Returning users: `/login` → `/`. Post-auth routes: `/plan` (full plan detail), `/workout/:sessionId` (execution) → `/workout/:sessionId/reflection` (post-workout feedback), `/progress` (streak/volume/PRs).
