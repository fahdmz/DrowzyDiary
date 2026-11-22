# On-device AI prototype (throwaway)

A debug-only screen to measure whether on-device models are good enough for
the check-in assistant. It uses `flutter_edge_ai` 2.6 with the
`flutter_edge_ai_litertlm` (`.litertlm` models) and
`flutter_edge_ai_builtin_ai` (Gemini Nano / Apple Foundation Models) engines.
It does not touch the app flow, the backend or Supabase.

## Opening it

Run a **debug** build on a **physical** phone. A small chip button
(memory icon) appears at the bottom right of every screen, including the
login screen. In profile and release builds the button and this folder are
compiled out (`kDebugMode`).

Tabs:

- **Model**: pick a model, download it (progress and size on disk), choose
  GPU or CPU, then **Load**. The OS built-in row shows the OS availability
  status and says when it is unavailable.
- **Chat**: Indonesian check-in persona. Each reply shows the time to first
  token, total time, token count (`engine` = LiteRT-LM benchmark counter,
  `tokenizer` = model tokenizer, `chunks` = streamed chunks as a fallback),
  decode tokens per second, and process RSS (current and peak).
- **JSON test**: 10 independent runs on a sample message. Reports strict
  JSON, JSON after stripping extra text, and schema match, plus the raw
  output of each run. "Constrained decoding" can be turned on when the
  loaded model supports `responseFormat`.

## Hugging Face token

Gemma 3n E2B and Gemma 3 1B are gated. Before you download either:

1. Accept the license on each repo page while logged in:
   - https://huggingface.co/google/gemma-3n-E2B-it-litert-lm
   - https://huggingface.co/litert-community/Gemma3-1B-IT
2. Create a **read** token at https://huggingface.co/settings/tokens.
3. Add `HF_TOKEN=hf_...` to `frontend/.env` (gitignored), then restart the
   app. A hot reload is not enough.

`.env` is bundled into the app as a Flutter asset. Remove `HF_TOKEN` before
you build anything you share.

Gemma 4 E2B and Qwen3 0.6B are public.

## Android (physical device)

Requirements: an arm64 phone on Android 11 (API 30) or later. LiteRT-LM is
arm64-only and needs `minSdk 30`, so emulators on x86 hosts will not work.
Gemini Nano works only on devices on Google's Prompt API list (Pixel 9 and
later, recent Galaxy S, and others). It also needs AICore up to date in Play
Store.

```bash
cd frontend
flutter devices                # enable USB debugging; the phone should be listed
flutter run -d <device-id>     # debug is the default
```

Downloads run as a foreground task so multi-GB files are not killed after
9 minutes. Stay on Wi-Fi. Gemma 3n E2B is about 3.7 GB.

## iPhone (physical device)

Requirements: iOS 15 or later. Apple Foundation Models need iOS 26 or later,
an iPhone 15 Pro or newer, and Apple Intelligence turned on in Settings.

1. `cd frontend && flutter pub get && (cd ios && pod install)`
2. Open `ios/Runner.xcworkspace` in Xcode. Under Runner > Signing &
   Capabilities, choose your team. The Debug configuration uses
   `Runner/Runner.entitlements` (extended virtual addressing, increased
   memory limit, increased debugging memory limit). Xcode needs a paid
   Apple Developer team to provision these. Free personal teams usually
   cannot. Without them, the 2-4 GB models are likely to be killed for
   memory.
3. Turn on Developer Mode on the phone (Settings > Privacy & Security).
4. `flutter run -d <device-id>`

The iOS Simulator runs on CPU only and is not representative.

## Notes on numbers

- These are debug builds. Inference runs in native code, so token speed is
  realistic, but UI work is slower than in release.
- The first reply after load includes warm-up. Compare the second and later
  replies.
- RSS is `ProcessInfo.currentRss`. Memory-mapped weights are counted only
  when their pages are resident, so treat it as approximate.

## Removing it

Delete `lib/prototype/` and `test/prototype/`. Remove the three added lines
in `lib/app.dart` (the `foundation.dart` and `prototype_launcher.dart`
imports and the `PrototypeLauncher` line) and the three `flutter_edge_ai*` entries
in `pubspec.yaml`. Then revert the platform changes listed in the PR or
commit: iOS target and Podfile, `Runner.entitlements`, Android `minSdk`,
Kotlin version, and the debug manifest.
