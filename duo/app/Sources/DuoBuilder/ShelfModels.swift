import Foundation

// MARK: - Platform

enum Platform: String, Codable, Equatable {
    case `switch`
    case ps2
}

// MARK: - Support, as persisted

/// The four support states of IMPLEMENTATION.md §4.4, stored so the shelf can draw a tile without reading a file.
struct SupportStateDTO: Codable, Equatable {
    /// `tested`, `other-version`, `provisional`, `unknown` (GameInfo.Support.state)
    var state: String
    var testedVersion: String?

    init(state: String, testedVersion: String? = nil) {
        self.state = state
        self.testedVersion = testedVersion
    }

    init(_ support: GameInfo.Support?) {
        state = support?.state ?? "unknown"
        testedVersion = support?.versions.last
    }

    /// Never merges the states. An "other version" profile with no named version is reported as new rather than
    /// printing an empty "(tested: )".
    var display: SupportState {
        switch state {
        case "tested", "verified":
            return .tested
        case "other-version":
            guard let v = testedVersion, !v.isEmpty else { return .new }
            return .otherVersionTested(testedVersion: v)
        case "provisional":
            return .bringUp
        default:
            return .new
        }
    }
}

// MARK: - Files and the library

/// One file of a game. Persisted as a bookmark (IMPLEMENTATION.md §9: "not paths"), with the path kept only as a
/// last resort for a fixture or a bookmark that could not be made.
struct FileRef: Codable, Equatable, Identifiable {
    var bookmark: Data?
    var path: String?
    /// `application`, `patch`, `addon`, `disc`
    var role: String
    var version: String?
    var name: String?

    var id: String { (path ?? bookmark.map { $0.base64EncodedString() } ?? role) + ":" + role }

    func url() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        if let path { return URL(fileURLWithPath: path) }
        return nil
    }

    static func make(url: URL, role: String, version: String?, name: String?) -> FileRef {
        FileRef(bookmark: bookmark(for: url), path: url.path, role: role, version: version, name: name)
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

/// IMPLEMENTATION.md §9. `info` is the card the game was last read as: §6.02 says a tile opens its card without
/// reading the file again, which the fields §9 lists cannot do on their own (see DESIGN-QUESTIONS Q9).
struct LibraryEntry: Codable, Equatable, Identifiable {
    var id: String                // titleId (+ cartridge index)
    var title: String
    var publisher: String?
    var platform: Platform
    var files: [FileRef]
    var bannerPNG: Data?
    var support: SupportStateDTO
    var lastUsed: Date
    var cacheKey: String?         // non-nil = "Ready · about 1 min"
    var info: GameInfo?           // the card, so opening a tile re-reads nothing
    var version: String?
    var bytes: Int64?
    var buildID: String?

    var isPrepared: Bool { cacheKey != nil }
}

// MARK: - Installs (what is on each phone)

struct InstalledApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var title: String
    var installedAt: Date?
    var expiresAt: Date?
    var id: String { bundleID }

    enum CodingKeys: String, CodingKey {
        case bundleID = "bundle_id"
        case title
        case installedAt = "installed_at"
        case expiresAt = "expires_at"
    }

    var daysLeft: Int? {
        guard let expiresAt else { return nil }
        return Copy.daysLeft(until: expiresAt)
    }

    var isExpiring: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 48 * 3600
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 0
    }
}

struct PhoneInstalls: Codable, Equatable, Identifiable {
    var deviceID: String
    var deviceName: String
    var slots: Int
    var apps: [InstalledApp]
    var freeBytes: Int64?
    var weeklyAppIDsLeft: Int?
    var id: String { deviceID }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case slots, apps
        case freeBytes = "free_bytes"
        case weeklyAppIDsLeft = "weekly_app_ids_left"
    }

    init(deviceID: String, deviceName: String, slots: Int = 3, apps: [InstalledApp] = [],
         freeBytes: Int64? = nil, weeklyAppIDsLeft: Int? = nil) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.slots = slots
        self.apps = apps
        self.freeBytes = freeBytes
        self.weeklyAppIDsLeft = weeklyAppIDsLeft
    }

    var used: Int { min(apps.count, slots) }
    var freeSlots: Int { max(0, slots - apps.count) }
}

struct InstallDocument: Codable, Equatable {
    var devices: [PhoneInstalls]

    /// The contract the UI asks `bin/duo device apps --json` for (IMPLEMENTATION.md §3): ISO-8601 dates,
    /// snake_case keys. Two shapes are accepted so a fixture can describe one phone without the wrapper.
    static func decode(_ text: String) -> InstallDocument? {
        guard let start = text.firstIndex(of: "{"), let data = String(text[start...]).data(using: .utf8) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        if let doc = try? d.decode(InstallDocument.self, from: data) { return doc }
        if let one = try? d.decode(PhoneInstalls.self, from: data) { return InstallDocument(devices: [one]) }
        // The coding keys are the snake_case contract itself, so a plain decoder reads it too.
        let plain = JSONDecoder()
        plain.dateDecodingStrategy = .iso8601
        if let doc = try? plain.decode(InstallDocument.self, from: data) { return doc }
        if let one = try? plain.decode(PhoneInstalls.self, from: data) { return InstallDocument(devices: [one]) }
        return nil
    }
}

// MARK: - Failures (`code` from the CLI; IMPLEMENTATION.md §3, §6.14)

struct Failure: Equatable {
    enum Code: String, Codable, CaseIterable {
        case slotsFull = "slots_full"
        case appIdLimit = "app_id_limit"
        case deviceGone = "device_gone"
        case deviceLocked = "device_locked"
        case trustNeeded = "trust_needed"
        case diskFullMac = "disk_full_mac"
        case diskFullPhone = "disk_full_phone"
        case signingFailed = "signing_failed"
        case unknown

        var isLimit: Bool { self == .slotsFull || self == .appIdLimit }
    }

    var code: Code
    /// The plain-language sentence the CLI printed (already in the register of DESIGN.md §9).
    var sentence: String
    var stage: String?
    var appIdAvailableOn: Date?

    init(code: Code = .unknown, sentence: String, stage: String? = nil, appIdAvailableOn: Date? = nil) {
        self.code = code
        self.sentence = sentence
        self.stage = stage
        self.appIdAvailableOn = appIdAvailableOn
    }

    /// The sentence shown above the ladder. Copied from the code where the copy needs no other data; the CLI's own
    /// sentence everywhere else, so the live app never shows an empty placeholder.
    func shownSentence(phone: String) -> String {
        switch code {
        case .slotsFull:
            return Copy.failSlotsFull(phone)
        case .deviceGone:
            return Copy.failDeviceGone(phone)
        case .deviceLocked:
            return Copy.failDeviceLocked(phone)
        case .appIdLimit:
            guard let date = appIdAvailableOn else { return sentence.isEmpty ? Copy.failUnknown(stage ?? "") : sentence }
            return Copy.failAppIdLimit(Copy.date(date))
        case .unknown:
            return sentence.isEmpty ? Copy.failUnknown(stage ?? "") : sentence
        default:
            return sentence.isEmpty ? Copy.failUnknown(stage ?? "") : sentence
        }
    }
}

struct LadderStep: Identifiable, Equatable {
    enum Action: Equatable { case choosePhone, showDetails, copyDetails }
    var id: String
    var text: String
    /// The first row is the recommended fix (accent number badge, filled panel).
    var recommended: Bool = false
    /// `slots_full`: the three installed games with their days left.
    var showsInstalled: Bool = false
    var action: Action?
}

enum FailureLadder {
    /// One table, so the copy can be reviewed in one place (§6.14). Codes whose ladder the spec does not describe
    /// use the `unknown` ladder with their own sentence above it (DESIGN-QUESTIONS Q6).
    static func steps(for failure: Failure, otherPhone: String?) -> [LadderStep] {
        if failure.code == .slotsFull {
            var steps: [LadderStep] = [
                LadderStep(id: "room", text: Copy.failMakeRoom, recommended: true, showsInstalled: true),
            ]
            if let otherPhone {
                steps.append(LadderStep(id: "phone", text: Copy.failOtherPhone(otherPhone), action: .choosePhone))
            }
            steps.append(LadderStep(id: "later", text: Copy.failLater))
            return steps
        }
        return [
            LadderStep(id: "retry", text: Copy.failRetry, recommended: true),
            LadderStep(id: "details", text: Copy.details, action: .showDetails),
            LadderStep(id: "copy", text: Copy.failCopyDetails, action: .copyDetails),
        ]
    }
}

// MARK: - Settings (`settings.json`)

struct Settings: Codable, Equatable {
    var reminder = false
    var autoRenew = false
    var selectedDevice: String?
    /// The user's own BIOS dump for `.iso (ps2)` games, chosen in Setup; passed to `duo ps2 build --bios`.
    var ps2BIOS: String?
}

// MARK: - One run (working / failed / done)

struct TimelineStage: Identifiable, Equatable {
    enum Status: Equatable {
        case done(elapsed: TimeInterval)
        case active
        case pending
    }
    var id: String
    var title: String
    var status: Status
    var detail: String?
    var fraction: Double?
    var eta: String?
    var hint: String?
}

struct CopyProgress: Equatable {
    var doneBytes: Int64
    var totalBytes: Int64
    var bytesPerSecond: Double

    var fraction: Double { totalBytes > 0 ? min(Double(doneBytes) / Double(totalBytes), 1) : 0 }
    var rateMBs: String {
        let mbs = bytesPerSecond / 1_048_576
        return mbs >= 10 ? String(format: "%.0f", mbs) : String(format: "%.1f", mbs)
    }
}

struct BuildRun: Equatable {
    var gameName: String
    var phone: String
    var picture: String
    var startedAt: Date
    var endedAt: Date?
    var fraction: Double
    var stages: [TimelineStage]
    var log: [String]
    var headline: String
    var detail: String
    var copy: CopyProgress?
    var slotsAfter: Int?
    var roomAfterBytes: Int64?
    var failure: Failure?
    var wasCachedBefore: Bool = false

    var elapsed: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
    var overallPercent: Int { Int((fraction * 100).rounded()) }
    var currentStageTitle: String { stages.last(where: { $0.status == .active })?.title ?? headline }
}

struct DoneInfo: Equatable {
    var gameName: String
    var phone: String
    var renewed: Bool
    var expiry: Date?
    var took: TimeInterval
    var needsTrust: Bool
    var slots: [InstalledApp]
}

struct ReadingProgress: Equatable {
    var fileName: String
    var startedAt: Date
    var doneBytes: Int64?
    var totalBytes: Int64?
}
