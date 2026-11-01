import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch m.screen {
                case .home: HomeView(targeted: targeted)
                case .working, .failed: WorkingView()
                case .done: DoneView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if m.screen == .home { StatusBar() }
        }
        .background(.background)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard m.screen == .home else { return false }
            Drop.urls(providers) { m.add($0) }
            return true
        }
        .sheet(isPresented: $m.showSetup) { SetupSheet().environmentObject(m) }
        .animation(.easeOut(duration: 0.2), value: m.screen)
    }
}

enum Drop {
    static func urls(_ providers: [NSItemProvider], _ done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}

// MARK: - Home: drop, then the game

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    var targeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            if let info = m.info, info.game != nil {
                GameCard(info: info)
            } else {
                DropZone(targeted: targeted)
            }
            if let notice = m.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
    }
}

struct DropZone: View {
    @EnvironmentObject var m: AppModel
    var targeted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(targeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.15),
                              style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
            VStack(spacing: 14) {
                if m.reading {
                    ProgressView().controlSize(.large)
                    Text("Reading the game…").font(.title3).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(targeted ? Color.accentColor : .secondary)
                    Text("Drop a Switch game")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Your own .nsp or .xci — the game, and its update if you have one.")
                        .foregroundStyle(.secondary)
                    Button("Choose File…") { m.choosePackages() }
                        .controlSize(.large)
                        .padding(.top, 4)
                }
            }
            .padding(40)
        }
    }
}

struct GameCard: View {
    @EnvironmentObject var m: AppModel
    let info: GameInfo

    var body: some View {
        let g = info.game!
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 22) {
                Banner(path: g.icon, size: 150)
                VStack(alignment: .leading, spacing: 6) {
                    Text(g.name ?? "Unknown game")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([g.publisher, g.version.map { "Version \($0)" }].compactMap { $0 }.joined(separator: "  ·  "))
                        .foregroundStyle(.secondary)
                    SupportBadge(support: info.support).padding(.top, 2)
                    PackageChips(info: info).padding(.top, 8)
                }
                Spacer(minLength: 0)
                Button { m.clear() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Choose another game")
            }

            if let games = info.cartridge, games.count > 1 {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.fill").foregroundStyle(.secondary)
                    Text("This cartridge holds \(games.count) games:").foregroundStyle(.secondary)
                    Picker("Game", selection: Binding(get: { info.titleId ?? games[0].title }, set: { m.pickCartridgeGame($0) })) {
                        ForEach(games) { Text($0.name ?? $0.title).tag($0.title) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    Spacer(minLength: 0)
                }
            }

            PictureRow(info: info)

            ForEach(info.problems, id: \.self) { p in
                Label(p, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            Button { m.install() } label: {
                Text(m.ready ? "Install on \(m.device?.name ?? "iPhone")" : "Set Up and Install")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(info.base == nil || !info.problems.isEmpty)
        }
    }
}

struct PackageChips: View {
    @EnvironmentObject var m: AppModel
    let info: GameInfo

    var body: some View {
        HStack(spacing: 8) {
            if let b = info.base { Chip(text: "Game " + (b.displayVersion ?? ""), done: true) }
            if let u = info.update {
                Chip(text: "Update " + (u.displayVersion ?? ""), done: true)
            } else {
                Button { m.choosePackages() } label: { Chip(text: "Add update", done: false) }.buttonStyle(.plain)
            }
            if !info.dlc.isEmpty { Chip(text: "DLC ×\(info.dlc.count)", done: true) }
        }
    }
}

struct Chip: View {
    var text: String
    var done: Bool
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: done ? "checkmark" : "plus").font(.caption.weight(.bold))
            Text(text).font(.callout.weight(.medium)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(done ? Color.primary.opacity(0.07) : Color.accentColor.opacity(0.12)))
        .foregroundStyle(done ? Color.primary : Color.accentColor)
    }
}

/// The one build-time choice there is: the Duo camera. Fill (letterbox, crop, stretch) is changed while playing.
struct PictureRow: View {
    @EnvironmentObject var m: AppModel
    let info: GameInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: m.duoOn ? "rectangle.inset.filled" : "rectangle.center.inset.filled")
                .font(.title3).foregroundStyle(m.duoOn ? Color.accentColor : .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                switch info.duo.state {
                case "available" where !m.duoAvailable:
                    Text("Original shape").fontWeight(.medium)
                    Text("A Duo full-screen patch exists for this game; it applies when you install to an iPhone Duo. Letterbox, crop or stretch can be changed while playing.")
                        .font(.callout).foregroundStyle(.secondary)
                case "available":
                    Toggle(isOn: $m.duoOn) {
                        Text("Duo full screen (experimental)").fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    Text(m.duoOn
                         ? "Uses the patch “\(info.duo.name ?? "Duo camera")” by \(info.duo.author ?? "unknown"): the 3D world fills the inner screen. HUD elements look a little tall."
                         : "Plays at the Switch's shape (letterbox). Crop or stretch can be changed while playing.")
                        .font(.callout).foregroundStyle(.secondary)
                default:
                    Text("Original shape").fontWeight(.medium)
                    Text("Plays at the Switch's shape. Letterbox, crop or stretch can be changed while playing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

struct Banner: View {
    var path: String?
    var size: CGFloat
    var body: some View {
        Group {
            if let path, let img = NSImage(contentsOfFile: path) {
                Image(nsImage: img).resizable().interpolation(.high)
            } else {
                ZStack {
                    LinearGradient(colors: [.red.opacity(0.8), .pink.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller.fill").font(.system(size: size * 0.32)).foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

struct StatusBar: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 8) {
            if m.checking && m.doctor == nil {
                ProgressView().controlSize(.small)
                Text("Checking this Mac…")
            } else if let d = m.doctor, !d.ready {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("\(d.missing.count) \(d.missing.count == 1 ? "thing" : "things") to set up")
            } else if m.doctor != nil {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Installs to")
                DeviceMenu()
            } else {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text(m.root == nil ? "Project folder not found" : "Could not check this Mac")
            }
            Spacer()
            Button("Setup") { m.showSetup = true; m.refreshDoctor() }.buttonStyle(.link)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            if m.screen == .home { m.refreshDevices() }        // a phone plugged in or unplugged shows up by itself
        }
    }
}

/// The connected iPhones and iPads; one tap picks where Install goes. Unplugged ones are listed, greyed, so the player knows why
struct DeviceMenu: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Menu {
            ForEach(m.devices) { d in
                Button {
                    m.choose(d)
                } label: {
                    if d.udid == m.device?.udid { Label(label(d), systemImage: "checkmark") } else { Text(label(d)) }
                }
                .disabled(!d.connected)
            }
            if m.devices.isEmpty { Text("No iPhone found — connect one with a cable") }
        } label: {
            Text(m.device.map { $0.duo ? "\($0.name) (Duo)" : $0.name } ?? "no iPhone connected")
                .fontWeight(.medium).foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func label(_ d: Device) -> String {
        var t = d.name + (d.duo ? " — iPhone Duo" : "")
        if !d.connected { t += "  (not connected)" } else if !d.devmode { t += "  (Developer Mode off)" }
        return t
    }
}

/// How far nxnative has brought the game up: the honest answer to "will it run?"
struct SupportBadge: View {
    let support: GameInfo.Support?
    var body: some View {
        let (text, icon, color): (String, String, Color) = {
            switch support?.state {
            case "tested": return ("Tested with nxnative", "checkmark.seal.fill", .green)
            case "other-version":
                let v = support?.versions.last.map { " (tested: \($0))" } ?? ""
                return ("Another version was tested\(v) — likely works", "checkmark.seal", .blue)
            case "provisional": return ("Still being brought up — may not start", "exclamationmark.triangle.fill", .orange)
            default: return ("New to nxnative — it may not start", "questionmark.circle.fill", .orange)
            }
        }()
        return Label(text, systemImage: icon)
            .font(.callout.weight(.medium))
            .foregroundStyle(color)
    }
}

// MARK: - Working

struct WorkingView: View {
    @EnvironmentObject var m: AppModel
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                Banner(path: m.info?.game?.icon, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(m.title).font(.title3.weight(.semibold))
                    Text(m.duoOn ? "Duo full screen" : "Original shape").foregroundStyle(.secondary)
                }
            }

            if m.screen == .failed {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Install stopped", systemImage: "xmark.octagon.fill")
                        .font(.headline).foregroundStyle(.red)
                    Text(m.failure ?? "Something went wrong.").textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red.opacity(0.08)))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(m.headline).font(.system(size: 20, weight: .semibold, design: .rounded))
                    ProgressView(value: m.fraction).progressViewStyle(.linear)
                    HStack {
                        Text(m.detail.isEmpty ? " " : m.detail).lineLimit(1)
                        Spacer()
                        Text("\(Int((m.fraction * 100).rounded()))%").monospacedDigit()
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
                Text("The first install of a game prepares its graphics: 10–40 minutes. After that it takes about a minute.")
                    .font(.callout).foregroundStyle(.tertiary)
            }

            DisclosureGroup("Details", isExpanded: $showLog) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(m.log.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("end")
                    }
                    .frame(height: 160)
                    .onChange(of: m.log.count) { _ in proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            .font(.callout)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if m.screen == .failed {
                    Button("Back") { m.screen = .home }
                    Button("Try Again") { m.retry() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Cancel") { m.cancel() }
                }
            }
            .controlSize(.large)
        }
        .padding(28)
    }
}

// MARK: - Done

struct DoneView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Banner(path: m.info?.game?.icon, size: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white, .green)
                    .offset(x: 12, y: 12)
            }
            Text("\(m.title) is on \(m.deviceName)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            if m.needsTrust {
                Label {
                    Text("One last step on the iPhone: Settings › General › VPN & Device Management › your Apple ID › Trust. Then open the game.")
                } icon: { Image(systemName: "lock.shield.fill").foregroundStyle(.orange) }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.1)))
                    .frame(maxWidth: 460)
            } else {
                Text("Open it from the Home Screen. The ⚙ button in the game has the picture and control settings.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            Text("A free Apple ID keeps up to 3 of your apps on the phone, for 7 days. Install again to renew.")
                .font(.footnote).foregroundStyle(.tertiary)
            Button("Install Another Game") { m.reset() }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding(.top, 6)
            Spacer()
        }
        .padding(28)
    }
}

// MARK: - Setup

struct SetupSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let missing = m.doctor?.missing ?? []
        let ready = (m.doctor?.items ?? []).filter(\.ok)
        let yours = missing.filter { $0.fix == "manual" }.count
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(missing.isEmpty ? "This Mac is ready" : "Set up this Mac")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(missing.isEmpty ? "Everything Duo Builder needs is in place."
                     : yours == 0 ? "Duo Builder can do all of it for you."
                     : "Duo Builder sets up what it can. \(yours) \(yours == 1 ? "step needs" : "steps need") you.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(missing) { item in
                        SetupRow(item: item)
                        Divider().padding(.leading, 64)
                    }
                    if !ready.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Ready").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                            ForEach(ready) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    Text(item.title)
                                    Text(item.detail).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .font(.callout)
                            }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 18)
                    }
                }
            }

            Divider()
            HStack {
                if m.checking { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
                Spacer()
                Button("Check Again") { m.refreshDoctor() }
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
        .background(.background)
    }
}

struct SetupRow: View {
    @EnvironmentObject var m: AppModel
    let item: Doctor.Item

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if m.fixing == item.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: item.ok ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(item.ok ? Color.green : Color.orange)
                }
            }
            .font(.title2)
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).fontWeight(.semibold)
                Text(m.fixing == item.id ? m.fixLine : item.detail)
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !item.ok, let label = action {
                Button(label) { m.fix(item) }.disabled(m.fixing != nil)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var action: String? {
        switch (item.id, item.fix) {
        case ("xcode", _): return "App Store"
        case ("account", _): return "Open Xcode"
        case ("keys", _): return "Choose…"
        case ("device", _): return nil
        case (_, "auto"): return "Fix"
        case (_, "admin"): return "Fix…"
        default: return nil
        }
    }
}
