# DrowzyDiary

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A private, voice-first sleep diary and wind-down companion. The idea is
simple: give people a safe, bounded place to dump their worries before bed,
and a quick check-in in the morning about how they slept. Over time those
check-ins turn into a diary you can go back and correct, plus gentle,
non-causal observations about what tends to show up around your bad nights
(late caffeine, doomscrolling, whatever it is for you).

To be clear up front: this is **not** a medical or diagnostic tool. It's a
journaling and reflection app, not therapy and not a sleep clinic.

## What it actually does

- **Evening check-in** — a short, structured conversation to offload
  whatever's on your mind before bed.
- **Morning check-in** — a quick chat about how you slept.
- **Recap history** — every check-in becomes a diary entry you can revisit,
  edit, or delete.
- **Weekly sleep factors** — the app looks for patterns across your entries
  (things like caffeine, stress, screen time) and surfaces them as
  observations, never as a diagnosis or a "this caused that" claim.
- **Crisis safety net** — if a check-in message trips certain risk signals,
  the app immediately stops the normal conversation and shows real crisis
  resources. This part is deliberately rule-based and deterministic, not
  something left up to a model's judgment call, because it has to work the
  same way every single time.

## Repository layout

```
backend/    FastAPI service — auth verification, check-in flow, crisis
            detection, sleep-factor analysis, recaps
frontend/   Flutter app — auth, 3-tab home (Recap / Check-in / Profile),
            the night/morning check-in chat, recap detail view
supabase/   Database schema lives in backend/sql, plus an edge function
            for text-to-speech
```

`backend/` and `frontend/` are independent projects with their own
dependencies — there's no shared build step between them.

## Tech stack

**Frontend**
- Flutter / Dart, targeting iOS, Android, and web out of the box (desktop
  targets are scaffolded too)
- `provider` for state management
- `supabase_flutter` for auth
- `speech_to_text` and `flutter_tts` for voice input/output
- `google_fonts`, `flutter_svg` for the UI

**Backend**
- Python, FastAPI, served with `uvicorn`
- `pydantic` for request/response validation
- `pyjwt` to verify Supabase-issued JWTs locally against the project's JWKS
  endpoint (no separate auth system — Supabase Auth is the source of truth)
- `supabase-py` as the Postgres client
- A locally-run HuggingFace model for emotion classification on check-in
  messages, with an Azure AI Foundry deployment as a fallback when local
  confidence is low, and for generating check-in replies and weekly recaps
- `pytest` for the test suite

**Data**
- Postgres via Supabase, with row-level security scoping every table to
  `user_id`
- Tables: `profiles`, `chat_sessions`, `chat_messages`, `sleep_logs`,
  `sleep_factors`, `sleep_factor_occurrences`

**Other**
- A Supabase Edge Function (TypeScript/Deno) handles text-to-speech via
  Google's API

## Running it locally

You'll need one Supabase project shared between both apps.

### 1. Database

In the Supabase SQL editor, run `backend/sql/schema.sql` once to create the
tables and RLS policies. Under Authentication, make sure the project uses
an asymmetric signing key (ES256 or RS256) — the backend verifies tokens
against the public JWKS endpoint, not a shared secret.

### 2. Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate   # or the equivalent for your shell
pip install -r requirements-dev.txt
cp .env.example .env
```

Fill in `.env` with your Supabase URL, service-role key, and Azure AI
Foundry endpoint/deployment names (see the comments in `.env.example` —
each variable is documented there). Then:

```bash
uvicorn app.main:app --reload --port 8000
```

API docs land at `http://localhost:8000/docs`. Run the tests with `pytest`.

### 3. Frontend

```bash
cd frontend
cp .env.example .env   # fill in your Supabase URL/anon key
flutter pub get
flutter run -d chrome --web-port=8080
```

`API_BASE_URL` in `.env` defaults to `http://localhost:8000`. If you're
running in Chrome, keep `--web-port=8080` — it has to match one of the
origins in the backend's `ALLOWED_ORIGINS`, or every request will get
blocked by CORS. Running on a simulator or physical device instead doesn't
have that restriction.

Google sign-in works out of the box in the sense that the OAuth flow is
wired up (`AuthService.signInWithGoogle`), but you still need to enable the
Google provider in the Supabase dashboard with your own Google Cloud OAuth
credentials, and add the app's redirect URL to the allow-list there.

## License

MIT — see [LICENSE](LICENSE).
