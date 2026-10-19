# Plan

Branch: `feature/rotate-status-zoom`

| Task | Scope | Main files | Depends on |
|---|---|---|---|
| T001 | Apply rotation to file (Return), sidecar-aware loading, sidecar move | new `Services/RotationWriter.swift`, `ImageLoader`, `CullingView`, `FileMover` | None |
| T002 | Status bar: wrapping layout + labeled folder stats | `StatusBar`, `CullingView` call site | T001 (shares `CullingView`) |
| T003 | Zoom centering at narrow widths + top-right minimap | `PhotoView` | T002 |
| T004 | Settings window, keyCode-based customizable shortcuts | new binding store + Settings view, `RawCullApp`, `CullingView`, `StatusBar` | T003 |
| T005 | Korean localization (String Catalog) + Language setting via `AppleLanguages` | all views, `project.yml`, `Package.swift` | T004 |
| T006 | Wider resizable folder tree, Close Folder moved to File menu (Cmd+W) | `CullingView`, `ContentView`, `RawCullApp` | T005 |
| T008 | File names + Reveal in Finder in thumbnail sidebar | `ThumbnailSidebar` | T006 |
| T007 | Picks/ and Rejects/ folders default to their decision, re-sort on Move Files | `CullSession`, `FileMover`, `SummaryView` | T008 |

Tasks run sequentially (shared files, one Codex session per working tree). Localization runs
last so it covers every string the earlier tasks add.

## GUI checks for the user (cannot be automated here, see memory note)

- Rotate a JPEG with C, press Return, reopen in Preview: rotated.
- Rotate a RAW, press Return: `<name>.xmp` appears; RawCull and Lightroom show it rotated.
- Narrow the window: status bar wraps, nothing crushed.
- Narrow the window, press Space: photo centered, scrolls both ways; minimap top-right tracks.
- Settings (Cmd+,): rebind pick to another key, check it works and survives restart.
- Switch language to 한국어, Restart Now: whole UI Korean; System Default follows macOS.
- Folder tree divider drags 200-420 pt; File > Close Folder (Cmd+W).
- Thumbnail names visible; right-click > Reveal in Finder.
- Open X/Picks: all picks; reject one, Move Files: it lands in X/Rejects.
