// Launcher settings, validation and persistence. Shared by the iOS UI, the Mac app's settings window (dm/mac/Launcher.swift) and the native storage regression test.
import Foundation
import Combine

struct Setting: Decodable, Identifiable {
    let env, kind, label, note, def: String
    let section: String?   // heading on the settings screen; absent in older bundles
    let needs: String?     // "<VAR>=<value>": a sub-setting, drawn only while that setting has that value
    let level: String?     // "basic": shown first (the Mac window's Basic settings); any other or none: Advanced settings. The iPhone keeps one list
    let base: Base?        // render scale: the 3D views' size at 1.0, docked and handheld, for the size in pixels (the Mac window)
    struct Base: Decodable { let docked, handheld: [Int] }
    let options: [[String]]?   // choice: [value, label]
    let min, max, step: Double?   // range
    let on, off: String?   // toggle: the values the variable takes (1 / 0 when not given)
    var id: String { env }
    var sectionTitle: String { section ?? "Game" }
    var basic: Bool { level == "basic" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }
    func isDefault(_ v: String) -> Bool {   // a range compares as numbers (a slider writes 1.00 for 1.0)
        kind == "range" ? abs((Double(v) ?? .nan) - (Double(def) ?? .nan)) < 1e-6 : v == def
    }
    func accepts(_ v: String) -> Bool {   // a saved choice the game still offers
        switch kind {
        case "choice": return options?.contains { $0[0] == v } ?? false
        case "range":
            guard !v.contains(where: { $0 == "x" || $0 == "X" }), let n = Double(v), n.isFinite, let lo = min, let hi = max else { return false }   // no hex: launcher.c's check agrees
            return n >= lo && n <= hi
        case "toggle": return v == onValue || v == offValue
        default: return true
        }
    }
    enum CodingKeys: String, CodingKey { case env, kind, label, note, def = "default", section, needs, level, base, options, min, max, step, on, off }
}
struct SettingsFile: Decodable { let settings: [Setting] }

/// One heading and its rows, in the catalogue's order. The iOS launcher's List, the Mac window's Form and the in-game menu draw these, so
/// the three screens cannot group one list differently (duo/design/settings-ui.md §2)
struct SettingSection: Identifiable {
    let title: String
    let rows: [Setting]
    var id: String { title }
}

/// The one grouping behind every settings screen: the catalogue's section order (first appearance), the `needs` rule, and the two optional
/// selections a screen may ask for (a search filter; the Mac window's Basic / Advanced split). The rows themselves come from dm/launcher.json;
/// nothing here names a setting
enum SettingsGrouping {
    /// `values` is what the screen shows for each variable: the launcher's draft, or the running game's values in the menu
    static func sections(_ settings: [Setting], values: [String: String], matching query: String = "", basic: Bool? = nil) -> [SettingSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var order: [String] = [], rows: [String: [Setting]] = [:]
        for s in settings {
            if let b = basic, s.basic != b { continue }
            guard visible(s, values), q.isEmpty || matches(s, q) else { continue }
            if rows[s.sectionTitle] == nil { order.append(s.sectionTitle); rows[s.sectionTitle] = [] }
            rows[s.sectionTitle]?.append(s)
        }
        return order.map { SettingSection(title: $0, rows: rows[$0] ?? []) }
    }

    /// A row with "needs" is a sub-setting of the row it names: drawn only while that setting has that value, so a
    /// setting that cannot do anything is not offered (an upscaler's detail with the upscaler off, rumble strength
    /// with rumble off). A row naming a setting this game does not have stays drawn, as it has nothing to hide behind
    static func visible(_ s: Setting, _ values: [String: String]) -> Bool {
        guard let n = s.needs, let eq = n.firstIndex(of: "=") else { return true }
        let key = String(n[n.startIndex..<eq]), want = String(n[n.index(after: eq)...])
        guard let v = values[key] else { return true }
        return v == want
    }

    /// The in-game menu's filter: the row's name, its description, the switch it sets and its heading, case-insensitively
    static func matches(_ s: Setting, _ q: String) -> Bool {
        [s.label, s.note, s.env, s.sectionTitle].contains { $0.lowercased().contains(q) }
    }
}

// One game's settings: the rows, what an env file or the launch environment fixed, and the one place a choice is read and written.
// The launcher (LauncherModel, which delegates to it) and the in-game menu (InGameMenu.swift) share it, so a choice made on either
// screen is the same value, under the same key (`launcher.<VAR>`, which the Mac app reads through CFPreferences), with one Reset rule
final class SettingsStore {
    let settings: [Setting]
    let fixed: Set<String>        // set by an env file or by the launch environment: shown, never changed
    let fromLaunch: Set<String>   // of those, the ones the launch environment set (DM_ENV_LAUNCH_KEYS from launcher.c or main.m)
    let ignoreSaved: Bool         // DM_SAVED_CHOICES=0: the defaults, and nothing written
    private let defaults: UserDefaults

    init(_ settings: [Setting], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = settings
        let env = ProcessInfo.processInfo.environment
        fromLaunch = Set((env["DM_ENV_LAUNCH_KEYS"] ?? "").split(separator: " ").map(String.init))
        fixed = fromLaunch.union((env["DM_ENV_FILE_KEYS"] ?? "").split(separator: " ").map(String.init))
        ignoreSaved = env["DM_SAVED_CHOICES"] == "0"
    }

    // The launcher's value: an env file's or the launch environment's value for a fixed row, else the saved choice, else the
    // game's default. A saved choice the game no longer offers reads as its default
    func current(_ s: Setting) -> String {
        if fixed.contains(s.env), let v = ProcessInfo.processInfo.environment[s.env] { return v }
        let saved = ignoreSaved ? nil : defaults.object(forKey: "launcher." + s.env) as? String   // a string, as launcher.c reads it: not string(forKey:), which turns a number into one
        return saved.flatMap { s.accepts($0) ? $0 : nil } ?? s.def
    }

    // The value the running game has: what Play wrote into the environment this run first (a choice the player made that equals
    // the default is not stored, so the store alone cannot tell it), then current(). The menu is only ever made after Play
    func applied(_ s: Setting) -> String {
        guard let v = ProcessInfo.processInfo.environment[s.env], !v.isEmpty else { return current(s) }
        return v
    }

    // Store one choice exactly as Play does: a default removes the key, a change writes `launcher.<env>`; a fixed row and
    // DM_SAVED_CHOICES=0 write nothing. true when a choice is now stored. The environment is the launch-time record: not touched here
    @discardableResult func store(_ s: Setting, _ v: String) -> Bool {
        guard !fixed.contains(s.env), !ignoreSaved else { return false }
        if s.isDefault(v) { defaults.removeObject(forKey: "launcher." + s.env); return false }
        defaults.set(v, forKey: "launcher." + s.env); return true
    }

    // The default value, without writing (the menu's Reset shows it, and its live path applies it)
    func defaultValue(_ s: Setting) -> String { s.def }

    // A range's label: its percentage, with the size in pixels for the chosen console mode when the list has the base size (the
    // render scale). `opmode` is the operation mode to size for ("0" handheld, anything else docked)
    static func rangeLabel(_ s: Setting, _ v: Double, opmode: String) -> String {
        let p = "\(Int((v * 100).rounded())) %"
        guard let b = s.base else { return p }
        let size = opmode == "0" ? b.handheld : b.docked
        guard size.count == 2 else { return p }
        return "\(Int((Double(size[0]) * v).rounded())) × \(Int((Double(size[1]) * v).rounded())) (\(p))"
    }
}

final class LauncherModel: ObservableObject {
    let settings: [Setting]
    let fixed: Set<String>      // set by an env file or by the launch environment: shown, not changed
    let fromLaunch: Set<String>   // of those, the ones the launch environment set (a front end's launch overrides, Xcode; DM_ENV_LAUNCH_KEYS from launcher.c or main.m)
    let store: SettingsStore   // the choices themselves (SettingsStore above; the in-game menu shares it), with its ignoreSaved
    @Published var values: [String: String] = [:]

    init(_ settings: [Setting], defaults: UserDefaults = .standard) {
        let store = SettingsStore(settings, defaults: defaults)
        self.store = store
        self.settings = settings
        self.fromLaunch = store.fromLaunch
        self.fixed = store.fixed
        if store.ignoreSaved { fputs("launcher: saved choices ignored (DM_SAVED_CHOICES=0)\n", stderr) }
        for s in settings { values[s.env] = store.current(s) }
    }

    // The catalogue's sections, in the list's order, with each row's "needs" applied (SettingsGrouping.visible): one grouping for the iOS
    // launcher, the Mac window and the in-game menu, so the three cannot draw the same list differently
    var groups: [SettingSection] { SettingsGrouping.sections(settings, values: values) }
    // The Mac window's Form (dm/mac/Launcher.swift): Basic settings first, then Advanced settings, each in the list's sections and order.
    // Two shapes of that Form, both over the one grouping above
    func sections(basic: Bool) -> [String] { SettingsGrouping.sections(settings, values: values, basic: basic).map(\.title) }
    func rows(in section: String, basic: Bool) -> [Setting] {
        SettingsGrouping.sections(settings, values: values, basic: basic).first { $0.title == section }?.rows ?? []
    }
    // A range's label: its percentage, with the size in pixels for the chosen console mode when the list has the base size (the render scale)
    func rangeLabel(_ s: Setting, _ v: Double) -> String {
        SettingsStore.rangeLabel(s, v, opmode: values["DM_OPMODE"] ?? "1")   // the screen's console-mode row, which may not be applied yet
    }
    var changed: Bool { settings.contains { !fixed.contains($0.env) && !$0.isDefault(values[$0.env] ?? $0.def) } }

    // Reset every launcher choice to the game's defaults on the screen; values fixed by an env file or at launch stay. The saved choices are forgotten when Play applies
    // the defaults (apply() keeps no default), so Quit after Reset keeps them, and a choice a launch override hides is kept
    func reset() {
        for s in settings where !fixed.contains(s.env) { values[s.env] = s.def }
        fputs("launcher: settings reset to the game's defaults\n", stderr)
    }

    // Before the game starts: every setting not set by an env file goes into the environment (DM_LANG replaces the packed language main.m set as a default). Only a choice that
    // differs from the game's default is stored: a setting the player left at its default follows the defaults of a later build (the settings it was tested with)
    func apply() {
        for s in settings {
            let v = values[s.env] ?? s.def
            if store.fixed.contains(s.env) { fputs("launcher: \(s.env) kept at \(v) (\(store.fromLaunch.contains(s.env) ? "launch environment" : "env file"))\n", stderr); continue }
            store.store(s, v)   // launcher.<VAR>: the default removes the key, a choice writes it; DM_SAVED_CHOICES=0 writes nothing
            setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v)\(s.isDefault(v) ? "" : " (changed)")\n", stderr)
        }
    }

    // DM_LAUNCHER=0: no screen, but the saved choices still apply (only DM_SAVED_CHOICES=0 ignores them); nothing is stored. Every row
    // is exported, defaults included, exactly as Play does: a catalogue default can depend on the build (Picture fill is Stretch in a
    // Duo build, settings.tsv build:DM_DUO) while the host's own default for an unset switch is the generic one, so leaving a default
    // out of the environment showed a Duo build letterboxed when the launcher was skipped (2026-10-30)
    func applySaved() {
        for s in settings where !fixed.contains(s.env) {
            let v = values[s.env] ?? s.def
            setenv(s.env, v, 1)
            if !s.isDefault(v) { fputs("launcher: \(s.env)=\(v) (saved choice)\n", stderr) }
        }
    }
}
