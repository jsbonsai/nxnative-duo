import Foundation

/// The app's only way into the project: `bin/duo` (doctor, fix, info, build). The app draws; the wrapper decides
/// what a game is, what this Mac needs and how a game gets onto the phone, so the CLI and the app never disagree.
enum Pipeline {
    static let rootDefaultsKey = "DuoBuilder.root"

    /// A folder is the repo when it holds the wrapper and the pipeline the wrapper runs.
    static func isRoot(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/bin/duo")
            && FileManager.default.fileExists(atPath: path + "/scripts/build_ipa_from_nsp.py")
    }

    /// `DUO_ROOT`, the remembered folder, then the parents of the executable (under `swift run` it sits in
    /// <repo>/duo/app/.build/…) and of the working folder.
    static func locate() -> String? {
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["DUO_ROOT"] { candidates.append(env) }
        if let saved = UserDefaults.standard.string(forKey: rootDefaultsKey) { candidates.append(saved) }
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath().path { candidates += ancestors(of: exe) }
        candidates += ancestors(of: Bundle.main.bundleURL.path)
        candidates += ancestors(of: FileManager.default.currentDirectoryPath)
        guard let root = candidates.first(where: isRoot) else { return nil }
        UserDefaults.standard.set(root, forKey: rootDefaultsKey)
        return root
    }

    static func ancestors(of path: String) -> [String] {
        var out: [String] = []
        var url = URL(fileURLWithPath: path)
        for _ in 0..<12 {
            out.append(url.path)
            let up = url.deletingLastPathComponent()
            if up.path == url.path { break }
            url = up
        }
        return out
    }

    /// The wrapper always runs on macOS's own Python 3.9 (it is written for it). Never `env python3`: a PATH
    /// whose python3 is Xcode's or some other one made the old app start the build with the wrong interpreter.
    static let python = "/usr/bin/python3"

    static func duo(_ root: String, _ args: [String]) -> [String] { [root + "/bin/duo"] + args }

    static func environment(root: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["NXN_REPO"] = root
        env["PYTHONUNBUFFERED"] = "1"
        let base = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + base     // a Finder-started app gets a bare PATH
        return env
    }

    struct Capture {
        var status: Int32
        var stdout: String
        var stderr: String
        var lastLine: String {
            let lines = (stderr + "\n" + stdout).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let line = lines.last(where: { !$0.isEmpty }) ?? ""
            return line.hasPrefix("error: ") ? String(line.dropFirst(7)) : line
        }
    }

    private final class Box: @unchecked Sendable {
        var out = Data()
        var err = Data()
    }

    /// A short wrapper command (doctor, info) and its whole output; `timeout` ends one that hangs.
    static func capture(root: String, _ args: [String], timeout: TimeInterval = 120) -> Capture? {
        let p = Process()
        let out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: python)
        p.arguments = duo(root, args)
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        p.environment = environment(root: root)
        do { try p.run() } catch { return nil }
        let box = Box()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) { box.out = out.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global(qos: .userInitiated).async(group: group) { box.err = err.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if p.isRunning { p.terminate() }
        }
        p.waitUntilExit()
        group.wait()
        return Capture(status: p.terminationStatus,
                       stdout: String(decoding: box.out, as: UTF8.self),
                       stderr: String(decoding: box.err, as: UTF8.self))
    }

    static func decode<T: Decodable>(_ type: T.Type, _ text: String) -> T? {
        guard let start = text.firstIndex(of: "{"), let data = String(text[start...]).data(using: .utf8) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try? d.decode(T.self, from: data)
    }
}
