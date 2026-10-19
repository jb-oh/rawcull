# T005 Handoff

Status: implemented

## Summary

- Added an English-source String Catalog with 84 fully translated Korean entries.
- Localized screens, alerts, shortcut names and tooltips, FavrenUI labels, rotation feedback,
  and file-processing errors. Folder names, filenames, destination folders and key caps stay literal.
- Added Settings → Language with System Default, English and 한국어. The selection persists
  through the app's `AppleLanguages` default and applies on the next launch.
- Added Restart Now. It flushes the session save and synchronizes defaults before opening a
  new app instance. The current instance terminates after the launch succeeds. Failures show an alert.
- Added catalog plural variants and tests for both languages.

## Files changed

- `Sources/RawCull/Resources/Localizable.xcstrings`
  - Complete English/Korean translations and English plural variants.
- `Sources/RawCull/Models/LanguagePreferenceStore.swift`
  - Reads only the app's persistent override, writes `["en"]` or `["ko"]`, and removes the key
    for System Default. Supports regional stored codes such as `ko-KR`.
- `Sources/RawCull/Models/Localization.swift`
  - Selects the SwiftPM resource bundle for package builds and the main bundle for the app.
- `Sources/RawCull/Views/SettingsView.swift`
  - Language tab, restart note/button, and restart failure alert.
- `Sources/RawCull/App/RawCullApp.swift`
  - Makes the current session available to Settings for the pre-restart save flush.
- `Sources/RawCull/Models/KeyBinding.swift`
  - Resolves shortcut action names using the localization bundle.
- `Sources/RawCull/Services/FileMover.swift`, `Sources/RawCull/Services/RotationWriter.swift`
  - Localized error descriptions without changing file operations.
- `Sources/RawCull/Views/CullingView.swift`, `Sources/RawCull/Views/WelcomeView.swift`
  - Localized rotation feedback, FavrenUI empty-state text, and the open-panel message.
- `Sources/RawCull/Views/StatusBar.swift`, `Sources/RawCull/Views/SummaryView.swift`
  - Catalog-backed badges, plural counts, summary rows and move results. Fixed the summary's
    conditional heading, which previously selected a plain String instead of a localized key.
- `Package.swift`, `project.yml`, `RawCull.xcodeproj/project.pbxproj`
  - Resource packaging, English development language, Korean known region, and compiler string
    extraction. Regenerated the project with XcodeGen.
- `Tests/RawCullTests/LanguagePreferenceStoreTests.swift`
  - Isolated UserDefaults tests for inherited values, read/write, removal, regional codes,
    malformed values and preservation of unrelated settings.
- `Tests/RawCullTests/LocalizationTests.swift`, `Tests/RawCullTests/StatusBarTests.swift`
  - Replaced the English-only count test with checks against the compiled resource bundle.
    Added translation completeness, advertised languages, English plurals, Korean counts,
    filename preservation and folder-summary formatting checks.

## Implementation notes

- SwiftUI literal keys use the main app catalog. Values passed as String, including FavrenUI
  labels and AppKit messages, use `String(localized:bundle:)` explicitly.
- Reading `UserDefaults.stringArray(forKey: "AppleLanguages")` alone also sees macOS's global
  language list. Reading the app's persistent domain distinguishes an override from System Default.
- No live locale override is applied. The standard per-app language mechanism also covers
  AppKit/system menus after relaunch.
- English counts use catalog `one`/`other` variants. Korean counts use a single translation.
  The original formatted scan count is preserved.
- All source files were inspected. Tree names are user content, key-cap labels are intentionally
  untranslated, and the unavailable NSCoder initializer's fatalError is a developer diagnostic.
- Reviewed the unstaged diff and new files. The SHA-256 of `git diff --cached --binary` matches
  the pre-task snapshot. Nothing was committed, staged or unstaged.

## Validation

### Passed

- `xcodegen generate`: regenerated the project successfully.
- `swift build`: final build passed.
- `swift test`: final run passed, 68 tests in 10 suites.
- `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`:
  final app build passed.
- Compiler extraction audit: all 84 keys emitted in the app's `.stringsdata` files exist in the
  catalog. No missing keys.
- Post-build Info.plist / Resources inspection: `CFBundleDevelopmentRegion` is `en`;
  `Contents/Resources/en.lproj/Localizable.strings`, `en.lproj/Localizable.stringsdict` and
  `ko.lproj/Localizable.strings` exist. Every one of the 84 shipped Korean values matches the catalog.
  The generated project's `knownRegions` includes `ko`.
- App bundle inspected:
  `/Users/jboh/Library/Developer/Xcode/DerivedData/RawCull-eyhevjfcxcubkzaioiibxakqgyvw/Build/Products/Debug/RawCull.app`
- `git diff --check`: passed.
- Staged-diff checksum comparison: passed, earlier tasks' staged content is unchanged.

### Failed

- Initial restricted `swift build`: failed because nested `sandbox-exec` could not apply its
  sandbox. The same command passed when rerun with approved build permissions.
- Initial `swift test`: failed in two new tests that incorrectly assumed a registered Korean
  fallback outranked macOS's global language list. Corrected those assertions to verify inherited
  values are preserved. The final full run passed. These were new test issues, not pre-existing failures.
- Initial Python bundle-resource inspection: failed because `plistlib` did not parse Xcode's
  UTF-16 XML strings file directly. Repeated inspection through `plutil` passed for all 84 values.

### Not run

- Interactive Korean/English UI and system-menu inspection, including launch with
  `-AppleLanguages "(ko)"`: not run, GUI/computer-use automation was explicitly prohibited.
- Language picker interaction, Restart Now relaunch and return to System Default in the running
  app: not run for the same reason. Persistence and compiled-resource behavior were tested automatically.

## Acceptance criteria

- [ ] Entire Korean/English UI including system menus and Settings: implemented, but interactive
      launch and visual confirmation were not run.
- [ ] Language switching after Restart Now and System Default following macOS: implemented;
      preference behavior is tested, but interactive relaunch was not run.
- [x] Complete Korean translations and correct English statistics plurals: catalog audit and
      compiled-bundle tests passed.
- [x] `swift build`, `swift test` and the Xcode app build passed.

## Deviations

None. Interactive checks remain explicitly not run as requested.

## Risks / concerns

- Claude should perform the interactive language/restart/menu checks before final acceptance.
  No claim is made that those runtime interactions passed.

## Suggested shared-context updates

None.
