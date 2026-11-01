import Foundation

/// One line of `--progress json` (docs/frontends.md): `ev` is `stage`, `step`, `progress`, `stage_end` or
/// `say`, and every other field is optional so one reader survives a stage that omits one.
struct ProgressEvent: Decodable, Equatable {
    enum Kind: String, Decodable {
        case stage
        case step
        case progress
        case stageEnd = "stage_end"
        case say
    }

    let ev: Kind
    let k: Int?
    let n: Int?
    let name: String?
    let step: String?
    let done: Double?
    let total: Double?
    let unit: String?
    let est: Bool?
    let note: String?
    let frac: Double?
    let eta: Double?
    let elapsed: Double?
    let ok: Bool?
    let summary: String?
    let msg: String?
    /// true for the pipeline's own stages, which bin/duo forwards nested inside its step 2 ("Preparing the game")
    let sub: Bool?

    /// nil for every line that is not one of the pipeline's JSON events (bin/duo's own messages, stderr).
    static func parse(_ line: String) -> ProgressEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProgressEvent.self, from: data)
    }
}

/// The pipeline's stage names, in plain words (duo/RELEASE.md §2: "Reading the game… Rebuilding its
/// executable… Compiling shaders (this is the long one, 10–40 min)…"). An unknown stage keeps its name.
enum StageCopy {
    static func headline(for stage: String) -> String? {
        let s = stage.lowercased()
        if s.hasPrefix("extract") || s.contains("decompress") || s.contains("build id lookup") || s.hasPrefix("survey") {
            return "Reading the game…"
        }
        if s == "rewrite" { return "Rebuilding the game's executable…" }
        if s.contains("shader") || s.contains("glsl") || s.contains("vulkan") {
            return "Compiling shaders (this is the long one, 10–40 minutes the first time)…"
        }
        if s.hasPrefix("prepare xcode") { return "Preparing Xcode…" }
        if s == "app build" { return "Building the app for the phone…" }
        if s.hasPrefix("ipa pack") { return "Packing the app…" }
        if s.contains("heap check") || s.contains("address regions") { return "Checking the game's memory layout…" }
        return nil
    }

    /// "1.9/~5.0 GB", "1,203/~19,592 shaders", "2,301 files"; "" without a count. The pipeline's own `_count`.
    static func count(done: Double, total: Double, unit: String, estimate: Bool) -> String {
        guard done > 0 || total > 0 else { return "" }
        if total <= 0 {
            return unit == "B" ? bytes(done) : "\(Int(done).formatted())" + (unit.isEmpty ? "" : " \(unit)")
        }
        let tilde = estimate ? "~" : ""
        if unit == "B" {
            return "\(bytes(done)) of \(tilde)\(bytes(total))"
        }
        return "\(Int(done).formatted()) of \(tilde)\(Int(total).formatted())" + (unit.isEmpty ? "" : " \(unit)")
    }

    static func bytes(_ v: Double) -> String {
        for (unit, divisor) in [("GB", 1_073_741_824.0), ("MB", 1_048_576.0)] where v >= divisor {
            return String(format: "%.1f %@", v / divisor, unit)
        }
        return String(format: "%.0f KB", v / 1024)
    }

    /// "4m 12s", "1h 03m", "38s": the elapsed and ETA times.
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        if s >= 60 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return "\(s)s"
    }
}
