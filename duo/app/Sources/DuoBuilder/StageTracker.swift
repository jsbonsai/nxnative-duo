import Foundation

/// Turns the pipeline's `--progress json` events into the timeline of IMPLEMENTATION.md §6.11.
///
/// There is no `plan` event in `bin/duo` (§3), so only stages that have actually started get a row: the spec's own
/// fallback ("Without it, only draw stages already reached"). Elapsed time is measured here from the events'
/// timestamps, which §3 explicitly allows.
struct StageTracker {
    enum Row: String, CaseIterable {
        case read, rewrite, graphics, memory, build, pack, install, copy
        // `.iso (ps2)` pipeline rows (their titles come from Copy.ps2Stage*).
        case ps2Disc, ps2Program, ps2Rebuild, ps2Explore, ps2Graphics, ps2Build, ps2Check

        var id: String { rawValue }

        /// The order rows appear in. The two pipelines never share a run; each order is correct on its own.
        var rank: Int {
            switch self {
            case .read: return 0
            case .ps2Disc: return 1
            case .ps2Program: return 2
            case .rewrite: return 3
            case .ps2Rebuild: return 4
            case .ps2Explore: return 5
            case .graphics: return 6
            case .ps2Graphics: return 7
            case .memory: return 8
            case .build: return 9
            case .ps2Build: return 10
            case .pack: return 11
            case .ps2Check: return 12
            case .install: return 13
            case .copy: return 14
            }
        }
    }

    struct Naming: Equatable {
        var phone: String
        var picture: String
        var platform: Platform = .switch
    }

    private struct Track {
        var key: String              // canonical row id, or "raw:<pipeline name>"
        var row: Row?
        var rawName: String?
        var accumulated: TimeInterval = 0
        var activeSince: Date?
        var detail: String?
        var fraction: Double?
        var etaSeconds: Double?
    }

    private var tracks: [Track] = []
    private var naming: Naming
    private let calendar = Calendar.current

    init(naming: Naming) {
        self.naming = naming
    }

    // MARK: Mapping (§6.11)

    /// The row a pipeline or wrapper stage belongs to. `nil` means it is a container ("Preparing the game") or an
    /// unmapped stage, which becomes a row of its own with the pipeline's name (as before the redesign).
    static func row(for name: String, platform: Platform = .switch) -> Row? {
        let s = name.lowercased()
        if s.contains("preparing the game") || s == "preparing the game" { return nil }
        if platform == .ps2 {
            switch s {
            case "reading the game", "reading-disc": return .ps2Disc
            case "rebuilding the game": return nil          // container of the nine pipeline stages
            case "reading-executable": return .ps2Program
            case "translating": return .ps2Rebuild
            case "exploring": return .ps2Explore
            case "compiling-vu", "vu-aot": return .ps2Graphics
            case "building the app", "building", "linking": return .ps2Build
            case "verifying": return .ps2Check
            case "installing on the game", "starting the game": return .install
            case "copying the game to the phone", "copy": return .copy
            default: break
            }
        }
        if s == "signing" { return .pack }
        if s.hasPrefix("install") || s.hasPrefix("starting the game") { return .install }
        if s == "copy" || s.contains("copying the game") { return .copy }
        if s.hasPrefix("read the game") || s.hasPrefix("reading the game")
            || s.hasPrefix("extract") || s.contains("decompress") || s.contains("build id lookup")
            || s.hasPrefix("survey") {
            return .read
        }
        if s == "rewrite" { return .rewrite }
        if s.contains("shader") || s.contains("glsl") || s.contains("vulkan") { return .graphics }
        if s.contains("heap check") || s.contains("address regions") { return .memory }
        if s.hasPrefix("prepare xcode") || s == "app build" || s.hasPrefix("building the app") { return .build }
        if s.hasPrefix("ipa pack") || s.hasPrefix("pack the app") { return .pack }
        return nil
    }

    // MARK: Events

    /// Returns true when the event changed the timeline.
    @discardableResult
    mutating func consume(_ event: ProgressEvent, at time: Date) -> Bool {
        switch event.ev {
        case .stage:
            guard let name = event.name else { return false }
            if let row = Self.row(for: name, platform: naming.platform) { return activate(row, rawName: nil, at: time) }
            let lower = name.lowercased()
            if lower == "preparing the game"
                || (naming.platform == .ps2 && (lower == "rebuilding the game" || lower == "done")) { return false }
            return activateUnknown(name, at: time)
        case .step, .progress:
            guard let name = event.name else { return false }
            guard let index = index(for: name) else { return false }
            let row = tracks[index].row
            var detail: String?
            var rate: String?
            var fraction: Double?
            if row == .copy, event.unit == "B", let done = event.done, let total = event.total {
                let elapsed = event.elapsed ?? activeElapsed(index, at: time)
                if elapsed > 1, done > 0 {
                    let mbs = (done / elapsed) / 1_048_576
                    rate = mbs >= 10 ? String(format: "%.0f", mbs) : String(format: "%.1f", mbs)
                }
                detail = Copy.stageCopyDetail(done: gigabytes(done), total: gigabytes(total), rate: rate ?? "—")
            } else if let done = event.done, let total = event.total {
                let c = StageCopy.count(done: done, total: total, unit: event.unit ?? "", estimate: event.est ?? false)
                if !c.isEmpty { detail = c }
            } else if let note = event.note, !note.isEmpty {
                // The ps2 pipeline sends its plain message in `note`; there is no count to draw.
                detail = note
            } else if let step = event.step, !step.isEmpty, event.ev == .step {
                // A step that is not a count is not drawn: the design has no step line.
                detail = nil
            }
            if let f = event.frac {
                fraction = f
            } else if let done = event.done, let total = event.total, total > 0 {
                fraction = min(max(done / total, 0), 1)
            }
            if let eta = event.eta, eta > 0 { tracks[index].etaSeconds = eta }
            if let detail { tracks[index].detail = detail }
            if let fraction { tracks[index].fraction = fraction }
            return true
        case .stageEnd:
            guard let name = event.name, let index = index(for: name) else { return false }
            close(index, elapsed: event.elapsed, at: time)
            return true
        case .say:
            return false
        }
    }

    private mutating func activate(_ row: Row, rawName: String?, at time: Date) -> Bool {
        let key = row.id
        if let existing = tracks.firstIndex(where: { $0.key == key }) {
            if let since = tracks[existing].activeSince {
                tracks[existing].accumulated += max(0, time.timeIntervalSince(since))
            }
            tracks[existing].activeSince = time
            tracks[existing].detail = nil
            tracks[existing].fraction = nil
            tracks[existing].etaSeconds = nil
            return true
        }
        closeActive(at: time)
        tracks.append(Track(key: key, row: row, rawName: rawName, activeSince: time))
        return true
    }

    /// A stage that started without a row of its own still gets a row, with the pipeline's name (existing behaviour:
    /// an unknown stage keeps its name).
    @discardableResult
    mutating func activateUnknown(_ name: String, at time: Date) -> Bool {
        let key = "raw:" + name
        if tracks.contains(where: { $0.key == key }) { return false }
        closeActive(at: time)
        tracks.append(Track(key: key, row: nil, rawName: name, activeSince: time))
        return true
    }

    private mutating func closeActive(at time: Date) {
        guard let i = tracks.lastIndex(where: { $0.activeSince != nil }) else { return }
        tracks[i].accumulated += max(0, time.timeIntervalSince(tracks[i].activeSince!))
        tracks[i].activeSince = nil
        tracks[i].detail = nil
        tracks[i].fraction = nil
        tracks[i].etaSeconds = nil
    }

    private mutating func close(_ index: Int, elapsed: Double?, at time: Date) {
        if let elapsed, elapsed > 0 {
            tracks[index].accumulated += elapsed
            tracks[index].activeSince = nil
        } else if let since = tracks[index].activeSince {
            tracks[index].accumulated += max(0, time.timeIntervalSince(since))
            tracks[index].activeSince = nil
        }
        tracks[index].detail = nil
        tracks[index].fraction = nil
        tracks[index].etaSeconds = nil
    }

    private func activeElapsed(_ index: Int, at time: Date) -> TimeInterval {
        var total = tracks[index].accumulated
        if let since = tracks[index].activeSince { total += time.timeIntervalSince(since) }
        return total
    }

    private func index(for name: String) -> Int? {
        if let row = Self.row(for: name, platform: naming.platform) {
            return tracks.firstIndex(where: { $0.key == row.id })
        }
        return tracks.firstIndex(where: { $0.key == "raw:" + name })
    }

    // MARK: Output

    var activeRowTitle: String? {
        guard let t = tracks.last(where: { $0.activeSince != nil }) else { return nil }
        return title(for: t, active: true)
    }

    var activeDetail: String? { tracks.last(where: { $0.activeSince != nil })?.detail }

    var stages: [TimelineStage] {
        return tracks
            .sorted { lhs, rhs in
                let l = lhs.row?.rank ?? Int.max
                let r = rhs.row?.rank ?? Int.max
                return l == r ? false : l < r
            }
            .map { t in
                let active = t.activeSince != nil
                let status: TimelineStage.Status = active ? .active : .done(elapsed: t.accumulated)
                var hint: String?
                if t.row == .graphics {
                    hint = active ? Copy.stageGraphicsNote : Copy.stageGraphicsHint
                }
                let detail = t.detail
                var eta: String?
                if active, let s = t.etaSeconds { eta = Copy.duration(s) }
                return TimelineStage(id: t.key, title: title(for: t, active: active), status: status,
                                     detail: detail, fraction: t.fraction, eta: eta, hint: hint)
            }
    }

    private func title(for track: Track, active: Bool) -> String {
        if let raw = track.rawName { return raw }
        switch track.row {
        case .read: return active ? Copy.stageReadActive : Copy.stageRead
        case .rewrite: return Copy.stageRewrite
        case .graphics: return Copy.stageGraphics
        case .memory: return Copy.stageMemory
        case .build: return Copy.stageBuild
        case .pack: return Copy.stagePack
        case .install: return Copy.stageInstall(naming.phone)
        case .copy: return Copy.stageCopy
        case .ps2Disc: return Copy.ps2StageDisc
        case .ps2Program: return Copy.ps2StageProgram
        case .ps2Rebuild: return Copy.ps2StageRebuild
        case .ps2Explore: return Copy.ps2StageExplore
        case .ps2Graphics: return Copy.ps2StageGraphics
        case .ps2Build: return Copy.ps2StageBuild
        case .ps2Check: return Copy.ps2StageCheck
        case nil: return ""
        }
    }

    private func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f", bytes / 1_073_741_824)
    }

    /// §6.13: the copy stage's two info cells need the room left after this and the slot count after this. They are
    /// only drawn when the CLI supplied the phone's numbers; the fixture supplies them for the render.
    static func roomAfter(freeBytes: Int64?, gameBytes: Int64?) -> Int64? {
        guard let freeBytes, let gameBytes else { return nil }
        return max(0, freeBytes - gameBytes)
    }
}
