import XCTest
@testable import DuoBuilder

/// The rules the redesign adds: the four support states stay distinct, the timeline only draws stages the pipeline
/// reported, failure ladders are chosen by code, the shelf reads its own JSON, and the copy deck stays honest.
final class ShelfTests: XCTestCase {

    // MARK: Support states (§4.4)

    func testTheFourSupportStatesAreNeverMerged() {
        XCTAssertEqual(SupportStateDTO(state: "tested").display, .tested)
        XCTAssertEqual(SupportStateDTO(state: "other-version", testedVersion: "1.0.0").display,
                       .otherVersionTested(testedVersion: "1.0.0"))
        XCTAssertEqual(SupportStateDTO(state: "provisional").display, .bringUp)
        XCTAssertEqual(SupportStateDTO(state: "unknown").display, .new)
        // An "other version" profile that names no version is reported as new, not as "tested: ".
        XCTAssertEqual(SupportStateDTO(state: "other-version").display, .new)
        let all = Set([SupportState.tested, .otherVersionTested(testedVersion: "1"), .bringUp, .new]
            .map { $0.text })
        XCTAssertEqual(all.count, 4)
    }

    // MARK: Timeline (§6.11)

    func testTheTimelineDrawsOnlyStagesThatStarted() {
        var tracker = StageTracker(naming: .init(phone: "iPhone Duo", picture: "Original shape"))
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        tracker.consume(progress(.stage, name: "Reading the game"), at: t0)
        tracker.consume(progress(.progress, name: "extract base", done: 1.9e9, total: 5.0e9, unit: "B", est: true), at: t0 + 5)
        XCTAssertEqual(tracker.stages.count, 1)
        XCTAssertEqual(tracker.stages[0].status, .active)
        XCTAssertEqual(tracker.stages[0].title, Copy.stageReadActive)
        XCTAssertEqual(tracker.stages[0].detail, "1.8 GB of ~4.7 GB")
        XCTAssertEqual(tracker.stages[0].fraction ?? 0, 1.9e9 / 5.0e9, accuracy: 1e-9)

        tracker.consume(progress(.stageEnd, name: "Reading the game", elapsed: 42), at: t0 + 42)
        tracker.consume(progress(.stage, name: "iOS shaders"), at: t0 + 42)
        tracker.consume(progress(.progress, name: "iOS shaders", done: 18204, total: 62901, eta: 580), at: t0 + 60)
        XCTAssertEqual(tracker.stages.map(\.id), ["read", "graphics"])
        XCTAssertEqual(tracker.stages[0].status, .done(elapsed: 42))
        XCTAssertEqual(tracker.stages[0].title, Copy.stageRead)
        XCTAssertEqual(tracker.stages[1].status, .active)
        XCTAssertEqual(tracker.stages[1].eta, "9m 40s")
        XCTAssertEqual(tracker.stages[1].hint, Copy.stageGraphicsNote)
        XCTAssertTrue(tracker.stages[1].detail?.contains("18,204 of 62,901") ?? false)
    }

    func testAnUnknownStageKeepsItsOwnName() {
        var tracker = StageTracker(naming: .init(phone: "iPhone Duo", picture: "Original shape"))
        guard let event = ProgressEvent.parse(#"{"ev":"stage","name":"Mac host"}"#) else { return XCTFail() }
        tracker.consume(event, at: Date())
        XCTAssertEqual(tracker.stages.first?.title, "Mac host")
    }

    func testStageRowMappingCoversThePipelinesNames() {
        XCTAssertEqual(StageTracker.row(for: "extract base"), .read)
        XCTAssertEqual(StageTracker.row(for: "decompress NSZ"), .read)
        XCTAssertEqual(StageTracker.row(for: "build ID lookup"), .read)
        XCTAssertEqual(StageTracker.row(for: "survey: RomFS manifest"), .read)
        XCTAssertEqual(StageTracker.row(for: "rewrite"), .rewrite)
        XCTAssertEqual(StageTracker.row(for: "shader split"), .graphics)
        XCTAssertEqual(StageTracker.row(for: "iOS shaders"), .graphics)
        XCTAssertEqual(StageTracker.row(for: "GLSLC capture"), .graphics)
        XCTAssertEqual(StageTracker.row(for: "Vulkan shaders"), .graphics)
        XCTAssertEqual(StageTracker.row(for: "heap check"), .memory)
        XCTAssertEqual(StageTracker.row(for: "address regions"), .memory)
        XCTAssertEqual(StageTracker.row(for: "prepare Xcode"), .build)
        XCTAssertEqual(StageTracker.row(for: "app build"), .build)
        XCTAssertEqual(StageTracker.row(for: "IPA pack"), .pack)
        XCTAssertEqual(StageTracker.row(for: "Signing"), .pack)
        XCTAssertEqual(StageTracker.row(for: "Installing on iPhone Duo"), .install)
        XCTAssertEqual(StageTracker.row(for: "Starting the game"), .install)
        XCTAssertEqual(StageTracker.row(for: "copy"), .copy)
        XCTAssertNil(StageTracker.row(for: "Preparing the game"))
    }

    func testCopyProgressComesFromTheBytesAndElapsedTime() {
        var tracker = StageTracker(naming: .init(phone: "iPhone 16 Pro", picture: "Original shape"))
        let t0 = Date()
        tracker.consume(progress(.stage, name: "copy"), at: t0)
        tracker.consume(progress(.progress, name: "copy", done: 2.4e9, total: 4.5e9, unit: "B", elapsed: 100), at: t0 + 100)
        let stage = tracker.stages.first
        XCTAssertEqual(stage?.title, Copy.stageCopy)
        XCTAssertEqual(stage?.detail, Copy.stageCopyDetail(done: "2.2", total: "4.2", rate: "23"))
    }

    // MARK: Failures (§6.14)

    func testSlotsFullSentenceAndLadderComeFromTheCode() {
        let failure = Failure(code: .slotsFull, sentence: "raw", stage: "Installing")
        XCTAssertEqual(failure.shownSentence(phone: "iPhone Duo"), Copy.failSlotsFull("iPhone Duo"))
        let steps = FailureLadder.steps(for: failure, otherPhone: "iPhone 16 Pro")
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps[0].recommended)
        XCTAssertTrue(steps[0].showsInstalled)
        XCTAssertEqual(steps[1].action, .choosePhone)
    }

    func testAVerifiedPS2GameIsTestedAndNamedByItsOwnStages() throws {
        XCTAssertEqual(SupportStateDTO(state: "verified").display, .tested)
        let json = "{\"game\": {\"title\": \"SCUS-97399\", \"name\": \"Tidewalker\", \"bytes\": 4509715660},"
            + "\"base\": {\"file\": \"/g/t.iso\", \"kind\": \"iso\", \"name\": \"Tidewalker\"},"
            + "\"updates\": [], \"dlc\": [], \"duo\": {\"state\": \"none\"},"
            + "\"support\": {\"state\": \"verified\", \"versions\": [], \"note\": \"plays\"},"
            + "\"problems\": [],"
            + "\"ps2\": {\"serial\": \"SCUS-97399\", \"region\": \"NTSC-U\", \"layers\": 2, \"size_bytes\": 4509715660, \"bios\": \"optional\"}}"
        let info = try XCTUnwrap(Pipeline.decode(GameInfo.self, json))
        XCTAssertEqual(info.base?.kind, "iso")
        XCTAssertEqual(info.ps2?.serial, "SCUS-97399")
        XCTAssertEqual(info.ps2?.layers, 2)
        XCTAssertEqual(info.ps2?.sizeBytes, 4509715660)
        XCTAssertEqual(info.support?.note, "plays")
        XCTAssertEqual(SupportStateDTO(info.support).display, .tested)

        var tracker = StageTracker(naming: .init(phone: "iPhone 16 Pro", picture: "Original shape", platform: .ps2))
        let t0 = Date()
        tracker.consume(progress(.stage, name: "reading-disc"), at: t0)
        tracker.consume(progress(.stageEnd, name: "reading-disc", elapsed: 12), at: t0 + 12)
        tracker.consume(progress(.stage, name: "translating"), at: t0 + 12)
        tracker.consume(progress(.stageEnd, name: "translating", elapsed: 60), at: t0 + 72)
        tracker.consume(progress(.stage, name: "compiling-vu"), at: t0 + 72)
        tracker.consume(progress(.progress, name: "compiling-vu", note: "VU 12 of 40"), at: t0 + 80)
        XCTAssertEqual(tracker.stages.map(\.title), [Copy.ps2StageDisc, Copy.ps2StageRebuild, Copy.ps2StageGraphics])
        XCTAssertEqual(tracker.stages[0].status, .done(elapsed: 12))
        XCTAssertEqual(tracker.stages[2].status, .active)
        XCTAssertEqual(tracker.stages[2].detail, "VU 12 of 40")
    }

    func testAnUnknownCodeUsesTheUnknownLadder() {
        let failure = Failure(code: .unknown, sentence: "The install stopped.", stage: "Building the app")
        XCTAssertEqual(failure.shownSentence(phone: "iPhone Duo"), "The install stopped.")
        let steps = FailureLadder.steps(for: failure, otherPhone: nil)
        XCTAssertEqual(steps.map(\.action), [nil, .showDetails, .copyDetails])
    }

    func testEmptyUnknownSentenceFallsBackToTheDeck() {
        let failure = Failure(code: .unknown, sentence: "", stage: "Reading the game")
        XCTAssertEqual(failure.shownSentence(phone: "iPhone Duo"), Copy.failUnknown("Reading the game"))
    }

    // MARK: Installs contract (§3)

    func testInstallsDecodeTheSnakeCaseContract() {
        let json = """
        {"devices": [{"device_id": "duo", "device_name": "iPhone Duo", "slots": 3,
          "apps": [{"bundle_id": "org.a", "title": "Harbor Lights",
                    "installed_at": "2026-10-24T10:00:00Z", "expires_at": "2026-11-06T10:00:00Z"}],
          "free_bytes": 65000000000, "weekly_app_ids_left": 7}]}
        """
        let doc = InstallDocument.decode(json)
        XCTAssertNotNil(doc)
        XCTAssertEqual(doc?.devices.first?.deviceID, "duo")
        XCTAssertEqual(doc?.devices.first?.apps.first?.bundleID, "org.a")
        XCTAssertEqual(doc?.devices.first?.apps.first?.title, "Harbor Lights")
        XCTAssertEqual(doc?.devices.first?.freeBytes, 65000000000)
        XCTAssertEqual(doc?.devices.first?.weeklyAppIDsLeft, 7)
        XCTAssertNotNil(doc?.devices.first?.apps.first?.expiresAt)
    }

    // MARK: Shelf persistence (§9)

    func testALibraryEntryRoundTripsWithItsCardAndDates() throws {
        let info = GameInfo(
            game: .init(title: "0100000000000001", name: "Lantern Isles", publisher: "Northwind Games",
                        version: "1.2.0", icon: nil, buildId: "b", bytes: 6_550_000_000),
            cartridge: nil, titleId: nil,
            base: .init(file: "/tmp/games/lantern.xci", kind: "application", displayVersion: "1.0.0", name: "Lantern Isles"),
            update: nil, updates: [], dlc: [], duo: .init(state: "none", name: nil, author: nil, source: nil, note: nil),
            support: .init(state: "tested", versions: ["1.2.0"]), problems: [], keys: "/tmp/keys")
        let entry = LibraryEntry(id: "0100000000000001", title: "Lantern Isles", publisher: "Northwind Games",
                                 platform: .switch, files: [], bannerPNG: nil,
                                 support: SupportStateDTO(info.support), lastUsed: Date(timeIntervalSince1970: 1_800_000_000),
                                 cacheKey: nil, info: info, version: "1.2.0", bytes: 6_550_000_000, buildID: "b")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LibraryEntry.self, from: encoder.encode(entry))
        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(decoded.info?.game?.name, "Lantern Isles")
        XCTAssertEqual(decoded.support.display, .tested)
    }

    func testAPreparedBuildIsRecognisedByThePathConvention() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("duo-test-" + UUID().uuidString)
        let build = folder.appendingPathComponent("0100000000000001_build")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("x".utf8).write(to: build.appendingPathComponent("graphics.bin"))

        let info = GameInfo(
            game: .init(title: "0100000000000001", name: "X", publisher: nil, version: nil, icon: nil, buildId: nil, bytes: nil),
            cartridge: nil, titleId: nil,
            base: .init(file: folder.appendingPathComponent("game.xci").path, kind: "application", displayVersion: nil, name: nil),
            update: nil, updates: [], dlc: [], duo: .init(state: "none", name: nil, author: nil, source: nil, note: nil),
            support: nil, problems: [], keys: nil)
        XCTAssertEqual(CacheProbe.key(for: info), build.path)
    }

    // MARK: Copy (§9, §15)

    func testTheDeckUsesTheShortWeekdayDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
        XCTAssertEqual(Copy.date(date, calendar: calendar), "Sat, Nov 7")
        XCTAssertEqual(Copy.daysLeft(until: date, now: date.addingTimeInterval(-6.5 * 86_400)), 6)
        XCTAssertEqual(Copy.daysLeft(until: date, now: date.addingTimeInterval(1)), 0)
    }

    func testNoUserFacingSentenceUsesTheForbiddenWords() {
        let sentences = [
            Copy.stageGraphics, Copy.stageGraphicsNote, Copy.stageGraphicsHint, Copy.stageRead,
            Copy.stageReadActive, Copy.stageRewrite, Copy.stageBuild, Copy.stagePack,
            Copy.pictureOriginalBody, Copy.pictureNoPack, Copy.cardFooter, Copy.readingFooter,
            Copy.workSafe, Copy.setupRunning, StageCopy.headline(for: "iOS shaders") ?? "",
            StageCopy.headline(for: "extract base") ?? "",
        ]
        for sentence in sentences {
            let lower = sentence.lowercased()
            XCTAssertFalse(lower.contains("shader"), sentence)
            XCTAssertFalse(lower.contains("provisioning"), sentence)
            XCTAssertFalse(lower.contains("entitlement"), sentence)
            XCTAssertFalse(sentence.contains("NSP"), sentence)
        }
    }

    func testCopyNamesFileFormatsNotConsoles() {
        let strings = [Copy.firstRunTypes, Copy.tileAddHint, Copy.tilePS2, Copy.chipBiosMissing,
                       Copy.cardReasonNoKeys, Copy.cardReasonNoBios, Copy.stepKeys, Copy.stepKeysBody,
                       Copy.stepBios, Copy.stepBiosBody, Copy.firstRunDrop, Copy.dropKindGame]
        for string in strings {
            var rest = string.lowercased().replacingOccurrences(of: ".iso (ps2)", with: "")
            rest = rest.replacingOccurrences(of: ".iso", with: "")
            XCTAssertFalse(rest.contains("switch"), string)
            XCTAssertFalse(rest.contains("ps2"), string)
            XCTAssertFalse(rest.contains("playstation"), string)
            XCTAssertFalse(rest.contains("nintendo"), string)
        }
        XCTAssertEqual(Copy.firstRunTypes, ".xci / .nsp · .iso (ps2)")
    }

    // MARK: Helpers

    private func progress(_ kind: ProgressEvent.Kind, name: String, step: String? = nil,
                          done: Double? = nil, total: Double? = nil, unit: String? = nil,
                          est: Bool? = nil, frac: Double? = nil, eta: Double? = nil,
                          elapsed: Double? = nil, note: String? = nil) -> ProgressEvent {
        var parts: [String] = ["\"ev\": \"\(kind.rawValue)\"", "\"name\": \"\(name)\""]
        if let step { parts.append("\"step\": \"\(step)\"") }
        if let done { parts.append("\"done\": \(done)") }
        if let total { parts.append("\"total\": \(total)") }
        if let unit { parts.append("\"unit\": \"\(unit)\"") }
        if let est { parts.append("\"est\": \(est)") }
        if let frac { parts.append("\"frac\": \(frac)") }
        if let eta { parts.append("\"eta\": \(eta)") }
        if let elapsed { parts.append("\"elapsed\": \(elapsed)") }
        if let note { parts.append("\"note\": \"\(note)\"") }
        let json = "{" + parts.joined(separator: ",") + "}"
        return ProgressEvent.parse(json)!
    }
}
