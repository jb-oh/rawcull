import Foundation
import Testing
@testable import RawCull

@MainActor
struct LocalizationTests {
    private var catalogURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RawCull/Resources/Localizable.xcstrings")
    }

    @Test func everyCatalogEntryHasCompleteEnglishAndKoreanTranslations() throws {
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        #expect(catalog["sourceLanguage"] as? String == "en")
        let entries = try #require(catalog["strings"] as? [String: [String: Any]])
        #expect(!entries.isEmpty)
        func checkUnits(_ node: [String: Any]) {
            if let unit = node["stringUnit"] as? [String: String] {
                #expect(unit["state"] == "translated")
                #expect(unit["value"]?.isEmpty == false)
            }
            for child in node.values {
                if let dictionary = child as? [String: Any] { checkUnits(dictionary) }
            }
        }
        for entry in entries.values {
            let languages = try #require(entry["localizations"] as? [String: [String: Any]])
            #expect(Set(languages.keys) == Set(["en", "ko"]))
            for language in ["en", "ko"] {
                let translation = try #require(languages[language])
                #expect(translation["stringUnit"] != nil || translation["variations"] != nil)
                checkUnits(translation)
            }
        }
    }

    @Test func compiledCatalogResolvesKoreanAndEnglishPlurals() throws {
        #expect(Set(["en", "ko"]).isSubset(of: Set(Localization.bundle.localizations)))
        let output = try #require(Localization.bundle.resourceURL)
        let english = try #require(Bundle(url: output.appendingPathComponent("en.lproj")))
        let korean = try #require(Bundle(url: output.appendingPathComponent("ko.lproj")))
        for (key, expected) in [
            ("Pick", "픽"), ("Reject", "리젝"), ("Unmark", "표시 해제"), ("Undecided", "미결정"),
            ("Close Folder", "폴더 닫기"),
            ("Reveal in Finder", "Finder에서 보기"),
            ("Rotate Left", "왼쪽으로 회전"), ("Rotate Right", "오른쪽으로 회전"),
            ("Language", "언어"), ("System Default", "시스템 설정 따르기"),
            ("Restart Now", "지금 다시 시작"), ("Rotation saved", "회전 저장 완료"),
            ("No source folder set", "원본 폴더가 지정되지 않음")
        ] {
            #expect(korean.localizedString(forKey: key, value: nil, table: nil) == expected)
            #expect(english.localizedString(forKey: key, value: nil, table: nil) == key)
        }
        for count in [0, 1, 23, 142] {
            for (kind, noun, koreanValue) in [
                (StatusBar.CountKind.photos, "photo", "사진 \(count)장"),
                (.picks, "pick", "픽 \(count)장"), (.rejects, "reject", "리젝 \(count)장")
            ] {
                #expect(StatusBar.countLabel(count, kind: kind, bundle: english, locale: Locale(identifier: "en"))
                    == "\(count) \(noun)\(count == 1 ? "" : "s")")
                #expect(StatusBar.countLabel(count, kind: kind, bundle: korean, locale: Locale(identifier: "ko")) == koreanValue)
            }
        }
        let name = "여행 RAW.cr3"
        #expect(String(localized: "Could not read \(name)", bundle: korean, locale: Locale(identifier: "ko"))
            == "여행 RAW.cr3 파일을 읽을 수 없습니다.")
        let folders = 1
        let picks = "1 pick"
        let rejects = "0 rejects"
        #expect(String(localized: "Moved across \(folders) folders: \(picks), \(rejects)", bundle: english, locale: Locale(identifier: "en"))
            == "Moved across 1 folder: 1 pick, 0 rejects")
    }

    @Test func selectionAndBatchActionPluralsResolveInEnglishAndKorean() throws {
        let output = try #require(Localization.bundle.resourceURL)
        let english = try #require(Bundle(url: output.appendingPathComponent("en.lproj")))
        let korean = try #require(Bundle(url: output.appendingPathComponent("ko.lproj")))
        let en = Locale(identifier: "en")
        let ko = Locale(identifier: "ko")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let entries = try #require(catalog["strings"] as? [String: [String: Any]])
        for key in ["%lld selected", "Pick %lld Photos", "Reject %lld Photos", "Unmark %lld Photos"] {
            let languages = try #require(entries[key]?["localizations"] as? [String: [String: Any]])
            for language in ["en", "ko"] {
                let variations = try #require(languages[language]?["variations"] as? [String: Any])
                let plural = try #require(variations["plural"] as? [String: Any])
                #expect(plural["other"] != nil)
                if language == "en" { #expect(plural["one"] != nil) }
            }
        }
        for count in [0, 1, 2, 23, 142] {
            #expect(StatusBar.selectionLabel(count, bundle: english, locale: en) == "\(count) selected")
            #expect(StatusBar.selectionLabel(count, bundle: korean, locale: ko) == "\(count)장 선택됨")
            let noun = count == 1 ? "Photo" : "Photos"
            #expect(String(localized: "Pick \(count) Photos", bundle: english, locale: en) == "Pick \(count) \(noun)")
            #expect(String(localized: "Reject \(count) Photos", bundle: english, locale: en) == "Reject \(count) \(noun)")
            #expect(String(localized: "Unmark \(count) Photos", bundle: english, locale: en) == "Unmark \(count) \(noun)")
            for (decision, verb, koreanAction) in [
                (Decision.pick, "Pick", "픽하기"), (.reject, "Reject", "리젝하기"),
                (.undecided, "Unmark", "표시 해제")
            ] {
                #expect(ThumbnailSidebar.decisionTitle(decision, count: count, bundle: english, locale: en)
                    == (count > 1 ? "\(verb) \(count) Photos" : verb))
                #expect(ThumbnailSidebar.decisionTitle(decision, count: count, bundle: korean, locale: ko)
                    == (count > 1 ? "\(count)장 \(koreanAction)" : decision == .pick ? "픽" : decision == .reject ? "리젝" : "표시 해제"))
            }
        }
    }

    @Test func batchRotationFeedbackResolvesPluralCountsInEnglishAndKorean() throws {
        let output = try #require(Localization.bundle.resourceURL)
        let english = try #require(Bundle(url: output.appendingPathComponent("en.lproj")))
        let korean = try #require(Bundle(url: output.appendingPathComponent("ko.lproj")))
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let entries = try #require(catalog["strings"] as? [String: [String: Any]])
        for key in ["Rotation saved for %lld photos", "Saved %lld, failed %lld"] {
            let languages = try #require(entries[key]?["localizations"] as? [String: [String: Any]])
            for language in ["en", "ko"] {
                let translation = try #require(languages[language])
                let nodes: [[String: Any]]
                if let substitutions = translation["substitutions"] as? [String: [String: Any]] {
                    #expect(Set(substitutions.keys) == Set(["saved", "failed"]))
                    nodes = Array(substitutions.values)
                } else {
                    nodes = [translation]
                }
                for node in nodes {
                    let variations = try #require(node["variations"] as? [String: Any])
                    let plural = try #require(variations["plural"] as? [String: Any])
                    #expect(plural["other"] != nil)
                    if language == "en" { #expect(plural["one"] != nil) }
                }
            }
        }
        for count in [0, 1, 2, 23, 142] {
            let urls = (0..<count).map { URL(fileURLWithPath: "/tmp/\($0).jpg") }
            let noun = count == 1 ? "photo" : "photos"
            let success = RotationWriter.BatchResult(savedURLs: urls)
            #expect(success.message(bundle: english, locale: Locale(identifier: "en")) == "Rotation saved for \(count) \(noun)")
            #expect(success.message(bundle: korean, locale: Locale(identifier: "ko")) == "사진 \(count)장 회전 저장 완료")
            for failures in [1, 2, 23] {
                let result = RotationWriter.BatchResult(savedURLs: urls, failedURLs: Array(repeating: URL(fileURLWithPath: "/tmp/failed.jpg"), count: failures))
                #expect(result.message(bundle: english, locale: Locale(identifier: "en")) == "Saved \(count) \(noun), failed \(failures) \(failures == 1 ? "photo" : "photos")")
                #expect(result.message(bundle: korean, locale: Locale(identifier: "ko")) == "\(count)장 저장, \(failures)장 실패")
            }
        }
    }

    @Test func summaryMessagesDescribeSortedMovesInEnglishAndKorean() throws {
        let output = try #require(Localization.bundle.resourceURL)
        let english = try #require(Bundle(url: output.appendingPathComponent("en.lproj")))
        let korean = try #require(Bundle(url: output.appendingPathComponent("ko.lproj")))
        let en = Locale(identifier: "en")
        let ko = Locale(identifier: "ko")
        let parent = URL(fileURLWithPath: "/여행")
        for folderName in ["Picks", "Rejects"] {
            let folder = parent.appendingPathComponent(folderName)
            let destination = folderName == "Picks" ? "Rejects" : "Picks"
            let result = MoveResult(picks: folderName == "Rejects" ? 2 : 0,
                                    rejects: folderName == "Picks" ? 2 : 0, returnedToParent: 1)
            #expect(SummaryView.moveResultMessage(result, folderURL: folder, bundle: english, locale: en)
                == "2 moved to \(destination)/, 1 moved back to 여행/")
            #expect(SummaryView.moveResultMessage(result, folderURL: folder, bundle: korean, locale: ko)
                == "2장 → \(destination)/, 1장 → 여행/로 되돌림")
            for count in [1, 2] {
                #expect(SummaryView.undecidedMessage(count: count, folderURL: folder, bundle: english, locale: en)
                    == "\(count) undecided photo\(count == 1 ? "" : "s") will move back to 여행/")
                #expect(SummaryView.undecidedMessage(count: count, folderURL: folder, bundle: korean, locale: ko)
                    == "미결정 사진 \(count)장은 여행/로 되돌아갑니다.")
            }
        }
        for folders in [1, 2] {
            let result = TreeMoveResult(folders: folders, picks: 2, rejects: 1, returnedToParent: 3)
            #expect(SummaryView.treeMoveResultMessage(result, bundle: english, locale: en)
                == "Moved across \(folders) folder\(folders == 1 ? "" : "s"): 2 picks, 1 reject, 3 photos returned to parent folders")
            #expect(SummaryView.treeMoveResultMessage(result, bundle: korean, locale: ko)
                == "폴더 \(folders)개에서 이동 완료: 픽 2장, 리젝 1장, 사진 3장 부모 폴더로 되돌림")
        }

        let ordinary = MoveResult(picks: 1, rejects: 2, returnedToParent: 0)
        #expect(SummaryView.moveResultMessage(ordinary, folderURL: parent, bundle: english, locale: en)
            == "1 pick moved to Picks/, 2 rejects moved to Rejects/")
        #expect(SummaryView.moveResultMessage(ordinary, folderURL: parent, bundle: korean, locale: ko)
            == "픽 1장 → Picks/, 리젝 2장 → Rejects/ 이동 완료")
        #expect(SummaryView.undecidedMessage(count: 1, folderURL: parent, bundle: english, locale: en)
            == "1 photo is undecided. It will stay in place.")
        #expect(SummaryView.treeMoveResultMessage(
            TreeMoveResult(folders: 1, picks: 1, rejects: 2, returnedToParent: 0), bundle: english, locale: en
        ) == "Moved across 1 folder: 1 pick, 2 rejects")
    }
}
