# DrowzyDiary mobile app

A Flutter implementation of the `DrowzyDiary.dc.html` design
(claude.ai/design project `188117e3-411b-440c-bad0-d0386dcf16bd`): an auth
screen, a 3-tab home (Recap / Check-in / Profile), a night/morning-themed
check-in chat, and a recap detail view with crisis-line handling — backed
by Supabase Auth and the FastAPI service in [`../backend`](../backend).

## Setup

```bash
cp .env.example .env   # fill in your Supabase URL/anon key
flutter pub get
flutter run -d chrome --web-port=8080
```

`.env` is loaded at startup via `flutter_dotenv` (see `main.dart` and
`lib/services/env.dart`) — no more `--dart-define` flags needed. It's
gitignored, same as the backend's. `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` are
the same Supabase project the backend points at (Project Settings > API
Keys in the Supabase dashboard — this is the public `sb_publishable_` key,
not the backend's secret key; the legacy `SUPABASE_ANON_KEY` name still
works as a fallback). `API_BASE_URL` defaults to `http://localhost:8000` if
omitted.

The `--web-port=8080` matters if you're running in Chrome: it has to match
one of the origins in the backend's `ALLOWED_ORIGINS` (`.env`), or every
API call fails CORS preflight. Not needed when running on a simulator/
device instead of Chrome.

### Google sign-in setup

"Continue with Gmail" is wired to a real Supabase OAuth flow
(`AuthService.signInWithGoogle`), but needs configuration this repo can't
do for you:

1. Enable the Google provider under Authentication > Providers in the
   Supabase dashboard, with a Google Cloud OAuth client ID/secret.
2. Add `com.drowzydiary.drowzydiary://login-callback` to the redirect URL
   allow-list under Authentication > URL Configuration.

The Android intent-filter and iOS `CFBundleURLTypes` for that redirect
scheme are already in place (`android/app/src/main/AndroidManifest.xml`,
`ios/Runner/Info.plist`) — don't need to match anything on the web build,
where the OAuth redirect goes through the browser's own URL instead.

## Layout

- `lib/theme/` - night/morning `Palette`s, Nunito text theme, and the
  bedtime-mode grayscale `ColorFilter`.
- `lib/models/` - plain data classes (chat message, recap entry/group,
  sleep factor).
- `lib/data/` - EN/ID copy (`strings.dart`), translation lookup tables,
  and date/weekday formatting (`date_format.dart`).
- `lib/services/` - `AuthService` (the only place that touches Supabase
  Auth directly), `ApiClient` (adds the bearer token to every backend
  call), and `ChatService`/`RecapService`/`ProfileService` on top of it.
- `lib/state/app_state.dart` - single `ChangeNotifier` holding all app
  state and actions (screen/auth mode/active tab, chat messages, recap
  filter/selection, profile settings), talking to the network only through
  the services above.
- `lib/screens/` - `AuthScreen`, `HomeScreen` (+ `screens/tabs/` for Recap /
  Check-in / Profile), `ChatScreen`, `RecapDetailScreen`.
- `lib/widgets/` - shared pieces: crescent-moon/sun icons (custom painters),
  segmented toggle, filter pill, chat bubble, typing indicator, sleep bar
  chart, factor tile, bottom nav bar, breathing circle, twinkling
  `StarFieldBackground`, `DeleteConfirmModal`,
  `NotificationBanner`, `GoogleLogo` (rendered via `flutter_svg`).

## Feature notes

- **Delete confirmation**: the recap detail trash icon now opens a confirm
  step (`requestDeleteEntry` → `showDeleteConfirm`) before the entry is
  actually removed.
- **Notification preview**: the two "preview night/morning reminder" links
  on the Check-in tab show a fake system-notification banner
  (`NotificationBanner`) that auto-dismisses after 6s; tapping it deep-links
  into that check-in, like tapping a real push notification would.
- **Password confirmation**: signup requires a matching confirm-password
  field before it will submit; the mismatch error only appears after a
  submit attempt, not while still typing.

## Notes on fidelity

- Chat replies, crisis detection and sleep-factor detection are real and
  come from the backend.
- The crisis-line handling (Healing119, 119 ext. 8) is a real rule-based check
  on the backend (`app/services/safety.py`), not LLM-decided.
- A few icons (send, back, delete, nav icons) use standard Material
  icons as stand-ins for the design's hand-drawn SVGs; the moon and sun,
  which recur throughout and define the app's day/night identity, are
  recreated as custom painters for fidelity.
