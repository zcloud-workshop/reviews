# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Reviews is a local-first Flutter quiz practice app (Chinese-language UI). Users import question banks from `.json`, `.docx`, or `.doc` files; question banks, answer drafts, and scores are stored entirely on-device via SharedPreferences — no server, no accounts. On Android, files can also arrive via the system share sheet ("分享"/"用其他应用打开", e.g. from QQ).

All user-facing strings, code comments, and test names are in Chinese. Write new UI text and error messages in Chinese to match.

## Commands

```bash
flutter pub get        # install dependencies
flutter run            # run on connected device/emulator
dart analyze           # static analysis (flutter analyze also works)
flutter test           # run all tests
flutter test test/widget_test.dart                          # run one file
flutter test --plain-name "判题器可以统计自动判分题和待核对简答题"  # run one test by name
flutter build apk --release   # output: build/app/outputs/flutter-apk/app-release.apk
```

Release builds use a fixed keystore loaded from ignored `android/key.properties`; missing signing configuration fails the release build without falling back to debug signing. Debug builds do not require the release key. CI restores the key from GitHub Actions Secrets and checks the APK certificate against `android/signing-certificate.sha256`. See `docs/ci-workflow.md` for local configuration and backup instructions. Android minSdk is 26.

## Architecture

### App bootstrap and state

`lib/main.dart` → `lib/src/app.dart` (`ReviewsApp`). The app root creates two app-wide `ChangeNotifier` controllers in `initState` and injects them down through constructors (no provider/inherited-widget package):

- `QuestionBankController` — imported modules. Handles conflict strategies on import (`replaceImported` / `keepBoth`); `keepBoth` regenerates module/day/question IDs via `_withUniqueIdentity` when id, name, day id, or question id collides.
- `QuizProgressController` — per-`QuizDay` progress: drafts, submitted flag, last accuracy. `clearForModule` removes a deleted module's progress.

Both follow the same pattern: controller (ChangeNotifier) → repository → SharedPreferences, JSON under versioned keys (`imported_question_banks_v1`, `quiz_progress_v1`, `theme_mode`). Writes are serialized through an internal `_writeQueue` future chain; loading happens once (`_loadOperation ??=`). Preserve this pattern — widget tests verify persistence across "restarts" (re-pumping the app over the same mocked SharedPreferences).

### Data model

`lib/models/quiz.dart`: `QuizModule` → `QuizDay` → `Question`. `Question.answer` is `dynamic`, with a distinct shape per type:

| type | answer shape |
| --- | --- |
| `choice` | `int` option index (0-based) |
| `multi` | `List<int>` unique indices |
| `judge` | `bool` |
| `fill` | `List<String>` |
| `shortAnswer` | `String` reference answer (never auto-graded) |

`lib/data/sample_data.dart` is used only by tests — the shipped app starts with no preset modules.

### Import pipeline

`HomeScreen` drives all imports: read file → decode → preview (counts, rename, conflict choice) → only then persist. Two decoders produce the same models:

- **JSON**: `QuestionFilePicker.pick()` → `QuestionBankCodec.decode()` — strict validation of `formatVersion: 1` and every field; the whole file is rejected with locatable Chinese errors (e.g. `模块 1 / 练习组 1 / 第 1 题.answer`). Format spec and templates are in `docs/`.
- **Documents**: extracted text → `DocumentQuestionBankParser.decode()` — heuristic line-based parser (numbered questions, `A.` options, `答案：` lines, ≥6 underscores for blanks, chapter headings ignored). Normalizes answers into the same shapes as the codec.

`QuestionFilePicker` dispatches by extension: `.docx` → `DocxTextExtractor` (archive + xml packages, runs inside `Isolate.run`); `.doc` → MethodChannel to Kotlin (Apache POI); `.json`/`.txt` → plain UTF-8 read. The 20 MB file limit is enforced independently in three places (Dart text reader, DOCX extractor, Android native) — keep them in sync when changing.

### Android native layer

`android/.../MainActivity.kt` implements two MethodChannels:

- `com.quiz.reviews/shared_file` — handles ACTION_VIEW/SEND/SEND_MULTIPLE intents, copies the shared file to cache, detects extension by name/MIME/magic bytes, returns `{name, mimeType, path}`. Dart side: `SharedQuestionFileReceiver` (initial file + live stream while the app runs).
- `com.quiz.reviews/document_reader` — `extractDoc` for legacy `.doc` via Apache POI `WordExtractor` on a background thread.

### Grading

`AnswerEvaluator` auto-grades all types except `shortAnswer`, which is marked `pendingReview` for self-checking. Accuracy = correct / auto-gradable total, so short-answer questions never affect the score.

### Screens and drafts

`home_screen.dart` (module list, import flow, theme toggle) → `module_screen.dart` (day list) → `quiz_screen.dart` (answering, submit with confirmation when unanswered questions remain, results, redo). Drafts autosave with a 350 ms debounce plus a final save on dispose. The theme toggle switches light/dark only (no "follow system" option in the UI); first launch defaults to system brightness.
