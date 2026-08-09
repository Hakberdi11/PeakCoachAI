# Peak Coach AI

An adaptive AI fitness coach that creates personalized workout plans, tracks user performance, and learns from user behavior over time.

This repo is currently at the **foundational scaffold** stage: a connected Django + Flutter skeleton with no business features yet. See [docs/architecture.md](docs/architecture.md) for the system overview.

## Tech stack

| Layer     | Tech |
|-----------|------|
| Frontend  | Flutter, Riverpod, go_router, dio |
| Backend   | Django, Django REST Framework |
| Database  | PostgreSQL |
| Auth      | JWT (djangorestframework-simplejwt) |
| AI        | OpenAI API (behind a provider-agnostic service layer) |

## Prerequisites

- Python 3.12
- PostgreSQL 16 (running locally)
- Flutter (stable channel)

## Backend setup

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# edit .env with your local DB credentials / secrets

createdb peak_coach_ai   # or create the DB/role matching your .env

python manage.py migrate
python manage.py runserver
```

## Frontend setup

```bash
cd frontend
flutter pub get

cp .env.example .env
# API_BASE_URL defaults to http://localhost:8000
# Android emulator: use http://10.0.2.2:8000 instead of localhost

flutter run
```

## Verify it works

1. Start the backend (`python manage.py runserver`) and confirm:
   ```bash
   curl -i http://localhost:8000/api/health/
   # HTTP 200, {"status":"ok","service":"peak-coach-ai-backend","database":"connected"}
   ```
2. Run the Flutter app (`flutter run`) — it should boot straight into a themed screen that shows "Backend connected" once the health check succeeds.
3. Stop the Django server and retry from the app — the screen should show a themed error state with a working retry button, and the backend should return HTTP 503 when the database is unreachable.

## Project structure

```
peak-coach-ai/
├── backend/    # Django + DRF API
├── frontend/   # Flutter app
├── docs/       # architecture notes
└── README.md
```

Backend and frontend are fully independent — Flutter communicates with the backend only through the DRF API.
