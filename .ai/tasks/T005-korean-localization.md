# T005: Korean localization and a language setting

Status: accepted
Owner: codex
Depends on: T004

## Objective

Localize every user-facing string into Korean. By default RawCull follows the macOS system
language (Korean system → Korean UI, otherwise English). Settings gets a Language section with
"System Default", "English" and "한국어".

## Why

User request (2026-10-18): Korean support that follows the system setting, plus a way to switch
language in the app's settings.

## Context

- Strings are currently English literals across `Sources/RawCull/Views/*`, `App/*`, and error
  messages in `Services/*` (for example `FileMover.MoveError` descriptions, the T001 rotation
  feedback, the T004 Settings window and action names).
- The app ships through the Xcode project generated from `project.yml` (XcodeGen); resources
  must be included there. `Package.swift` is used for `swift build`/`swift test` only, but must
  keep building (add `defaultLocalization` and resources if needed).
- Use a String Catalog (`Localizable.xcstrings`) with `en` as source language and full `ko`
  translations. Make sure `ko` is a known region of the built app so system menus (Edit, Window,
  Settings…, Quit) also appear in Korean.
- Language override: write the chosen language to the app's `AppleLanguages` user default
  (`["ko"]` or `["en"]`, remove the key for System Default). macOS applies it at next launch, so
  show a note "Restart RawCull to apply the language change." with a "Restart Now" button that
  relaunches the app (flush the session save first, as quitting does). This is the standard
  per-app language mechanism (same as System Settings > Language & Region > Applications).
- Strings passed to FavrenUI components as `String` (for example `FavrenBadge`) are not localized
  by SwiftUI automatically; resolve them with `String(localized:)`.
- Pluralized stats from T002 (`1 photo`/`142 photos`) need catalog plural variants in English;
  Korean has no plural form (`사진 142장`, `픽 23`, `리젝 8`, `남음 111` or similar natural wording).

## Translation guidance

- Natural, concise Korean UI wording, not literal translation. Keep the photography terms users
  know: Pick → 픽, Reject → 리젝 (match the user's own wording), Undecided → 미결정.
- Key cap labels (A, Space, Return, ←) are not translated; `Space` may stay as is.
- Do not use the em dash. No trailing periods on labels, titles, buttons or short noun phrases;
  full sentences keep normal punctuation.

## Relevant files

- every file under `Sources/RawCull` with user-facing text
- `project.yml`, `Package.swift`, new `Sources/RawCull/Resources/Localizable.xcstrings`
- the Settings view from T004

## Implementation requirements

1. Every user-facing string goes through the catalog; no remaining English literal is shown in a
   Korean UI (search the sources for `Text("`, `Button("`, `Label("`, `.help(`, alerts, errors).
2. `ko` translations complete for every key (no `new`/untranslated state in the catalog).
3. Settings → Language picker with the three options, persisted via `AppleLanguages` as above,
   current selection reflecting the stored value, restart note and Restart Now button.
4. `ko` declared so the built `.app` lists it (check `Info.plist` / `knownRegions` after build).
5. Tests: language preference read/write against a test `UserDefaults` suite (System Default
   removes the key). If feasible, a test that loads the built catalog and asserts a sample of
   keys has a `ko` value.

## Non-goals

- No other languages. No changes to shortcut behaviour or culling logic.
- Folder and file names are never translated.

## Acceptance criteria

- [ ] With macOS set to Korean (or launching with `-AppleLanguages "(ko)"`), the whole UI
      including system menus and Settings is Korean; with English it is English.
- [ ] Language picker switches after Restart Now; System Default follows macOS again.
- [ ] Catalog has complete `ko` translations; stats plurals correct in English.
- [ ] `swift build`, `swift test`, and the `xcodebuild` app build pass.

## Required checks

- `swift build`
- `swift test`
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`

## Expected output

The string catalog, localized call sites, Language settings section, project/package updates,
tests, and `.ai/handoffs/T005-handoff.md`.
