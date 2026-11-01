import AppKit
import Foundation
import SwiftUI

/// The window's state. Every decision (what a file is, Duo support, what the Mac needs, how to install) comes
/// from bin/duo; this only keeps what the player dropped and what is on screen.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable { case home, working, done, failed }

    @Published var screen: Screen = .home
    @Published private(set) var root: String?

    // Setup
    @Published var doctor: Doctor?
    @Published var checking = false
    @Published var showSetup = false
    @Published var fixing: String?
    @Published var fixLine = ""

    // The game
    @Published private(set) var files: [String] = []
    @Published var info: GameInfo?
    @Published var reading = false
    @Published var notice: String?
    @Published var duoOn = false
    /// the game picked from a cartridge that holds several; nil = the wrapper's choice (the one a dropped update belongs to)
    @Published var titleID: String?

    // Installing
    @Published var headline = ""
    @Published var detail = ""
    @Published var fraction = 0.0
    @Published var log: [String] = []
    @Published var failure: String?
    @Published var needsTrust = false
    @Published var deviceName = "your iPhone"
    @Published var devices: [Device] = []
    @Published var deviceID: String? = UserDefaults.standard.string(forKey: "DuoBuilder.device") {
        didSet { UserDefaults.standard.set(deviceID, forKey: "DuoBuilder.device") }
    }

    /// The chosen device when it is connected, else the first connected one (the wrapper lists the Duo first)
    var device: Device? {
        let ready = devices.filter(\.connected)
        return ready.first(where: { $0.udid == deviceID }) ?? ready.first
    }
    /// Duo full screen is the Duo inner screen's camera: offered only when the install goes to a Duo
    var duoAvailable: Bool { device?.duo ?? false }

    private var runner: ProcessRunner?
    private var top = (k: 1, n: 6)

    init() {
        root = Pipeline.locate()
        refreshDoctor()
    }

    /// No wrapper calls: for Snapshot's offscreen screens.
    init(preview: Void) {}

    var ready: Bool { doctor?.ready ?? false }
    var title: String { info?.game?.name ?? "Your game" }

    // MARK: Setup

    func refreshDevices() {
        guard let root else { return }
        Task.detached {
            let run = Pipeline.capture(root: root, ["devices", "--json"], timeout: 60)
            let list = run.flatMap { Pipeline.decode(DeviceList.self, $0.stdout) }
            await MainActor.run {
                guard let list else { return }
                self.devices = list.devices
                if let d = self.device { self.deviceName = d.name }
                if !self.duoAvailable { self.duoOn = false }
            }
        }
    }

    func choose(_ d: Device) {
        deviceID = d.udid
        deviceName = d.name
        if !d.duo { duoOn = false }
    }

    func refreshDoctor() {
        refreshDevices()
        guard let root, !checking else { return }
        checking = true
        Task.detached {
            let run = Pipeline.capture(root: root, ["doctor", "--json"], timeout: 90)
            let d = run.flatMap { Pipeline.decode(Doctor.self, $0.stdout) }
            await MainActor.run {
                self.checking = false
                if let d {
                    self.doctor = d

                }
            }
        }
    }

    func fix(_ item: Doctor.Item) {
        guard let root else { return }
        switch item.id {
        case "xcode":
            if let url = URL(string: item.action) { NSWorkspace.shared.open(url) }
            return
        case "keys":
            chooseKeys()
            return
        case "device":
            return
        default:
            break
        }
        let id = item.id == "account" ? "xcode-accounts" : item.id
        fixing = item.id
        fixLine = item.fix == "admin" ? "macOS will ask for your password…" : "Working…"
        do {
            runner = try ProcessRunner(executable: Pipeline.python, arguments: Pipeline.duo(root, ["fix", id, "--json"]),
                                       directory: root, environment: Pipeline.environment(root: root),
                                       onLine: { [weak self] line, _ in
                                           Task { @MainActor in
                                               if let ev = ProgressEvent.parse(line), let msg = ev.msg, !msg.isEmpty {
                                                   self?.fixLine = msg.hasPrefix("[RED] ") ? String(msg.dropFirst(6)) : msg
                                               }
                                           }
                                       },
                                       onExit: { [weak self] _ in
                                           Task { @MainActor in
                                               self?.fixing = nil
                                               self?.refreshDoctor()
                                           }
                                       })
        } catch {
            fixing = nil
            fixLine = error.localizedDescription
        }
    }

    func chooseKeys() {
        let panel = NSOpenPanel()
        panel.message = "Choose your prod.keys"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { setKeys(url.path) }
    }

    func setKeys(_ path: String) {
        guard let root else { return }
        Task.detached {
            let run = Pipeline.capture(root: root, ["keys", path], timeout: 30)
            await MainActor.run {
                if run?.status == 0 {
                    self.notice = nil
                    self.refreshDoctor()
                    if !self.files.isEmpty { self.readFiles() }
                } else {
                    self.notice = run?.lastLine ?? "That is not a prod.keys file."
                }
            }
        }
    }

    // MARK: Files

    /// Anything dropped or chosen: game packages join the game, a keys file becomes the keys, a folder adds the
    /// packages directly inside it.
    func add(_ urls: [URL]) {
        var packages: [String] = []
        for url in urls {
            let path = url.path
            let ext = url.pathExtension.lowercased()
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if ext == "keys" {
                setKeys(path)
            } else if path.hasSuffix(".duopatch.json") || ext == "zip" {
                addPack(path)
            } else if ext == "nsp" || ext == "xci" {
                packages.append(path)
            } else if isDir.boolValue {
                let inside = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                packages += inside.filter { !$0.hasPrefix("._") && ["nsp", "xci"].contains(($0 as NSString).pathExtension.lowercased()) }
                    .sorted().map { path + "/" + $0 }
            } else {
                notice = "\(url.lastPathComponent) is not a Switch game file (.nsp or .xci)."
            }
        }
        guard !packages.isEmpty else { return }
        files = Array(NSOrderedSet(array: files + packages)) as? [String] ?? files + packages
        readFiles()
    }

    /// A Duo patch pack dropped on the window (duo/patches/README.md): checked and kept by the wrapper; the game on screen is
    /// read again so its Duo switch appears when the pack names it
    func addPack(_ path: String) {
        guard let root else { return }
        Task.detached {
            let run = Pipeline.capture(root: root, ["patch", "add", path], timeout: 30)
            await MainActor.run {
                if run?.status == 0 {
                    self.notice = nil
                    if !self.files.isEmpty { self.readFiles() }
                } else {
                    self.notice = run?.lastLine ?? "That is not a Duo patch pack."
                }
            }
        }
    }

    func choosePackages() {
        let panel = NSOpenPanel()
        panel.message = "Choose the game (and its update, if you have it)"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    /// Another game on the same cartridge: read again for that one
    func pickCartridgeGame(_ title: String) {
        guard title != info?.titleId else { return }
        titleID = title
        readFiles()
    }

    func clear() {
        files = []
        titleID = nil
        info = nil
        notice = nil
        screen = .home
    }

    private func readFiles() {
        guard let root else { notice = "The project folder was not found."; return }
        reading = true
        notice = nil
        let args = ["info", "--json"] + (titleID.map { ["--title-id", $0] } ?? []) + files
        Task.detached {
            let run = Pipeline.capture(root: root, args, timeout: 300)
            let decoded = run.flatMap { $0.status == 0 ? Pipeline.decode(GameInfo.self, $0.stdout) : nil }
            await MainActor.run {
                self.reading = false
                guard let decoded else {
                    let why = run?.lastLine ?? ""
                    if why.lowercased().contains("prod.keys") {
                        self.notice = "Add your prod.keys to read this game (drop it on the window)."
                        self.showSetup = false
                    } else {
                        self.notice = why.isEmpty ? "These files could not be read." : why
                    }
                    if self.info == nil { self.files = [] }
                    return
                }
                if decoded.game == nil {          // nothing readable: no card to show the reason on, so say it here
                    self.notice = decoded.problems.first ?? "These files could not be read."
                    self.files = []
                    return
                }
                self.info = decoded
                self.files = decoded.files.isEmpty ? self.files : decoded.files
                self.duoOn = false          // opt-in: every game starts at letterbox, its true shape
            }
        }
    }

    // MARK: Install

    func install() {
        guard let root, info?.base != nil else { return }
        guard ready else { showSetup = true; refreshDoctor(); return }
        screen = .working
        headline = "Reading the game"
        detail = ""
        fraction = 0
        log = []
        failure = nil
        needsTrust = false
        top = (1, 6)
        var args = ["build", "--duo", duoOn ? "on" : "off", "--install", "--progress", "json"]
        if let t = info?.titleId { args += ["--title-id", t] }
        if let d = device { args += ["--device", d.udid]; deviceName = d.name }
        args += files
        do {
            runner = try ProcessRunner(executable: Pipeline.python, arguments: Pipeline.duo(root, args), directory: root,
                                       environment: Pipeline.environment(root: root),
                                       onLine: { [weak self] line, _ in Task { @MainActor in self?.handle(line) } },
                                       onExit: { [weak self] code in Task { @MainActor in self?.finished(code) } })
        } catch {
            fail(error.localizedDescription)
        }
    }

    func cancel() {
        runner?.cancel()
        runner = nil
        screen = .home
    }

    func retry() { install() }

    private func handle(_ line: String) {
        guard let ev = ProgressEvent.parse(line) else {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { appendLog(line) }
            return
        }
        switch ev.ev {
        case .stage where ev.sub != true:
            top = (ev.k ?? top.k, ev.n ?? top.n)
            headline = ev.name ?? headline
            detail = ""
            fraction = max(fraction, Self.span(top.k, top.n).lowerBound)
        case .stage, .step, .progress:
            guard ev.sub == true else { break }
            let k = Double(ev.k ?? 1), n = Double(max(ev.n ?? 1, 1))
            let inner = min(((k - 1) + (ev.frac ?? 0)) / n, 1)
            let span = Self.span(top.k, top.n)
            fraction = max(fraction, span.lowerBound + inner * (span.upperBound - span.lowerBound))
            var parts: [String] = []
            if let name = ev.name { parts.append(StageCopy.headline(for: name) ?? name.capitalized) }
            if let done = ev.done, let total = ev.total {
                let c = StageCopy.count(done: done, total: total, unit: ev.unit ?? "", estimate: ev.est ?? false)
                if !c.isEmpty { parts.append(c) }
            }
            if let eta = ev.eta, eta > 0 { parts.append("about " + StageCopy.duration(eta) + " left") }
            if !parts.isEmpty { detail = parts.joined(separator: " · ") }
        case .stageEnd:
            break
        case .say:
            let msg = ev.msg ?? ""
            appendLog(msg)
            if msg.hasPrefix("[RED] ") { failure = String(msg.dropFirst(6)) }
            if msg.contains(" is on ") && !msg.hasPrefix("[RED]") { detail = "" }
        }
    }

    /// The wrapper's six steps share the bar by how long they take: preparing the game is most of a first build.
    nonisolated static func span(_ k: Int, _ n: Int) -> ClosedRange<Double> {
        let edges: [Double] = n == 6 ? [0, 0.02, 0.86, 0.93, 0.94, 0.99, 1] : [0, 0.03, 0.9, 0.98, 1]
        let i = min(max(k, 1), edges.count - 1)
        return edges[i - 1]...edges[i]
    }

    private func finished(_ code: Int32) {
        runner = nil
        guard screen == .working else { return }
        if code == 0 {
            fraction = 1
            screen = .done
        } else if code == 3, let f = failure, f.lowercased().contains("trust") {
            needsTrust = true          // installed; the phone wants the developer trusted before the first start
            fraction = 1
            screen = .done
        } else {
            fail(failure ?? log.last ?? "The install stopped (exit \(code)).")
        }
    }

    private func fail(_ why: String) {
        failure = why
        screen = .failed
    }

    private func appendLog(_ line: String) {
        log.append(line)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    func reset() {
        clear()
        refreshDoctor()
    }
}
