# DrowzyDiary backend

FastAPI service for chat check-ins, recaps, and profile/sleep data. Supabase
Auth runs in Flutter. Every backend request carries the Supabase access token
in `Authorization: Bearer <token>`.

The backend verifies access tokens locally with the project's asymmetric
public signing keys from:

```text
https://<project-ref>.supabase.co/auth/v1/.well-known/jwks.json
```

The legacy shared JWT secret is not used.

## Setup

```bash
cd backend
python -m venv .venv
# Activate .venv for your shell, then:
pip install -r requirements-dev.txt
cp .env.example .env
```

Fill in the Supabase URL and the secret key (`SUPABASE_SECRET_KEY`,
`sb_secret_...`, from Project Settings > API Keys; the legacy
`SUPABASE_SERVICE_ROLE_KEY` name still works as a fallback). In the Supabase
dashboard, make sure Authentication uses an asymmetric signing key (ES256 or
RS256). The JWKS URL is derived automatically from `SUPABASE_URL`.

In the Supabase SQL editor, run these setup migrations once, in this order:

1. `sql/schema.sql`
2. `sql/ai_emotional_memory.sql`
3. `sql/chat_idempotency.sql`
4. `sql/session_delete_cascade.sql`
5. `sql/chat_rls_read_delete_only.sql`
6. `sql/sleep_factor_orphan_cleanup.sql`
7. `sql/service_role_grants.sql` (last)

`sql/delete_today_checkins.sql` is a dev tool for wiping one user's
check-ins for today. It is not a setup step.

## Run

```bash
uvicorn app.main:app --reload --port 8000
```

Docs are available at `http://localhost:8000/docs`.

## Test

```bash
pytest
```

## Endpoints

- `POST /chat/start` - begin a night or morning check-in
- `POST /chat/message` - send a user message and receive the next reply
- `POST /chat/{session_id}/end` - close a check-in early
- `GET /chat/{session_id}/messages` - retrieve a session transcript
- `GET /recaps` - list past check-ins
- `GET /recaps/{id}` - retrieve one recap and transcript
- `DELETE /recaps/{id}` - delete a recap
- `GET /profile` / `PATCH /profile` - profile and settings
- `GET /profile/sleep/weekly` - weekly sleep hours
- `GET /profile/sleep-factors` - observed, non-causal sleep influencers
