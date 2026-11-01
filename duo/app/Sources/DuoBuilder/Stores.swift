import Foundation
import SwiftUI

// MARK: - Settings (settings.json)

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet { save() }
    }

    private let fileURL: URL?
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        self.fileURL = persistent ? LibraryStore.supportDirectory()?.appendingPathComponent("settings.json") : nil
        var loaded = Settings()
        if persistent, let fileURL, let data = try? Data(contentsOf: fileURL) {
            loaded = (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
        }
        // The device choice lived in UserDefaults before the shelf; carry it across once.
        if loaded.selectedDevice == nil {
            loaded.selectedDevice = UserDefaults.standard.string(forKey: "DuoBuilder.device")
        }
        self.settings = loaded
    }

    private func save() {
        guard persistent, let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    var selectedDevice: String? {
        get { settings.selectedDevice }
        set { settings.selectedDevice = newValue }
    }

    var reminder: Bool {
        get { settings.reminder }
        set { settings.reminder = newValue }
    }

    var autoRenew: Bool {
        get { settings.autoRenew }
        set { settings.autoRenew = newValue }
    }

    var ps2BIOS: String? {
        get { settings.ps2BIOS }
        set { settings.ps2BIOS = newValue }
    }
}

// MARK: - Devices (existing 6-second poll)

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var refreshing = false

    private var root: String?
    private var timer: Timer?
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func configure(root: String?) {
        self.root = root
        guard timer == nil, root != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    /// The install target: the remembered phone only when it is connected. We never silently install to a
    /// different phone than the one the pill shows; the card asks the user to plug it in instead.
    var device: Device? {
        if let id = settings.selectedDevice {
            return devices.first(where: { $0.udid == id && $0.connected })
        }
        return devices.first(where: \.connected)
    }

    /// The phone the pill and the shelf talk about, connected or not.
    var knownDevice: Device? {
        if let id = settings.selectedDevice, let known = devices.first(where: { $0.udid == id }) { return known }
        return devices.first(where: \.connected) ?? devices.first
    }

    var connected: Bool { device != nil }

    func choose(_ device: Device) {
        settings.selectedDevice = device.udid
    }

    func choose(id: String) {
        settings.selectedDevice = id
    }

    func use(_ devices: [Device]) {
        self.devices = devices
    }

    func refresh() {
        guard let root, !refreshing else { return }
        refreshing = true
        Task.detached {
            let run = Pipeline.capture(root: root, ["devices", "--json"], timeout: 60)
            let list = run.flatMap { Pipeline.decode(DeviceList.self, $0.stdout) }
            await MainActor.run {
                self.refreshing = false
                guard let list else { return }
                self.devices = list.devices
                if let d = self.device, self.settings.selectedDevice != d.udid, !list.devices.contains(where: { $0.udid == self.settings.selectedDevice && $0.connected }) {
                    // A remembered phone that is gone leaves the selection alone (it is listed greyed); only a
                    // first-run choice is filled in.
                    if self.settings.selectedDevice == nil { self.settings.selectedDevice = d.udid }
                }
            }
        }
    }
}

// MARK: - Installs (what is on each phone)

@MainActor
final class InstallsStore: ObservableObject {
    /// Live, this stays nil: `bin/duo` has no `device apps` command yet (IMPLEMENTATION.md §3; DESIGN-QUESTIONS Q2).
    @Published private(set) var document: InstallDocument?
    @Published private(set) var renewing: Set<String> = []
    @Published private(set) var lastError: String?

    var available: Bool { document != nil }

    func phone(id: String?) -> PhoneInstalls? {
        guard let id, let document else { return nil }
        return document.devices.first(where: { $0.deviceID == id })
    }

    /// The contract the UI asks the CLI for: bundle id, title, install date, profile expiry, free bytes, weekly count.
    func refresh(root: String?) {
        guard let root else { return }
        Task.detached {
            let run = Pipeline.capture(root: root, ["device", "apps", "--json"], timeout: 120)
            let doc = run.flatMap { InstallDocument.decode($0.stdout) }
            await MainActor.run {
                if let doc { self.document = doc }
            }
        }
    }

    /// `bin/duo renew <bundle-id> --device <id>` (IMPLEMENTATION.md §3). Returns the CLI's sentence on failure.
    func renew(bundleID: String, deviceID: String, root: String?) async -> String? {
        guard let root else { return "The project folder was not found." }
        renewing.insert(bundleID)
        defer { renewing.remove(bundleID) }
        let run = await Task.detached { Pipeline.capture(root: root, ["renew", bundleID, "--device", deviceID], timeout: 1800) }.value
        if let run, run.status == 0 {
            refresh(root: root)
            lastError = nil
            return nil
        }
        let message = run?.lastLine ?? "The renew did not finish."
        lastError = message
        return message
    }

    func use(_ document: InstallDocument?) {
        self.document = document
    }
}

// MARK: - Setup (doctor and its fixes)

@MainActor
final class SetupStore: ObservableObject {
    @Published private(set) var doctor: Doctor?
    @Published private(set) var checking = false
    @Published private(set) var fixing: String?
    @Published private(set) var fixLine = ""
    @Published private(set) var fixOutput: [String] = []
    @Published private(set) var fixFailed = false
    @Published private(set) var fixFailedID: String?

    private var root: String?
    private var runner: ProcessRunner?
    private var onKeysChanged: (() -> Void)?
    private var settings: SettingsStore?

    func configure(root: String?, settings: SettingsStore? = nil, onKeysChanged: (() -> Void)? = nil) {
        self.root = root
        self.settings = settings
        self.onKeysChanged = onKeysChanged
    }

    func chooseBIOS() {
        let panel = NSOpenPanel()
        panel.message = "Choose your BIOS dump"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings?.ps2BIOS = url.path
            objectWillChange.send()
        }
    }

    var ready: Bool { doctor?.ready ?? false }

    func refresh() {
        guard let root, !checking else { return }
        checking = true
        Task.detached {
            let run = Pipeline.capture(root: root, ["doctor", "--json"], timeout: 90)
            let d = run.flatMap { Pipeline.decode(Doctor.self, $0.stdout) }
            await MainActor.run {
                self.checking = false
                if let d { self.doctor = d }
            }
        }
    }

    func fixLine(for id: String) -> String? {
        fixing == id ? fixLine : nil
    }

    func run(_ action: SetupAction, itemID: String? = nil) {
        guard root != nil else { return }
        switch action {
        case .appStore(let url):
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        case .openXcode:
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Xcode.app"),
                                               configuration: NSWorkspace.OpenConfiguration())
        case .chooseKeys:
            chooseKeys()
        case .chooseBIOS:
            chooseBIOS()
        case .fix(let id):
            fix(id, item: itemID)
        }
    }

    func fix(_ id: String, item: String? = nil) {
        guard let root else { return }
        if item == "xcode" { return }
        let what = id == "account" ? "xcode-accounts" : id
        fixing = item ?? id
        fixFailedID = nil
        fixLine = id == "xcode-setup" ? "macOS will ask for your password…" : "Working…"
        fixOutput = []
        fixFailed = false
        do {
            runner = try ProcessRunner(executable: Pipeline.python, arguments: Pipeline.duo(root, ["fix", what, "--json"]),
                                       directory: root, environment: Pipeline.environment(root: root),
                                       onLine: { [weak self] line, _ in
                                           Task { @MainActor in
                                               guard let self else { return }
                                               let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                               if !text.isEmpty {
                                                   self.fixOutput.append(text)
                                                   if self.fixOutput.count > 400 { self.fixOutput.removeFirst(self.fixOutput.count - 400) }
                                               }
                                               if let ev = ProgressEvent.parse(line), let msg = ev.msg, !msg.isEmpty {
                                                   self.fixLine = msg.hasPrefix("[RED] ") ? String(msg.dropFirst(6)) : msg
                                               } else if !text.isEmpty {
                                                   self.fixLine = text.hasPrefix("error: ") ? String(text.dropFirst(7)) : text
                                               }
                                           }
                                       },
                                       onExit: { [weak self] code in
                                           Task { @MainActor in
                                               guard let self else { return }
                                               self.fixing = nil
                                               self.fixFailed = code != 0
                                               if code != 0 { self.fixFailedID = item ?? id }
                                               if code == 0 { self.refresh() }
                                           }
                                       })
        } catch {
            fixing = nil
            fixFailed = true
            fixFailedID = item ?? id
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
                    self.refresh()
                    self.onKeysChanged?()
                } else {
                    self.fixFailed = true
                    self.fixLine = run?.lastLine ?? "That is not a prod.keys file."
                }
            }
        }
    }

    func use(doctor: Doctor?) {
        self.doctor = doctor
    }

    func use(fixing id: String?, line: String) {
        self.fixing = id
        self.fixLine = line
    }

    func clearFixState() {
        fixing = nil
        fixFailed = false
        fixFailedID = nil
        fixLine = ""
        fixOutput = []
    }
}

/// One row of the Setup checklist. Built from the doctor's items in a fixed order (§6.10) so a step never moves.
struct SetupStep: Identifiable, Equatable {
    enum Status: Equatable {
        case done(value: String)
        case running
        case needsYou
    }

    var id: String
    var title: String
    var rule: String?               // "· at least one", in the group's orange
    var explanation: String
    var value: String
    var details: [String]
    var action: SetupAction?
    var substeps: [SetupSubstep] = []
    var status: Status

    var isDone: Bool { if case .done = status { return true }; return false }
}

struct SetupSubstep: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var done: Bool
    var action: SetupAction?
}

enum SetupAction: Equatable {
    case fix(String)
    case appStore(String)
    case openXcode
    case chooseKeys
    case chooseBIOS
}

extension SetupStore {
    /// Xcode, Xcode first-time setup, Graphics compiler, iOS SDK, Build tools, .NET 10 SDK, Python environment,
    /// Apple ID in Xcode, iPhone, Files from your own console, Free space.
    static let order = ["xcode", "xcode-setup", "metal", "ios-sdk", "tools", "dotnet", "python",
                        "account", "device", "keys", "space", "ps2-tools", "ps2-space"]

    var steps: [SetupStep] {
        guard let doctor else { return [] }
        let byID = Dictionary(doctor.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var steps: [SetupStep] = []
        for id in SetupStore.order {
            guard let item = byID[id] else { continue }
            if id == "keys" {
                steps.append(filesStep(item))
                continue
            }
            steps.append(step(item))
        }
        // A doctor item the app has never seen stays visible, after the known ones, rather than disappearing.
        for item in doctor.items where !SetupStore.order.contains(item.id) {
            steps.append(step(item))
        }
        return steps
    }

    private func step(_ item: Doctor.Item) -> SetupStep {
        let title: String
        switch item.id {
        case "xcode": title = Copy.stepXcode
        case "xcode-setup": title = Copy.stepXcodeSetup
        case "metal": title = Copy.stepCompiler
        case "ios-sdk": title = Copy.stepSDK
        case "tools": title = Copy.stepTools
        case "dotnet": title = Copy.stepDotnet
        case "python": title = Copy.stepPython
        case "account": title = Copy.stepAppleID
        case "device": title = Copy.stepiPhone
        case "space": title = Copy.stepSpace
        default: title = item.title
        }

        let action: SetupAction?
        if !item.ok {
            switch item.id {
            case "xcode": action = item.action.isEmpty ? nil : .appStore(item.action)
            case "account": action = .openXcode
            case "device": action = nil
            case "keys", "space", "metal": action = nil
            default:
                switch item.fix {
                case "auto": action = .fix(item.id)
                case "admin": action = .fix(item.id)
                default: action = nil
                }
            }
        } else {
            action = nil
        }

        let explanation: String
        if item.id == "account" && !item.ok {
            explanation = Copy.stepAppleIDBody
        } else if item.id == "device" && !item.ok {
            explanation = item.detail.lowercased().contains("developer mode") ? item.detail : Copy.stepiPhoneBody
        } else if item.id == "space" && !item.ok {
            explanation = item.detail
        } else {
            explanation = item.detail
        }

        let status: SetupStep.Status = fixing == item.id ? .running : (item.ok ? .done(value: shortValue(item)) : .needsYou)
        return SetupStep(id: item.id, title: title, rule: nil, explanation: explanation,
                         value: shortValue(item), details: [item.detail].filter { !$0.isEmpty },
                         action: action, status: status)
    }

    private func filesStep(_ keys: Doctor.Item) -> SetupStep {
        let bios = settings?.ps2BIOS
        let biosPresent = !(bios ?? "").isEmpty
        let done = keys.ok || biosPresent
        let keyAction: SetupAction? = keys.ok ? nil : .chooseKeys
        let sub = [
            SetupSubstep(id: "keys", title: Copy.stepKeys, body: Copy.stepKeysBody, done: keys.ok, action: keyAction),
            SetupSubstep(id: "ps2-bios", title: Copy.stepBios, body: Copy.stepBiosBody, done: biosPresent,
                         action: biosPresent ? nil : .chooseBIOS),
        ]
        let value = biosPresent ? ((bios! as NSString).lastPathComponent) : shortValue(keys)
        return SetupStep(id: "files", title: Copy.stepFiles, rule: Copy.stepFilesRule,
                         explanation: Copy.stepFilesBody, value: done ? value : "",
                         details: [keys.detail].filter { !$0.isEmpty }, action: nil, substeps: sub,
                         status: done ? .done(value: value) : .needsYou)
    }

    private func shortValue(_ item: Doctor.Item) -> String {
        switch item.id {
        case "account":
            return item.detail.hasPrefix("signed in") ? "signed in" : item.detail
        case "python":
            return item.ok ? "ready" : ""
        case "keys":
            if item.ok {
                let name = (item.detail as NSString).lastPathComponent
                return name.isEmpty ? "ready" : name
            }
            return ""
        case "metal":
            return item.ok ? Copy.stepCompilerNewer : ""
        case "xcode":
            return item.ok ? "installed" : ""
        default:
            return item.detail
        }
    }
}

// MARK: - Snapshot fixtures (not used by the live app)

enum Fixture {
    static func decode<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        if let value = try? d.decode(T.self, from: data) { return value }
        // Types with their own snake_case CodingKeys (the installs contract) need no key strategy.
        let plain = JSONDecoder()
        plain.dateDecodingStrategy = .iso8601
        return try? plain.decode(T.self, from: data)
    }
}
