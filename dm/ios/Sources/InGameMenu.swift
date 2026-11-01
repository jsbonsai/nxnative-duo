// The in-game settings menu (duo/design/settings-ui.md; the overlay and the live rules: duo/design/ingamemenu-v2.md): one overlay over the
// running game, opened by the ⚙ button (DmGamepad.m) or a controller's Home button, over the game's picture so a frame-rate or render-scale
// change is seen happening.
//
// There is no list of rows here. The menu draws the app's dm/launcher.json — every row the launcher before the game shows, in the same
// sections and the same order (SettingsGrouping, LauncherSettings.swift), from the same SettingsStore and the same `launcher.<VAR>` key — so a
// choice made here is the choice the next start reads, and a choice made there is what this menu shows. A row the catalogue does not have is
// not drawn; a row it has is drawn once, under its catalogue section.
//
// Honesty is the point: a row is labelled "Applies now" only when dm_setting_live_state says this build can change it while the game runs
// (settings_live.m), and "Next start" otherwise. Nothing is written into the environment here (ingamemenu-v2.md §3.4): persistence goes
// through the store, the run-time change through the setter that owns the state.
import SwiftUI
import UIKit
import QuartzCore
import PhotosUI
import UniformTypeIdentifiers

final class InGameMenuModel: ObservableObject {
    /// Made once for the process, from the bundle's dm/launcher.json — the file dm_show_launcher decodes too. nil in an app built without
    /// settings (no launcher.json): the menu then does not open, and the ⚙ button does nothing. Kept across open / close, so a value that
    /// waits for the next start is still shown after the menu is reopened, also under DM_SAVED_CHOICES=0
    static let shared: InGameMenuModel? = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("dm/launcher.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(SettingsFile.self, from: data), !file.settings.isEmpty else { return nil }
        return InGameMenuModel(file.settings)
    }()

    let store: SettingsStore
    let catalog: [Setting]      // dm/launcher.json's rows, in the catalogue's order: this screen has no other list
    private let byEnv: [String: Setting]
    @Published private(set) var values: [String: String] = [:]   // what each row shows: the value in force for this run
    @Published private(set) var pending: Set<String> = []        // rows whose value waits for the next start
    @Published private(set) var note: [String: String] = [:]     // what the last change on a row did, said in the row
    @Published var query = ""                                    // the search field; a section with no match is not drawn
    @Published private(set) var editing = false                  // Control positions: Move (true) / Play (false)
    @Published private(set) var opacity = 1.0                    // Controls opacity: the current orientation class's (DmGamepad.m)
    @Published private(set) var background = false              // a background image is set (front_ios.m)
    @Published private(set) var dim = 0.3                        // its dimming

    enum Applied { case live, nextStart, refused }

    private init(_ settings: [Setting]) {
        store = SettingsStore(settings)
        catalog = settings
        byEnv = Dictionary(settings.map { ($0.env, $0) }, uniquingKeysWith: { a, _ in a })
        for s in settings { values[s.env] = store.applied(s) }   // Play wrote the environment: that is what the game runs with
        refresh()
    }

    // MARK: reading

    func setting(_ env: String) -> Setting? { byEnv[env] }
    func value(_ s: Setting) -> String { values[s.env] ?? s.def }
    func fixed(_ s: Setting) -> Bool { store.fixed.contains(s.env) }
    func fixedNote(_ s: Setting) -> String { store.fromLaunch.contains(s.env) ? "Set at launch" : "Set by an env file" }
    // 1 = this build can change the row while the game runs (settings_live.m answers without a change)
    func live(_ s: Setting) -> Bool { dm_setting_live_state(s.env) != 0 }
    func rangeLabel(_ s: Setting, _ v: Double) -> String {
        SettingsStore.rangeLabel(s, v, opmode: values["DM_OPMODE"] ?? "1")   // the console-mode row's value in force
    }

    /// The rows this menu draws, grouped exactly as the launcher groups them: the catalogue's sections in its order, each row's `needs`
    /// applied to the values in force here, and the search filter (a row's name, its description, its switch or its heading). A section with
    /// no row left is not drawn, so a row appears once and only once
    var sections: [SettingSection] { SettingsGrouping.sections(catalog, values: values, matching: query) }
    var shown: Int { sections.reduce(0) { $0 + $1.rows.count } }
    var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func changed(_ section: String) -> Bool {
        catalog.contains { $0.sectionTitle == section && !fixed($0) && !$0.isDefault(value($0)) }
    }
    var changed: Bool { catalog.contains { !fixed($0) && !$0.isDefault(value($0)) } }

    // MARK: changing

    /// Store one choice exactly as Play does, then run the live path for it. Nothing written to the environment. The row says what happened
    @discardableResult
    func commit(_ s: Setting, _ v: String) -> Applied {
        guard !fixed(s) else { note[s.env] = fixedNote(s); return .refused }
        let stored = store.store(s, v)              // persistence first, as Play does; a default removes the key
        values[s.env] = v
        if dm_setting_live(s.env, v) != 0 {         // the setter that owns the state; no setenv on this path
            pending.remove(s.env)
            note[s.env] = "Applied"
            return .live
        }
        if stored {
            pending.insert(s.env)
            note[s.env] = "Saved · takes effect at the next start"
        } else if s.isDefault(v) {
            pending.remove(s.env)
            note[s.env] = "The game's default · takes effect at the next start"
        } else {
            note[s.env] = "Not saved (DM_SAVED_CHOICES=0) · takes effect at the next start"
        }
        return .nextStart
    }

    /// Reset one heading: every row of that catalogue section back to its default, with the live path run for each live row — the launcher's
    /// own rule (§2.3), only over the rows on screen. A value an env file or the launch environment fixed stays
    func reset(_ section: String) {
        for s in catalog where s.sectionTitle == section && !fixed(s) { commit(s, store.defaultValue(s)) }
    }

    /// Reset to tested defaults: the same, for every row. The stored choices are forgotten — Reset means the same thing on both screens
    func resetAll() {
        for s in catalog where !fixed(s) { commit(s, store.defaultValue(s)) }
    }

    func setEditing(_ on: Bool) {
        guard dm_gamepad_set_editing(on ? 1 : 0) != 0 else { return }
        editing = on
    }
    func resetLayout() { _ = dm_gamepad_reset_layout() }
    func setOpacity(_ v: Double) {
        guard dm_gamepad_set_opacity(Float(v)) != 0 else { return }
        opacity = v
    }
    func setDim(_ v: Double) { dm_background_set_dim(Float(v)); dim = v }
    func removeBackground() { dm_background_remove(); background = false }
    /// The picked photo's bytes, off the main thread (decoding and downscaling take a moment); `done` gets whether it was taken, on the main thread
    func setBackground(_ data: Data?, done: @escaping (Bool) -> Void) {
        let ok = data.map { d in d.withUnsafeBytes { dm_background_set_image($0.baseAddress, $0.count) } != 0 } ?? false
        DispatchQueue.main.async {
            if ok { self.background = true }
            done(ok)
        }
    }

    /// Called each time the menu opens: the pad's edit mode is a session toggle that survives closing the menu; the opacity is the
    /// orientation class's the screen is in now
    func refresh() {
        editing = dm_gamepad_editing() != 0
        opacity = Double(dm_gamepad_opacity())
        background = dm_background_present() != 0
        dim = Double(dm_background_dim())
    }
}

// MARK: - The overlay
//
// A quick menu, as in the emulators players know: the game and how it is running at the top, the things changed mid-game as big tiles
// (picture, pad, split, controls), every other catalogue row once below as a one-line row, Performance folded under Advanced. No row
// carries a paragraph: a row that waits for the next start shows ↻, and the section says once what ↻ means.

/// The rows the tiles own: drawn as tiles, left out of the list, so each setting appears once.
private let kTileRows: Set<String> = ["DM_PRESENT_FILL", "DM_DUAL_SCREEN", "DM_PAD_LAYOUT", "DM_PAD_HIDDEN"]
private let kAdvanced = "Performance"

private struct InGameMenuView: View {
    @ObservedObject var m: InGameMenuModel
    let done: () -> Void
    @State private var fps: Double = 0
    @State private var thermal: Int32 = 0           // dm_thermal_now: 0 nominal, 1 fair, 2 serious, 3 critical
    @State private var advanced = false
    @State private var confirmReset = false
    @State private var toast: String?
    @State private var picking = false             // the photo picker for the background is up

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea().onTapGesture(perform: done)    // the game stays visible; a tap outside resumes
                panel
                    .frame(width: min(geo.size.width - 24, 600), height: min(geo.size.height - 24, 640))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .preferredColorScheme(.dark)
        .onAppear { m.refresh(); thermal = dm_thermal_now() }
        .task { await sample() }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    tiles
                    ForEach(listSections) { section in
                        SectionBox(title: section.title, rows: section.rows, m: m, toast: $toast)
                    }
                    if let perf = advancedSection {
                        DisclosureGroup(isExpanded: $advanced) {
                            SectionBox(title: nil, rows: perf.rows, m: m, toast: $toast).padding(.top, 8)
                        } label: {
                            Text("Advanced").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .tint(.secondary)
                    }
                    Button(role: .destructive) { confirmReset = true } label: {
                        Text("Reset All Settings").font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                    .disabled(!m.changed)
                    .padding(.bottom, 6)
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
        .overlay(alignment: .top) { toastView }
        .confirmationDialog("Reset every setting to the game's tested defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset All", role: .destructive) { m.resetAll(); flash("Settings reset") }
        }
    }

    // The game, how it runs right now, and the way back to it
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(gameName).font(.title3.weight(.bold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(fps > 0 ? "\(Int(fps.rounded())) fps" : "– fps").monospacedDigit()
                    Circle().frame(width: 3, height: 3).foregroundStyle(.tertiary)
                    Text(thermalWord).foregroundStyle(thermal >= 2 ? Color.orange : Color.secondary)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: done) {
                Label("Resume", systemImage: "play.fill").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: tiles

    private var tiles: some View {
        VStack(spacing: 10) {
            if let fill = m.setting("DM_PRESENT_FILL") {
                Tile(icon: "aspectratio", title: "Picture") { Segments(s: fill, m: m, toast: $toast) }
            }
            HStack(spacing: 10) {
                if let split = m.setting("DM_DUAL_SCREEN") {
                    ToggleTile(s: split, m: m, icon: "rectangle.split.1x2", title: "Split screen", toast: $toast)
                }
                if let hidden = m.setting("DM_PAD_HIDDEN") {
                    ToggleTile(s: hidden, m: m, icon: "hand.tap", title: "Touch controls", invert: true, toast: $toast)
                }
            }
            if let layout = m.setting("DM_PAD_LAYOUT") {
                Tile(icon: "gamecontroller", title: "Pad layout") { Segments(s: layout, m: m, toast: $toast) }
            }
            HStack(spacing: 10) {
                ActionTile(icon: m.editing ? "checkmark.circle" : "arrow.up.and.down.and.arrow.left.and.right",
                           title: m.editing ? "Done Moving" : "Move Controls",
                           detail: m.editing ? "Layout saved" : "Drag · pinch to resize") {
                    m.setEditing(!m.editing)
                    if m.editing { done() }               // the pad is under the menu: close it so the player can drag (its Done pill ends it)
                }
                ActionTile(icon: "arrow.counterclockwise", title: "Reset Layout", detail: "This orientation") {
                    m.resetLayout(); flash("Layout reset for this orientation")
                }
            }
            Tile(icon: "circle.lefthalf.filled", title: "Controls opacity") {
                PercentSlider(label: "Controls opacity", value: Binding(get: { m.opacity }, set: { m.setOpacity($0) }), range: 0.1...1)
                Text("Saved for this orientation").font(.caption).foregroundStyle(.secondary)
            }
            Tile(icon: "photo", title: "Background") {
                HStack(spacing: 10) {
                    Button { picking = true } label: { Label("Choose Photo…", systemImage: "photo.on.rectangle") }
                    Button("Remove", role: .destructive) { m.removeBackground(); flash("Background removed") }
                        .disabled(!m.background)
                }
                .buttonStyle(.bordered).font(.subheadline)
                HStack(spacing: 10) {
                    Text("Dimming").font(.caption).foregroundStyle(.secondary)
                    PercentSlider(label: "Background dimming", value: Binding(get: { m.dim }, set: { m.setDim($0) }), range: 0...0.8)
                }
                .disabled(!m.background)
            }
        }
        .sheet(isPresented: $picking) {
            PhotoPicker(dismiss: { picking = false }) { data in
                m.setBackground(data) { ok in flash(ok ? "Background set" : "That photo could not be used") }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: list

    private var listSections: [SettingSection] {
        m.sections.compactMap { sec in
            guard sec.title != kAdvanced else { return nil }
            let rows = sec.rows.filter { !kTileRows.contains($0.env) }
            return rows.isEmpty ? nil : SettingSection(title: sec.title, rows: rows)
        }
    }
    private var advancedSection: SettingSection? { m.sections.first { $0.title == kAdvanced } }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Text(toast).font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .foregroundStyle(.white)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func flash(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { withAnimation(.easeIn(duration: 0.2)) { if toast == text { toast = nil } } }
    }

    private var gameName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Game"
    }

    private var thermalWord: String {
        switch thermal {
        case 0: return "Cool"
        case 1: return "Warm"
        case 2: return "Hot · 30 fps hold"
        default: return "Very hot · 30 fps hold"
        }
    }

    // The frames the host presented in the last second (nvn_mtl.m counts them for every graphics layer)
    private func sample() async {
        var last = mtl_present_count(), t = CACurrentMediaTime()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            let n = mtl_present_count(), now = CACurrentMediaTime()
            if now - t > 0.2 { fps = Double(n &- last) / (now - t) }   // a longer span is time in the background: no reading
            last = n; t = now
            thermal = dm_thermal_now()
        }
    }
}

/// What a change did, said once, briefly: nothing for a live change (the player sees it), "applies next start" otherwise
private func feedback(_ applied: InGameMenuModel.Applied, _ toast: Binding<String?>) {
    guard applied == .nextStart else { return }
    withAnimation(.easeOut(duration: 0.2)) { toast.wrappedValue = "Saved · applies the next time you start the game" }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
        withAnimation(.easeIn(duration: 0.2)) { toast.wrappedValue = nil }
    }
}

private struct Tile<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// A catalogue choice as a segmented control (Picture fill, Pad layout): its options in the catalogue's order
private struct Segments: View {
    let s: Setting
    @ObservedObject var m: InGameMenuModel
    @Binding var toast: String?
    var body: some View {
        Picker(s.label, selection: Binding(get: { m.value(s) }, set: { feedback(m.commit(s, $0), $toast) })) {
            ForEach(s.options ?? [], id: \.[0]) { Text($0[1]).tag($0[0]) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(m.fixed(s))
    }
}

/// A catalogue toggle as a tile the whole of which is the switch; `invert` for a row whose "on" means hidden (On-screen controls)
private struct ToggleTile: View {
    let s: Setting
    @ObservedObject var m: InGameMenuModel
    let icon: String
    let title: String
    var invert = false
    @Binding var toast: String?
    var body: some View {
        let on = (m.value(s) == s.onValue) != invert
        Button {
            let wantOn = !on
            feedback(m.commit(s, (wantOn != invert) ? s.onValue : s.offValue), $toast)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.subheadline.weight(.semibold))
                Text(on ? "On" : "Off").font(.caption.weight(.semibold)).foregroundStyle(on ? Color.white : .secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(on ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .disabled(m.fixed(s))
    }
}

private struct ActionTile: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

/// A 0…1 value as a slider with its percentage (Controls opacity, Background dimming); applied live while it moves
private struct PercentSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: 0.05).accessibilityLabel(label)
            Text("\(Int((value * 100).rounded()))%").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// The system photo picker (PHPickerViewController: out of process, so no photo-library permission). The chosen image's bytes go to
/// `picked` off the main thread; nil when it could not be read. Cancel picks nothing
private struct PhotoPicker: UIViewControllerRepresentable {
    let dismiss: () -> Void
    let picked: (Data?) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var c = PHPickerConfiguration()
        c.filter = .images
        c.selectionLimit = 1
        let p = PHPickerViewController(configuration: c)
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let item = results.first?.itemProvider, item.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return }
            let picked = parent.picked
            item.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in picked(data) }
        }
    }
}

/// One catalogue section as a grouped box of one-line rows; a ↻ marks a row the running game cannot change, explained once below
private struct SectionBox: View {
    let title: String?
    let rows: [Setting]
    @ObservedObject var m: InGameMenuModel
    @Binding var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                    if i > 0 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 14) }
                    MenuRow(s: s, m: m, toast: $toast)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.07)))
            if rows.contains(where: { !m.live($0) && !m.fixed($0) }) {
                Text("↻ applies the next time you start the game").font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)
            }
        }
    }
}

/// One line: the name (↻ when it waits for the next start, the reason when an env file holds it), the control on the right
private struct MenuRow: View {
    let s: Setting
    @ObservedObject var m: InGameMenuModel
    @Binding var toast: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(s.label).font(.subheadline)
                if m.fixed(s) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary)
                } else if !m.live(s) {
                    Text("↻").font(.caption).foregroundStyle(.tertiary)
                }
                if m.pending.contains(s.env) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
                Spacer(minLength: 8)
                trailing
            }
            if s.kind == "range" { MenuRangeControl(s: s, m: m, toast: $toast) }
        }
        .padding(.horizontal, 14).padding(.vertical, s.kind == "range" ? 10 : 8)
        .frame(minHeight: 44)
        .disabled(m.fixed(s))
    }

    @ViewBuilder private var trailing: some View {
        switch s.kind {
        case "choice":
            Picker(s.label, selection: Binding(get: { m.value(s) }, set: { feedback(m.commit(s, $0), $toast) })) {
                ForEach(s.options ?? [], id: \.[0]) { Text($0[1]).tag($0[0]) }
            }
            .pickerStyle(.menu).labelsHidden().tint(.secondary)
        case "range":
            Text(m.rangeLabel(s, Double(m.value(s)) ?? s.min ?? 1)).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
        default:
            Toggle(s.label, isOn: Binding(get: { m.value(s) == s.onValue },
                                          set: { feedback(m.commit(s, $0 ? s.onValue : s.offValue), $toast) }))
                .labelsHidden()
        }
    }
}

private struct MenuRangeControl: View {
    let s: Setting
    @ObservedObject var m: InGameMenuModel
    @Binding var toast: String?
    @State private var draft: Double = 0

    var body: some View {
        Slider(value: $draft, in: (s.min ?? 0)...(s.max ?? 1), step: s.step ?? 0.05,
               onEditingChanged: { editing in if !editing { feedback(m.commit(s, String(format: "%.2f", draft)), $toast) } })
            .accessibilityLabel(s.label)
            .accessibilityValue(m.rangeLabel(s, draft))
            .onAppear { draft = Double(m.value(s)) ?? s.min ?? 1 }
            .onChange(of: m.value(s)) { _, v in draft = Double(v) ?? draft }
    }
}

/// The presented menu: the root controller's own orientation, status-bar and home-indicator preferences (front_ios.m), and the pad suspended
/// exactly as long as it is up — every touch released, no new one taken, controller reads forced to zero
private final class MenuHost: UIHostingController<InGameMenuView> {
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); dm_gamepad_suspend(1) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); dm_gamepad_suspend(0) }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
}

private weak var shownMenu: MenuHost?

private func menuClose() {
    guard let h = shownMenu else { return }
    shownMenu = nil
    h.dismiss(animated: false)
}

private func keyRoot() -> UIViewController? {
    for scene in UIApplication.shared.connectedScenes {
        guard let ws = scene as? UIWindowScene else { continue }
        for w in ws.windows where w.isKeyWindow { return w.rootViewController }
    }
    return nil
}

/// The ⚙ button and a controller's Home: open the menu, or close it when it is already up. 0 when this app has no dm/launcher.json
/// (Launcher.swift dm_show_launcher's own precondition), so the button does nothing rather than showing an empty menu. Int32, not Bool: the
/// C side declares it `int` (DmGamepad.m), as it declares dm_setting_commit
@_cdecl("dm_ingame_menu_present")
public func dmIngameMenuPresent() -> Int32 {
    if shownMenu != nil { menuClose(); return 1 }
    guard let model = InGameMenuModel.shared, let root = keyRoot() else { return 0 }
    var host = root
    while let over = host.presentedViewController { host = over }
    let vc = MenuHost(rootView: InGameMenuView(m: model, done: menuClose))
    vc.modalPresentationStyle = .overFullScreen      // the game keeps drawing behind the scrim
    vc.modalTransitionStyle = .crossDissolve
    vc.modalPresentationCapturesStatusBarAppearance = true
    vc.overrideUserInterfaceStyle = .dark
    vc.view.backgroundColor = .clear
    shownMenu = vc
    dm_gamepad_suspend(1)                            // before the first frame of the overlay: nothing drives the game behind it
    host.present(vc, animated: true)
    fputs("front end: in-game settings menu opened\n", stderr)
    return 1
}

/// One choice from the layout pill (DmGamepad.m -nextLayout), through the same store and the same live path the menu uses, so the pill and
/// the menu never disagree and there is one place a choice is written. 0 when this app has no store: the pill then switches on its own
@_cdecl("dm_setting_commit")
public func dmSettingCommit(_ env: UnsafePointer<CChar>, _ value: UnsafePointer<CChar>) -> Int32 {
    guard let m = InGameMenuModel.shared, let s = m.setting(String(cString: env)) else { return 0 }
    m.commit(s, String(cString: value))
    return 1
}
