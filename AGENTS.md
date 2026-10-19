# RawCull agent instructions

macOS 14+ SwiftUI app (Swift 6, strict concurrency) for keyboard-first photo culling.
See `README.md` for the product and build setup.

## Commands

- Build: `swift build`
- Tests: `swift test` (swift-testing, `Tests/RawCullTests`)
- App bundle build: `xcodebuild -project RawCull.xcodeproj -scheme RawCull -configuration Debug build`
- `project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after
  adding or removing source files so `RawCull.xcodeproj` picks them up, and commit the result.
- Tester DMG: `scripts/package.sh` (Developer ID signed, notarized, stapled, universal) writes
  `build/RawCull-<version>.dmg`. It reads the team ID and App Store Connect API key from
  `~/.config/favren/asc.env`; never copy those values into the repo. Bump `MARKETING_VERSION`
  / `CURRENT_PROJECT_VERSION` in `project.yml` before sending a new build. Notarization uploads
  to Apple, so run it only when the user asks for a package.

## Conventions

- UI colors, badges and key caps come from FavrenUI (`FavrenSemantic`, `FavrenColors`,
  `FavrenBadge`, `FavrenKeyCap`). Do not hardcode new colors where a token exists.
- Services that touch the file system are plain `struct`s with `static` functions and are unit
  tested against temp directories (see `FileMover`, `FolderScanner` and their tests).
- `@MainActor @Observable` classes hold UI state (`CullSession`, `ImageLoader`). Heavy I/O runs
  in `Task.detached` and hops back to the main actor.
- Keyboard handling lives in `CullingView.handleKeyDown`. Every culling key also has a Korean
  2-set layout alias (for example `a` and `ㅁ`).
- Never touch user photos except through an explicit user action. Writes must be atomic.
- Do not use the em dash character in code, comments or UI strings.
- Do not commit or push. Claude reviews and commits.
