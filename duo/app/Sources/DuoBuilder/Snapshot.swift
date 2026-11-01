import AppKit
import SwiftUI

/// `DuoBuilder --snapshot <dir> --fixtures <dir>` draws every screen of IMPLEMENTATION.md §12 into PNGs from an
/// offscreen window (real AppKit controls, no display needed). `--info` and `--doctor` remain for the two states the
/// old renderer knew; `--fixtures` adds the library, installs, run, failure and done fixtures.
///
/// Output names follow the pack's screen index and the appearance is a suffix, e.g. `02-home-dark.png` and
/// `02-home-light.png`.
enum Snapshot {
    @MainActor
    static func runIfAsked() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {     // the app icon at 1024 px, for package.sh
            render(AnyView(AppIcon()), size: CGSize(width: 1024, height: 1024), look: .darkAqua, to: args[i + 1], scale: 1)
            return true
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = args[i + 1]
        NSApp.setActivationPolicy(.regular)        // an active app draws prominent buttons in the accent colour
        NSApp.activate(ignoringOtherApps: true)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        func flag(_ name: String) -> String? {
            guard let j = args.firstIndex(of: name), j + 1 < args.count else { return nil }
            return args[j + 1]
        }

        let fixtures = flag("--fixtures")
        let doctor = load(Doctor.self, fixtures, "doctor.json") ?? flag("--doctor").flatMap { read(Doctor.self, $0) }
        let doctorReady = load(Doctor.self, fixtures, "doctor-ready.json") ?? doctor
        let library = load([LibraryEntry].self, fixtures, "library.json") ?? []
        let installs = load(InstallDocument.self, fixtures, "installs.json")
        let installsFull = load(InstallDocument.self, fixtures, "installs-full.json") ?? installs
        let lantern = load(GameInfo.self, fixtures, "info-lantern.json") ?? flag("--info").flatMap { read(GameInfo.self, $0) }
        let stone = load(GameInfo.self, fixtures, "info-stone.json")
        let ps2 = load(GameInfo.self, fixtures, "info-ps2.json")
        let night = load(GameInfo.self, fixtures, "info-night.json")
        let runEarly = load(RunFixture.self, fixtures, "run-early.json")
        let runGraphics = load(RunFixture.self, fixtures, "run-graphics.json")
        let runPS2 = load(RunFixture.self, fixtures, "run-ps2-copy.json")
        let failureFixture = load(FailureFixture.self, fixtures, "failure-slots-full.json")
        let doneTrust = load(DoneFixture.self, fixtures, "done-trust.json")
        let doneRenewed = load(DoneFixture.self, fixtures, "done-renewed.json")

        let duo = Device(udid: "duo", name: "iPhone Duo", model: "iPhone19,4", os: "27.2",
                         connected: true, wired: true, devmode: true, duo: true)
        let pro = Device(udid: "pro", name: "iPhone 16 Pro", model: "iPhone17,1", os: "27.0",
                         connected: true, wired: true, devmode: true, duo: false)

        let screen = CGSize(width: 720, height: 560)
        let looks: [NSAppearance.Name] = [.darkAqua, .aqua]
        func suffix(_ look: NSAppearance.Name) -> String { look == .darkAqua ? "dark" : "light" }

        func make(doctor: Doctor?, library: [LibraryEntry], installs: InstallDocument?,
                  devices: [Device], selected: String?) -> AppModel {
            let m = AppModel(preview: ())
            m.setup.use(doctor: doctor)
            m.library.use(library)
            m.installs.use(installs)
            m.phones.use(devices)
            m.settings.selectedDevice = selected
            return m
        }

        func screenScene(_ name: String, _ configure: @escaping (AppModel) -> Void) {
            for look in looks {
                let m = make(doctor: doctorReady, library: library, installs: installs,
                             devices: [duo, pro], selected: "duo")
                configure(m)
                render(root(m), size: screen, look: look, to: dir + "/" + name + "-" + suffix(look) + ".png")
            }
        }

        // 01 — first launch, nothing set up, no phone, empty library.
        screenScene("01-home-first-run") { m in
            m.setup.use(doctor: doctor)
            m.phones.use([])
            m.library.use([])
            m.installs.use(nil)
            m.preview(phase: .home)
        }
        // 02 — normal shelf: 2 of 3 slots, library of 9.
        screenScene("02-home") { m in
            m.preview(phase: .home)
        }
        // 03 — files dragged over the window.
        screenScene("03-home-drag-over") { m in
            let urls = [URL(fileURLWithPath: "~/Games/Games/kite-valley.xci"),
                        URL(fileURLWithPath: "~/Games/Games/kite-valley-v1.3.nsp"),
                        URL(fileURLWithPath: "~/Games/notes.txt")]
            m.preview(phase: .home, hover: urls, targeted: true)
        }
        // 04 — reading the game.
        screenScene("04-reading-the-game") { m in
            m.preview(phase: .reading(ReadingProgress(fileName: "kite-valley.xci", startedAt: Date(),
                                                      doneBytes: nil, totalBytes: nil)))
        }
        // 06 — another version tested, Duo pack on, DLC.
        screenScene("06-card-other-version-duo-pack") { m in
            m.preview(phase: .card, info: lantern, activeEntry: "0100000000000001", duoOn: true)
        }
        // 07 — two-game cartridge, new to nxnative, blocked with a reason.
        screenScene("07-card-two-game-cartridge-blocked") { m in
            m.preview(phase: .card, info: stone, activeEntry: "0100000000000002")
        }
        // 08 — PS2 .iso, phone free-space check.
        screenScene("08-card-ps2") { m in
            m.settings.selectedDevice = "pro"
            m.settings.ps2BIOS = "~/Games/Bios/SCPH-70012.bin"
            m.preview(phase: .card, info: ps2, platform: .ps2, activeEntry: "0100000000000003")
        }
        // 09 — tested, already built.
        screenScene("09-card-tested-cached") { m in
            m.preview(phase: .card, info: night, activeEntry: "0100000000000004")
        }
        // 11 — working, first stage, ETA unknown, Details open.
        screenScene("11-working-early") { m in
            guard let runEarly else { return }
            m.preview(phase: .working, info: lantern, run: runEarly.build(), detailsExpanded: true)
        }
        // 12 — the long stage, with timeline.
        screenScene("12-working-graphics") { m in
            guard let runGraphics else { return }
            m.preview(phase: .working, info: lantern, run: runGraphics.build(), duoOn: true)
        }
        // 13 — PS2 copy-to-phone stage.
        screenScene("13-working-ps2-copying") { m in
            guard let runPS2 else { return }
            m.settings.selectedDevice = "pro"
            m.preview(phase: .working, info: ps2, platform: .ps2, run: runPS2.build())
        }
        // 14 — 3-app limit hit, the ladder.
        screenScene("14-failed") { m in
            guard let f = failureFixture else { return }
            m.installs.use(installsFull)
            let failure = f.failure()
            m.preview(phase: .failed(failure), info: night, run: f.build(), failure: failure)
        }
        // 15 — first install of an Apple ID on this phone → Trust step.
        screenScene("15-done-trust-step") { m in
            guard let d = doneTrust else { return }
            m.installs.use(installsFull)
            m.settings.reminder = true
            m.preview(phase: .done(d.info(installs: installsFull)), info: lantern, activeEntry: "0100000000000001")
        }
        // 16 — renew finished, no Trust step.
        screenScene("16-done-renewed") { m in
            guard let d = doneRenewed else { return }
            m.installs.use(installsFull)
            m.settings.reminder = true
            m.preview(phase: .done(d.info(installs: installsFull)), info: nil, activeEntry: "0100000000000005")
        }

        // 10 — Setup sheet.
        for look in looks {
            let m = make(doctor: doctor, library: library, installs: installs, devices: [duo, pro], selected: "duo")
            if doctor?.items.first(where: { $0.id == "dotnet" })?.ok == false {
                m.setup.use(fixing: "dotnet", line: "")
            }
            render(sheet(m, AnyView(SetupSheet())), size: CGSize(width: 560, height: 520), look: look,
                   to: dir + "/10-setup-sheet-" + suffix(look) + ".png")
        }
        // 17 — On this iPhone / renew sheet.
        for look in looks {
            let m = make(doctor: doctor, library: library, installs: installsFull, devices: [duo, pro], selected: "duo")
            m.settings.reminder = true
            render(sheet(m, AnyView(RenewSheet())), size: CGSize(width: 560, height: 490), look: look,
                   to: dir + "/17-on-this-iphone-renew-sheet-" + suffix(look) + ".png")
        }
        return true
    }

    // MARK: Fixtures

    private static func load<T: Decodable>(_ type: T.Type, _ directory: String?, _ name: String) -> T? {
        guard let directory else { return nil }
        return Fixture.decode(type, from: directory + "/" + name)
    }

    private static func read<T: Decodable>(_ type: T.Type, _ path: String) -> T? {
        Fixture.decode(type, from: path)
    }

    struct StageFixture: Decodable {
        var id: String
        var title: String
        var status: String
        var elapsed: Double?
        var detail: String?
        var fraction: Double?
        var eta: String?
        var hint: String?
    }

    struct CopyFixture: Decodable {
        var doneBytes: Double
        var totalBytes: Double
        var bytesPerSecond: Double
    }

    struct RunFixture: Decodable {
        var game: String
        var phone: String
        var picture: String
        var fraction: Double
        var elapsed: Double
        var stages: [StageFixture]
        var log: [String]
        var copy: CopyFixture?
        var slotsAfter: Int?
        var roomAfterBytes: Int64?

        func build() -> BuildRun {
            let stages = self.stages.map { s -> TimelineStage in
                let status: TimelineStage.Status
                switch s.status {
                case "done": status = .done(elapsed: s.elapsed ?? 0)
                case "active": status = .active
                default: status = .pending
                }
                return TimelineStage(id: s.id, title: s.title, status: status, detail: s.detail,
                                     fraction: s.fraction, eta: s.eta, hint: s.hint)
            }
            return BuildRun(gameName: game, phone: phone, picture: picture,
                            startedAt: Date().addingTimeInterval(-elapsed), endedAt: nil,
                            fraction: fraction, stages: stages, log: log, headline: stages.last?.title ?? "",
                            detail: stages.last?.detail ?? "",
                            copy: copy.map { CopyProgress(doneBytes: Int64($0.doneBytes),
                                                          totalBytes: Int64($0.totalBytes),
                                                          bytesPerSecond: $0.bytesPerSecond) },
                            slotsAfter: slotsAfter, roomAfterBytes: roomAfterBytes)
        }
    }

    struct FailureFixture: Decodable {
        var code: String?
        var sentence: String
        var phone: String
        var game: String
        var picture: String
        var stage: String?
        var elapsed: Double?
        var log: [String]?

        func failure() -> Failure {
            Failure(code: code.flatMap(Failure.Code.init(rawValue:)) ?? .unknown, sentence: sentence, stage: stage)
        }

        func build() -> BuildRun {
            let failure = self.failure()
            return BuildRun(gameName: game, phone: phone, picture: picture,
                            startedAt: Date().addingTimeInterval(-(elapsed ?? 0)),
                            endedAt: Date(), fraction: 0, stages: [], log: log ?? [],
                            headline: stage ?? "", detail: "", failure: failure)
        }
    }

    struct DoneFixture: Decodable {
        var game: String
        var phone: String
        var renewed: Bool
        var expiry: Date?
        var took: Double
        var needsTrust: Bool

        func info(installs: InstallDocument?) -> DoneInfo {
            let slots = installs?.devices.first(where: { $0.deviceName == phone })?.apps ?? []
            return DoneInfo(gameName: game, phone: phone, renewed: renewed, expiry: expiry, took: took,
                            needsTrust: needsTrust, slots: slots)
        }
    }

    // MARK: Rendering

    @MainActor
    private static func root(_ m: AppModel) -> AnyView {
        AnyView(RootView()
            .environmentObject(m)
            .environmentObject(m.setup)
            .environmentObject(m.phones)
            .environmentObject(m.installs)
            .environmentObject(m.library)
            .environmentObject(m.settings)
            .environment(\.controlActiveState, .key))
    }

    @MainActor
    private static func sheet(_ m: AppModel, _ view: AnyView) -> AnyView {
        AnyView(view
            .environmentObject(m)
            .environmentObject(m.setup)
            .environmentObject(m.phones)
            .environmentObject(m.installs)
            .environmentObject(m.library)
            .environmentObject(m.settings)
            .environment(\.controlActiveState, .key))
    }

    @MainActor
    static func render(_ view: AnyView, size: CGSize, look: NSAppearance.Name, to path: String, scale: CGFloat = 2) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = KeyWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: look)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.makeKeyAndOrderFront(nil)     // key, so prominent buttons draw in the accent colour as in the real window
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))      // let SwiftUI lay out and load images
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }
}

/// A borderless window that may become key (a plain borderless one cannot).
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The app icon: a folded Duo with a game on its inner screen, in macOS's rounded-square shape. §13 offers three
/// directions and leaves the choice to the owner (DESIGN-QUESTIONS Q11); the current abstract icon stays.
struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.18, blue: 0.24), Color(red: 0.62, green: 0.06, blue: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .frame(width: 560, height: 400)
                .overlay(RoundedRectangle(cornerRadius: 70, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 6))
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 6, height: 400)          // the fold
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 210, weight: .regular))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}
