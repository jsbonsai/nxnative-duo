import AppKit
import SwiftUI

/// `DuoBuilder --snapshot <dir> [--info <duo info json>] [--doctor <duo doctor json>]` draws every screen into PNGs
/// from an offscreen window (real AppKit controls, no display needed): for checking a layout change and for docs.
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
        func file(_ flag: String) -> String? {
            guard let j = args.firstIndex(of: flag), j + 1 < args.count else { return nil }
            return try? String(contentsOfFile: args[j + 1], encoding: .utf8)
        }
        let info = file("--info").flatMap { Pipeline.decode(GameInfo.self, $0) }
        let doctor = file("--doctor").flatMap { Pipeline.decode(Doctor.self, $0) }
        let size = CGSize(width: 680, height: 500)
        let duo = Device(udid: "duo", name: "iPhone", model: "iPhone19,4", os: "27.2", connected: true, wired: true, devmode: true, duo: true)
        let pro = Device(udid: "pro", name: "JIP", model: "iPhone17,1", os: "27.0", connected: true, wired: true, devmode: true, duo: false)

        let scenes: [(String, NSAppearance.Name, (AppModel) -> Void)] = [
            ("1-drop-dark", .darkAqua, { m in m.doctor = doctor }),
            ("1-drop-light", .aqua, { m in m.doctor = doctor }),
            ("2-game-dark", .darkAqua, { m in m.doctor = doctor; m.info = info; m.duoOn = info?.duo.state == "available" }),
            ("2-game-light", .aqua, { m in m.doctor = doctor; m.info = info; m.duoOn = info?.duo.state == "available" }),
            ("2-game-duo", .darkAqua, { m in m.doctor = doctor; m.devices = [duo, pro]; m.deviceID = "duo"; m.info = info; m.duoOn = info?.duo.state == "available" }),
            ("2-game-16pro", .darkAqua, { m in m.doctor = doctor; m.devices = [duo, pro]; m.deviceID = "pro"; m.info = info; m.duoOn = false }),
            ("3-working", .darkAqua, { m in
                m.info = info; m.duoOn = true; m.screen = .working
                m.headline = "Preparing the game"
                m.detail = "Compiling shaders · 18,204 of 62,901 · about 9m 40s left"
                m.fraction = 0.41
            }),
            ("4-failed", .darkAqua, { m in
                m.info = info; m.screen = .failed
                m.failure = "A free Apple ID allows 3 of your own apps on the phone: delete one of them from the phone, then try again."
            }),
            ("5-done", .darkAqua, { m in m.info = info; m.screen = .done; m.deviceName = "iPhone" }),
            ("5-done-trust", .darkAqua, { m in m.info = info; m.screen = .done; m.needsTrust = true; m.deviceName = "iPhone" }),
        ]
        for (name, look, setup) in scenes {
            let m = AppModel(preview: ())
            setup(m)
            render(AnyView(RootView().environmentObject(m).frame(width: size.width, height: size.height)),
                   size: size, look: look, to: dir + "/" + name + ".png")
        }
        let m = AppModel(preview: ())
        m.doctor = doctor
        render(AnyView(SetupSheet().environmentObject(m)), size: CGSize(width: 560, height: 520), look: .darkAqua,
               to: dir + "/6-setup.png")
        return true
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

/// The app icon: a folded Duo with a game on its inner screen, in macOS's rounded-square shape
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
