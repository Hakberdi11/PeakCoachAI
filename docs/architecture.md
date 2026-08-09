# Architecture

Peak Coach AI is split into two independent projects that communicate only over REST/JSON:

```
Flutter (Riverpod, go_router, dio)
        │  REST/JSON (JWT-authenticated, once auth ships)
        ▼
Django + Django REST Framework
  apps/core          — health check, shared utilities
  apps/users         — accounts / profiles
  apps/onboarding    — onboarding data
  apps/workouts      — plans, sessions, logs
  apps/progress      — streaks, PRs, history
  apps/adaptation    — rule-based adaptation history
  apps/ai_engine     — AI service layer
        │
        ▼
   PostgreSQL
```

Flutter never talks to Postgres or Django internals directly — every interaction goes through a DRF endpoint.

## Auth

`djangorestframework-simplejwt` is installed and `JWTAuthentication` is registered as the default DRF authentication class, but no login/refresh views exist yet — those land with the auth feature plan.

## AI service layer

To keep OpenAI calls out of application logic and make swapping providers (Claude, Gemini, open-source) a non-event, all AI access goes through a layered interface:

```
Application logic → AIServiceProvider (apps/ai_engine/services/base.py)
                           └── OpenAIProvider (apps/ai_engine/services/openai_provider.py)
```

`OpenAIProvider` currently raises `NotImplementedError`; it's implemented alongside AI workout plan generation.

## Status

This is the foundational scaffold only. This document will grow as future plans land: authentication, onboarding, AI plan generation, workout execution, progress tracking, AI insights, and the adaptation engine.
