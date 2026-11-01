import AppKit
import Combine
import Foundation
import SwiftUI

/// The whole of `duo info`'s stdout/stderr, built on the reader's queue. A MainActor hop per line would race the
/// process exit, and a fast read could be decoded before its last line arrived.
final class ReadBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var out = ""
    private var err = ""

    func add(_ line: String, stdout: Bool) {
        lock.lock()
        if stdout { out += line + "\n" } else { err += line + "\n" }
        lock.unlock()
    }

    var stdout: String { lock.lock(); defer { lock.unlock() }; return out }
    var stderr: String { lock.lock(); defer { lock.unlock() }; return err }
}

/// The window's state and the one running job. Every decision (what a file is, Duo support, what the Mac needs,
/// how to install) still comes from bin/duo; this keeps the phase, the current card and the pipeline's events.
///
/// The stores of IMPLEMENTATION.md §2.3 are separate objects, injected into the view tree beside this model:
/// `SetupStore` (doctor), `DeviceStore` (phones), `InstallsStore` (what is on each phone), `LibraryStore` (the
/// shelf) and `SettingsStore`.
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case home
        case reading(ReadingProgress)
        case card
        case working
        case failed(Failure)
        case done(DoneInfo)
    }

    let isPreview: Bool
    let setup: SetupStore
    let phones: DeviceStore
    let installs: InstallsStore
    let library: LibraryStore
    let settings: SettingsStore

    @Published private(set) var phase: Phase = .home
    @Published private(set) var root: String?

    // The game on the card
    @Published private(set) var info: GameInfo?
    @Published private(set) var platform: Platform = .switch
    @Published private(set) var files: [String] = []
    @Published private(set) var fileURLs: [URL] = []
    @Published private(set) var activeEntryID: String?
    /// The bookmarks no longer resolve: the card shows a Locate… chip instead of the file chips (§6.02).
    @Published private(set) var filesMissing = false
    @Published var duoOn = false
    @Published private(set) var titleID: String?
    @Published var notice: String?
    @Published var toast: String?

    // The run
    @Published private(set) var run: BuildRun?
    @Published private(set) var failure: Failure?
    @Published private(set) var needsTrust = false

    // Sheets and prompts
    @Published var showSetup = false
    @Published var setupTarget: String?
    @Published var showRenew = false
    @Published var detailsExpanded = false
    @Published var renewError: String?
    @Published private(set) var cancelPrompt = false
    @Published private(set) var pendingInstallAfterSetup = false

    // Drag and drop
    @Published var hoverURLs: [URL] = []
    @Published var dropTargeted = false

    private var runner: ProcessRunner?
    private var readingRunner: ProcessRunner?
    private var readBuffer: ReadBuffer?
    private var readCancelled = false
    private var top = (k: 1, n: 6)
    private var tracker: StageTracker?
    private var copyStarted: Date?
    private var redSentence: String?
    private var toastTask: Task<Void, Never>?
    private var autoRenewTried: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []

    // MARK: Lifetime

    init() {
        isPreview = false
        let persistent = true
        settings = SettingsStore(persistent: persistent)
        setup = SetupStore()
        phones = DeviceStore(settings: settings)
        installs = InstallsStore()
        library = LibraryStore(persistent: persistent)
        root = Pipeline.locate()
        setup.configure(root: root, settings: settings, onKeysChanged: { [weak self] in self?.reloadAfterKeys() })
        phones.configure(root: root)
        setup.refresh()
        installs.refresh(root: root)
        observeForAutoRenew()
    }

    /// No CLI calls, no disk: for Snapshot's offscreen screens.
    init(preview: Void) {
        isPreview = true
        settings = SettingsStore(persistent: false)
        setup = SetupStore()
        phones = DeviceStore(settings: settings)
        installs = InstallsStore()
        library = LibraryStore(persistent: false)
        root = nil
        setup.configure(root: nil, settings: settings)
    }

    /// §10 auto-renew is opt-in and never runs without the setting. It starts when installs or phones change, once
    /// per app per session.
    private func observeForAutoRenew() {
        installs.$document.receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.autoRenewIfNeeded() }
        }.store(in: &cancellables)
        phones.$devices.receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.autoRenewIfNeeded() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: .duoOpenRenew).receive(on: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in
                self?.showRenew = true
                self?.installs.refresh(root: self?.root)
            }
        }.store(in: &cancellables)
    }

    func autoRenewIfNeeded() {
        guard !isPreview, settings.autoRenew, let phone = selectedInstalls, let device, device.connected else { return }
        for app in phone.apps where (app.daysLeft ?? 99) <= 2 {
            guard !autoRenewTried.contains(app.bundleID), !installs.renewing.contains(app.bundleID) else { continue }
            autoRenewTried.insert(app.bundleID)
            renew(app)
        }
        if settings.reminder { Reminders.reschedule(installs: phone, settings: settings) }
    }

    // MARK: Derived

    var device: Device? { phones.device }
    var phoneName: String { device?.name ?? phones.knownDevice?.name ?? "iPhone" }
    var duoAvailable: Bool { device?.duo ?? false }
    var ready: Bool { setup.doctor?.ready ?? false }
    var title: String { info?.game?.name ?? "Your game" }
    var titleIDForInstall: String? { titleID ?? info?.titleId }

    var selectedInstalls: PhoneInstalls? { installs.phone(id: phones.knownDevice?.udid ?? device?.udid) }

    var onPhoneTitles: Set<String> {
        Set(selectedInstalls?.apps.map(\.title) ?? [])
    }

    func isOnPhone(_ title: String) -> Bool { onPhoneTitles.contains(title) }

    var picture: String { duoOn ? "Duo full screen" : "Original shape" }

    // MARK: Drop

    /// §6.03: hover classification is by extension only; a drop hands the supported URLs to the reader. A file the
    /// panel called "left out" is not read.
    func acceptDrop(_ urls: [URL]) {
        hoverURLs = []
        dropTargeted = false
        let supported = DropKinds.supported(urls)
        guard !supported.isEmpty else { return }
        add(supported)
    }

    /// The drag pasteboard names the dragged files while SwiftUI's `onDrop` only reports that something is over the
    /// window (§6.03 lists them during hover).
    func readDragPasteboard() {
        if isPreview { return }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let drag = NSPasteboard(name: .drag)
        let urls = drag.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        if urls != hoverURLs { hoverURLs = urls }
    }

    // MARK: Setup

    func refreshDoctor() {
        setup.refresh()
        phones.refresh()
    }

    /// §6.06: "Set Up and Install" opens Setup first, then continues automatically when Setup becomes ready.
    func afterSetupIfPending() {
        guard pendingInstallAfterSetup else { return }
        if ready {
            pendingInstallAfterSetup = false
            install()
        }
    }

    func openSetup(target: String? = nil) {
        setupTarget = target
        showSetup = true
        setup.refresh()
        phones.refresh()
    }

    // MARK: Files

    /// Anything dropped or chosen: game packages join the set, a keys file becomes the keys, a patch pack is added,
    /// a folder contributes the packages directly inside it.
    func add(_ urls: [URL]) {
        guard phase != .working else {
            showToast(Copy.dropBusy(run?.gameName ?? title))
            return
        }
        var packages: [URL] = []
        var rejected: [String] = []
        var platformFound = self.platform
        for url in urls {
            let ext = url.pathExtension.lowercased()
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if ext == "keys" {
                setup.setKeys(url.path)
            } else if url.path.hasSuffix(".duopatch.json") || ext == "zip" {
                addPack(url.path)
            } else if ext == "nsp" || ext == "xci" {
                packages.append(url)
            } else if ext == "iso" {
                packages.append(url)
                platformFound = .ps2
            } else if isDir.boolValue {
                let inside = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
                let found = inside.filter { !$0.hasPrefix("._") && ["nsp", "xci", "iso"].contains(($0 as NSString).pathExtension.lowercased()) }
                    .sorted()
                if found.contains(where: { ($0 as NSString).pathExtension.lowercased() == "iso" }) { platformFound = .ps2 }
                packages += found.map { URL(fileURLWithPath: url.path).appendingPathComponent($0) }
            } else {
                rejected.append(url.lastPathComponent)
            }
        }
        if !rejected.isEmpty {
            notice = rejected.map { "\($0) — \(Copy.dropKindUnsupported)" }.joined(separator: "\n")
        }
        guard !packages.isEmpty else { return }
        platform = platformFound
        let unique = packages.reduce(into: [URL]()) { out, url in
            if !out.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { out.append(url) }
        }
        fileURLs = unique
        files = unique.map(\.path)
        readFiles()
    }

    /// A Duo patch pack dropped on the window (duo/patches/README.md): checked and kept by the wrapper; the game on
    /// screen is read again so its Duo switch appears when the pack names it.
    func addPack(_ path: String) {
        guard let root else { notice = "The project folder was not found."; return }
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

    func choosePack() {
        let panel = NSOpenPanel()
        panel.message = Copy.pictureAddPack
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { addPack(url.path) }
    }

    /// Another game on the same cartridge: read again for that one.
    func pickCartridgeGame(_ title: String) {
        guard title != info?.titleId else { return }
        titleID = title
        readFiles()
    }

    /// §6.02: a tile opens its card without reading the game file again. `info` is the card the file was read as.
    func open(_ entry: LibraryEntry) {
        guard phase != .working else {
            showToast(Copy.dropBusy(run?.gameName ?? title))
            return
        }
        library.touch(entry.id)
        activeEntryID = entry.id
        info = entry.info
        platform = entry.platform
        titleID = entry.info?.titleId
        duoOn = false
        files = entry.files.compactMap { $0.url()?.path }
        filesMissing = entry.files.contains { ref in
            guard let url = ref.url() else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        fileURLs = entry.files.compactMap { $0.url() }
        notice = nil
        if info == nil, !fileURLs.isEmpty {
            // An entry from before the card was cached: read it once to fill the card.
            readFiles()
            return
        }
        phase = .card
    }

    /// The Locate… chip: pick the files again, re-read them and refresh the entry's bookmarks.
    func locate() {
        let panel = NSOpenPanel()
        panel.message = Copy.locateChip
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func reloadAfterKeys() {
        if !files.isEmpty { readFiles() }
    }

    func clear() {
        guard phase != .working else { return }
        readingRunner?.cancel()
        readingRunner = nil
        readCancelled = true
        info = nil
        titleID = nil
        files = []
        fileURLs = []
        activeEntryID = nil
        filesMissing = false
        platform = .switch
        notice = nil
        duoOn = false
        phase = .home
    }

    private func readFiles() {
        guard let root else { notice = "The project folder was not found."; return }
        guard !fileURLs.isEmpty else { return }
        readingRunner?.cancel()
        readingRunner = nil
        let buffer = ReadBuffer()
        readBuffer = buffer
        readCancelled = false
        let args = ["info", "--json"] + (titleID.map { ["--title-id", $0] } ?? []) + files
        let progress = ReadingProgress(fileName: fileURLs.first?.lastPathComponent ?? "", startedAt: Date(),
                                       doneBytes: nil, totalBytes: nil)
        notice = nil
        do {
            readingRunner = try ProcessRunner(executable: Pipeline.python, arguments: Pipeline.duo(root, args), directory: root,
                                              environment: Pipeline.environment(root: root),
                                              onLine: { line, isStdout in
                                                  // Appended on the reader's own queue: `finishRead` runs after
                                                  // every line, so the whole JSON is here even for a fast read.
                                                  buffer.add(line, stdout: isStdout)
                                              },
                                              onExit: { [weak self] code in
                                                  Task { @MainActor in self?.finishRead(code) }
                                              })
            // §6.04: a read that finishes in under ~400 ms never flashes the Reading screen.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    guard let self, self.readingRunner != nil, !self.readCancelled else { return }
                    if !self.isReading { self.phase = .reading(progress) }
                }
            }
            // `duo info` had a 300 s timeout in the old reader; keep the same ceiling for a stuck file.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                await MainActor.run {
                    guard let self, self.readingRunner != nil else { return }
                    self.readCancelled = true
                    self.readingRunner?.cancel()
                    self.readingRunner = nil
                    self.notice = "Reading the game took too long."
                    self.phase = self.info == nil ? .home : .card
                }
            }
        } catch {
            readingRunner = nil
            notice = error.localizedDescription
            phase = .home
        }
    }

    private func finishRead(_ code: Int32) {
        readingRunner = nil
        guard !readCancelled else { return }
        let out = readBuffer?.stdout ?? ""
        let err = readBuffer?.stderr ?? ""
        let decoded = code == 0 ? Pipeline.decode(GameInfo.self, out) : nil
        guard let decoded else {
            let combined = err + "\n" + out
            let last = combined.split(separator: "\n").last.map(String.init) ?? ""
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            let why = trimmed.hasPrefix("error: ") ? String(trimmed.dropFirst(7)) : trimmed
            if why.lowercased().contains("prod.keys") {
                notice = "Add your prod.keys to read this game (drop it on the window)."
            } else {
                notice = why.isEmpty ? "These files could not be read." : why
            }
            if info == nil { files = []; fileURLs = [] }
            phase = info == nil ? .home : .card
            return
        }
        if decoded.game == nil {
            notice = decoded.problems.first ?? "These files could not be read."
            files = []
            fileURLs = []
            phase = .home
            return
        }
        info = decoded
        titleID = decoded.titleId
        if decoded.base?.kind == "iso" { platform = .ps2 }
        files = decoded.files.isEmpty ? files : decoded.files
        if decoded.files.isEmpty == false { fileURLs = decoded.files.map { URL(fileURLWithPath: $0) } }
        filesMissing = false
        duoOn = false          // opt-in: every game starts at letterbox, its true shape
        activeEntryID = decoded.titleId ?? decoded.game?.title
        if let entry = library.remember(info: decoded, urls: fileURLs, platform: platform) {
            activeEntryID = entry.id
        }
        phase = .card
    }

    // MARK: Install

    func install() {
        guard let info, info.base != nil else { return }
        guard ready else {
            pendingInstallAfterSetup = true
            openSetup()
            return
        }
        guard let device else {
            return   // the primary button explains this; a menu command cannot bypass it
        }
        guard let root else { notice = "The project folder was not found."; return }

        var args: [String]
        if platform == .ps2 {
            // duo/ps2.md: the `.iso` pipeline owns the disc, the app and the copy; there is no --duo and no key ring.
            guard let iso = files.first(where: { $0.lowercased().hasSuffix(".iso") }) else { return }
            args = ["ps2", "build", "--iso", iso, "--install", "--progress", "json", "--device", device.udid]
            if let bios = settings.ps2BIOS, !bios.isEmpty { args += ["--bios", bios] }
        } else {
            args = ["build", "--duo", duoOn ? "on" : "off", "--install", "--progress", "json"]
            if let t = titleIDForInstall { args += ["--title-id", t] }
            args += ["--device", device.udid]
            args += files
        }

        cancelPrompt = false
        detailsExpanded = false
        needsTrust = false
        redSentence = nil
        failure = nil
        copyStarted = nil
        top = (1, 6)
        let now = Date()
        let cached = CacheProbe.key(for: info) != nil
        run = BuildRun(gameName: title, phone: device.name, picture: picture, startedAt: now, endedAt: nil,
                       fraction: 0, stages: [], log: [], headline: Copy.stageReadActive, detail: "",
                       copy: nil, slotsAfter: nil, roomAfterBytes: nil, failure: nil, wasCachedBefore: cached)
        tracker = StageTracker(naming: .init(phone: device.name, picture: picture, platform: platform))
        phase = .working
        do {
            runner = try ProcessRunner(executable: Pipeline.python, arguments: Pipeline.duo(root, args), directory: root,
                                       environment: Pipeline.environment(root: root),
                                       onLine: { [weak self] line, _ in Task { @MainActor in self?.handle(line) } },
                                       onExit: { [weak self] code in Task { @MainActor in self?.finished(code) } })
        } catch {
            fail(error.localizedDescription)
        }
    }

    func retry() {
        guard phase != .working else { return }
        if info == nil, let entry = activeEntryID.flatMap({ id in library.entries.first(where: { $0.id == id }) }) {
            open(entry)
        }
        install()
    }

    func requestCancel() {
        guard phase == .working || isReading else { return }
        if phase == .working, run?.wasCachedBefore == false, (run?.elapsed ?? 0) >= 600 {
            cancelPrompt = true
        } else {
            cancel()
        }
    }

    var isReading: Bool { if case .reading = phase { return true }; return false }
    var isReadingPhase: Bool { isReading }
    var isWorkingPhase: Bool { if case .working = phase { return true }; return false }
    var isCardPhase: Bool { if case .card = phase { return true }; return false }
    var isDonePhase: Bool { if case .done = phase { return true }; return false }
    var isFailedPhase: Bool { if case .failed = phase { return true }; return false }

    func cancel() {
        cancelPrompt = false
        readingRunner?.cancel()
        readingRunner = nil
        readCancelled = true
        runner?.cancel()
        runner = nil
        run = nil
        failure = nil
        pendingInstallAfterSetup = false
        phase = info == nil ? .home : .card
    }

    func dismissCancelPrompt() {
        cancelPrompt = false
    }

    private func handle(_ line: String) {
        guard var run else { return }
        let now = Date()
        guard let ev = ProgressEvent.parse(line) else {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { appendLog(line) }
            return
        }
        if let name = ev.name, ev.ev == .stage, let row = StageTracker.row(for: name) {
            // The run's header and the copy panel's two info cells (§6.13).
            if row == .copy {
                copyStarted = now
                let phone = selectedInstalls
                let gameBytes = info?.game?.bytes
                run.slotsAfter = phone.map { min($0.slots, $0.used + 1) }
                run.roomAfterBytes = StageTracker.roomAfter(freeBytes: phone?.freeBytes, gameBytes: gameBytes)
            }
        }
        if ev.ev == .progress, let name = ev.name, StageTracker.row(for: name) == .copy,
           let done = ev.done, let total = ev.total, total > 0 {
            let elapsed = ev.elapsed ?? now.timeIntervalSince(copyStarted ?? now)
            let rate = elapsed > 0.2 ? done / elapsed : 0
            run.copy = CopyProgress(doneBytes: Int64(done.rounded()), totalBytes: Int64(total.rounded()), bytesPerSecond: rate)
        }

        switch ev.ev {
        case .stage where ev.sub != true:
            top = (ev.k ?? top.k, ev.n ?? top.n)
            if let title = StageCopy.headline(for: ev.name ?? "") { run.headline = title }
            run.detail = ""
            run.fraction = max(run.fraction, Self.span(top.k, top.n).lowerBound)
        case .stage, .step, .progress:
            guard ev.sub == true else { break }
            let k = Double(ev.k ?? 1), n = Double(max(ev.n ?? 1, 1))
            let inner = min(((k - 1) + (ev.frac ?? 0)) / n, 1)
            let span = Self.span(top.k, top.n)
            run.fraction = max(run.fraction, span.lowerBound + inner * (span.upperBound - span.lowerBound))
            if let title = StageCopy.headline(for: ev.name ?? "") { run.headline = title }
            var parts: [String] = []
            if let done = ev.done, let total = ev.total {
                let c = StageCopy.count(done: done, total: total, unit: ev.unit ?? "", estimate: ev.est ?? false)
                if !c.isEmpty { parts.append(c) }
            }
            if let eta = ev.eta, eta > 0 { parts.append(Copy.etaKnown(StageCopy.duration(eta))) }
            if !parts.isEmpty { run.detail = parts.joined(separator: " · ") }
        case .stageEnd:
            break
        case .say:
            let msg = ev.msg ?? ""
            appendLog(msg)
            if msg.hasPrefix("[RED] ") {
                redSentence = String(msg.dropFirst(6))
                run.failure = Failure(code: .unknown, sentence: redSentence ?? msg, stage: run.currentStageTitle)
            }
            if msg.contains(" is on ") && !msg.hasPrefix("[RED]") { run.detail = "" }
        }
        tracker?.consume(ev, at: now)
        if let tracker {
            run.stages = tracker.stages
            if let title = tracker.activeRowTitle { run.headline = title }
            if let detail = tracker.activeDetail { run.detail = detail }
        }
        self.run = run
    }

    /// The wrapper's six steps share the bar by how long they take: preparing the game is most of a first build.
    nonisolated static func span(_ k: Int, _ n: Int) -> ClosedRange<Double> {
        let edges: [Double] = n == 6 ? [0, 0.02, 0.86, 0.93, 0.94, 0.99, 1] : [0, 0.03, 0.9, 0.98, 1]
        let i = min(max(k, 1), edges.count - 1)
        return edges[i - 1]...edges[i]
    }

    private func finished(_ code: Int32) {
        runner = nil
        guard var run, phase == .working else { return }
        run.endedAt = Date()
        if code == 0 {
            run.fraction = 1
            finishDone(run, trust: false)
        } else if code == 3, let f = redSentence, f.lowercased().contains("trust") {
            needsTrust = true
            run.fraction = 1
            finishDone(run, trust: true)
        } else {
            let sentence = redSentence ?? run.log.last ?? "The install stopped (exit \(code))."
            fail(sentence)
        }
    }

    private func finishDone(_ run: BuildRun, trust: Bool) {
        needsTrust = trust
        self.run = run
        let slots = selectedInstalls?.apps ?? []
        let done = DoneInfo(gameName: run.gameName, phone: run.phone, renewed: false,
                            expiry: slots.first(where: { $0.title == run.gameName })?.expiresAt,
                            took: run.elapsed, needsTrust: trust, slots: slots)
        phase = .done(done)
        if let id = activeEntryID, let info {
            library.setCache(id, key: CacheProbe.key(for: info))
        }
        installs.refresh(root: root)
        Reminders.reschedule(installs: selectedInstalls, settings: settings)
        Reminders.notifyDone(game: run.gameName, phone: run.phone)
    }

    private func fail(_ why: String) {
        guard var run else { return }
        run.endedAt = Date()
        let f = Failure(code: .unknown, sentence: why, stage: run.currentStageTitle)
        run.failure = f
        failure = f
        self.run = run
        phase = .failed(f)
    }

    private func appendLog(_ line: String) {
        guard var run else { return }
        run.log.append(line)
        if run.log.count > 400 { run.log.removeFirst(run.log.count - 400) }
        self.run = run
    }

    // MARK: Shelf actions

    func installFromLibrary(_ entry: LibraryEntry) {
        open(entry)
        install()
    }

    func showInFinder() {
        let urls = fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func removeActiveFromLibrary() {
        guard let id = activeEntryID else { return }
        library.remove(id)
        clear()
    }

    func deletePreparedGraphics(_ entry: LibraryEntry) {
        guard let key = entry.cacheKey else { return }
        try? FileManager.default.removeItem(atPath: key)
        library.setCache(entry.id, key: nil)
    }

    func slotApp(title: String) -> InstalledApp? {
        selectedInstalls?.apps.first(where: { $0.title == title })
    }

    func backToShelf() {
        run = nil
        failure = nil
        notice = nil
        phase = .home
    }

    /// Whether ⌘↩ / the File menu item can install the card that is showing.
    var canInstallNow: Bool {
        guard let info, info.base != nil, info.problems.isEmpty else { return false }
        return ready ? phones.device != nil : true
    }

    func showInLibrary(title: String) {
        guard let entry = library.entries.first(where: { $0.title == title }) else { return }
        open(entry)
    }

    // MARK: Renew

    func renew(_ app: InstalledApp) {
        guard let device else { return }
        renewError = nil
        Task {
            if let error = await installs.renew(bundleID: app.bundleID, deviceID: device.udid, root: root) {
                renewError = error
            } else {
                Reminders.reschedule(installs: selectedInstalls, settings: settings)
            }
        }
    }

    func renewAll() {
        guard let device, let phone = selectedInstalls else { return }
        renewError = nil
        Task {
            for app in phone.apps {
                if let error = await installs.renew(bundleID: app.bundleID, deviceID: device.udid, root: root) {
                    renewError = error
                    return
                }
            }
            Reminders.reschedule(installs: selectedInstalls, settings: settings)
        }
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { if self?.toast == text { self?.toast = nil } }
        }
    }

    // MARK: Snapshot support

    /// Snapshot fixtures only: set the state the renderer should draw without running anything.
    func preview(phase: Phase, info: GameInfo? = nil, platform: Platform = .switch, run: BuildRun? = nil,
                 failure: Failure? = nil, hover: [URL] = [], targeted: Bool = false, notice: String? = nil,
                 activeEntry: String? = nil, duoOn: Bool = false, detailsExpanded: Bool = false) {
        self.info = info
        self.platform = platform
        self.run = run
        self.failure = failure
        self.hoverURLs = hover
        self.dropTargeted = targeted
        self.notice = notice
        self.activeEntryID = activeEntry
        self.duoOn = duoOn
        self.detailsExpanded = detailsExpanded
        self.phase = phase
    }
}
