import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Top bar (§5)

struct TopBar: View {
    @EnvironmentObject private var m: AppModel
    var showsBack: Bool = false
    var showsGear: Bool = true
    var showsDevicePill: Bool = true

    var body: some View {
        HStack(spacing: DuoSpace.s) {
            if showsBack {
                Button {
                    m.clear()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text(Copy.backLibrary).font(DuoFont.bodyBold)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .overlay(Capsule().strokeBorder(DuoColor.panelStroke))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if showsDevicePill { DevicePill() }
            if showsGear {
                Button {
                    m.openSetup()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                        .overlay(Circle().strokeBorder(DuoColor.panelStroke))
                }
                .buttonStyle(.plain)
                .help(Copy.menuSetup)
                .accessibilityLabel(Copy.menuSetup)
            }
        }
        .padding(.leading, showsBack ? 86 : DuoSpace.page)
        .padding(.trailing, DuoSpace.page)
        .frame(height: DuoSpace.topBand)
    }
}

struct DevicePill: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore

    var body: some View {
        Menu {
            ForEach(phones.devices) { d in
                Button {
                    phones.choose(d)
                } label: {
                    if d.udid == phones.knownDevice?.udid {
                        Label(label(d), systemImage: "checkmark")
                    } else {
                        Text(label(d))
                    }
                }
                .disabled(!d.connected)
            }
            if phones.devices.isEmpty {
                Text(Copy.deviceNone).disabled(true)
            }
            Divider()
            Button(Copy.deviceMenuOnThisPhone) {
                m.showRenew = true
                installs.refresh(root: m.root)
            }
            .disabled(!installs.available || phones.knownDevice == nil)
            Button(Copy.deviceMenuNewPhone) {
                m.openSetup(target: "device")
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill((phones.knownDevice?.connected ?? false) ? DuoColor.ready : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(phones.knownDevice?.name ?? Copy.deviceNone)
                    .font(DuoFont.bodyBold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .overlay(Capsule().strokeBorder(DuoColor.panelStroke))
            .contentShape(Capsule())
        }
        .menuIndicator(.hidden)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(phones.knownDevice?.name ?? Copy.deviceNone)
    }

    private func label(_ d: Device) -> String {
        d.connected ? d.name : Copy.deviceDisconnected(d.name)
    }
}

// MARK: - Status strip (§5)

struct StatusStrip: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var setup: SetupStore

    var body: some View {
        HStack(spacing: 8) {
            status
            Spacer(minLength: 8)
            Button(Copy.statusSetupLink) { m.openSetup() }
                .buttonStyle(.link)
                .font(DuoFont.body)
        }
        .font(DuoFont.body)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(height: DuoSpace.statusStrip)
        .background(DuoColor.statusStrip)
        .overlay(Rectangle().fill(DuoColor.hairline).frame(height: 1), alignment: .top)
    }

    @ViewBuilder private var status: some View {
        if setup.checking && setup.doctor == nil {
            ProgressView().controlSize(.small)
            Text(Copy.statusChecking)
        } else if let d = setup.doctor, !d.ready {
            Circle().fill(DuoColor.warn).frame(width: 8, height: 8)
            if m.library.entries.isEmpty {
                Text(Copy.statusTodo(d.missing.count) + " · " + Copy.statusNotAffiliated)
            } else {
                Text(Copy.statusTodo(d.missing.count))
            }
        } else if let d = setup.doctor {
            Circle().fill(DuoColor.ready).frame(width: 8, height: 8)
            Text(Copy.statusReady)
            if let gb = freeGB(d) {
                Text(Copy.statusFree(gb))
            }
        } else {
            Circle().fill(DuoColor.error).frame(width: 8, height: 8)
            Text(m.root == nil ? "Project folder not found" : "Could not check this Mac")
        }
    }

    /// The doctor's own free-space value: "41 GB free" (or "only 2.1 GB free: …").
    private func freeGB(_ doctor: Doctor) -> String? {
        guard let detail = doctor.items.first(where: { $0.id == "space" })?.detail else { return nil }
        let pattern = #"([0-9]+(?:\.[0-9]+)?) GB free"#
        guard let range = detail.range(of: pattern, options: .regularExpression) else { return nil }
        return String(detail[range].split(separator: " ").first ?? "")
    }
}

// MARK: - Banner

struct Banner: View {
    var image: Image?
    var size: CGFloat
    var corner: CGFloat
    var tag: String?
    var shadow: Bool

    init(path: String?, size: CGFloat, corner: CGFloat? = nil, tag: String? = nil, shadow: Bool? = nil) {
        if let path, let ns = NSImage(contentsOfFile: path) {
            image = Image(nsImage: ns)
        } else {
            image = nil
        }
        self.size = size
        self.corner = corner ?? (size >= 120 ? DuoRadius.banner : max(8, size * 0.16))
        self.tag = tag
        self.shadow = shadow ?? (size >= 160)
    }

    init(image: Image?, size: CGFloat, corner: CGFloat? = nil, tag: String? = nil, shadow: Bool? = nil) {
        self.image = image
        self.size = size
        self.corner = corner ?? (size >= 120 ? DuoRadius.banner : max(8, size * 0.16))
        self.tag = tag
        self.shadow = shadow ?? (size >= 160)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let image {
                    image.resizable().interpolation(.high)
                } else {
                    ZStack {
                        LinearGradient(colors: [.red.opacity(0.8), .pink.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: size * 0.32))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(.duo(corner))

            if let tag {
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .padding(8)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: shadow ? .black.opacity(0.45) : .clear,
                radius: shadow ? 30 : 0, y: shadow ? 12 : 0)
        .accessibilityHidden(true)
    }
}

// MARK: - Library tiles (§5, §6.02)

struct LibraryTile: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var phones: DeviceStore
    let entry: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            Banner(image: entry.banner, size: DuoSpace.libraryArt, corner: DuoRadius.tile,
                   tag: entry.platform == .ps2 ? Copy.tilePS2 : nil)
            Text(entry.title)
                .font(DuoFont.section)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(statusText)
                .font(DuoFont.caption)
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { m.open(entry) }
        .contextMenu {
            Button(Copy.menuInstall(phones.device?.name ?? "iPhone")) { m.installFromLibrary(entry) }
            Button(Copy.menuOpenCard) { m.open(entry) }
            Button(Copy.menuShowInFinder) {
                let urls = entry.files.compactMap { $0.url() }.filter { FileManager.default.fileExists(atPath: $0.path) }
                if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            }
            Button(Copy.menuRemoveFromLibrary) { m.library.remove(entry.id) }
            if entry.cacheKey != nil {
                Button(Copy.menuDeletePrepared) { m.deletePreparedGraphics(entry) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var statusText: String {
        if m.isOnPhone(entry.title), let name = phones.device?.name { return Copy.tileOnPhone(name) }
        if entry.isPrepared { return Copy.tileReady }
        // The reference shelf says "Not built yet" for a game whose profile is still provisional; the tile's
        // four states in §5 do not include "May not start". That sentence belongs to the card's support badge.
        switch entry.support.display {
        case .new: return Copy.tileNew
        default: return Copy.tileNotBuilt
        }
    }

    private var statusColor: Color {
        if m.isOnPhone(entry.title) { return .secondary }
        if entry.isPrepared { return DuoColor.readyText }
        return .secondary
    }
}

/// §5: same size as a tile, dashed accent border, accent tint 8%, + and "Add Game…"; first item in the grid.
struct AddGameTile: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            ZStack {
                RoundedRectangle.duo(DuoRadius.tile)
                    .fill(Color.accentColor.opacity(hovering ? 0.14 : 0.08))
                RoundedRectangle.duo(DuoRadius.tile)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 26, weight: .regular))
                    Text(Copy.tileAdd).font(DuoFont.bodyBold)
                }
                .foregroundStyle(Color.accentColor)
            }
            .frame(width: DuoSpace.libraryArt, height: DuoSpace.libraryArt)
            .onTapGesture(perform: action)
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Copy.tileAdd)
            .accessibilityAddTraits(.isButton)

            Text(Copy.tileAddHint)
                .font(DuoFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: DuoSpace.libraryArt, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Picture row (§6.06, §6.07, §6.08)

struct PictureRow: View {
    let info: GameInfo
    let platform: Platform
    let duoAvailable: Bool
    @Binding var duoOn: Bool
    let onAddPack: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DuoSpace.s) {
            Image(systemName: duoOn && available ? "rectangle.inset.filled" : "rectangle.center.inset.filled")
                .font(.system(size: 20))
                .foregroundStyle(duoOn && available ? DuoColor.readyText : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                if available && duoAvailable {
                    HStack(spacing: 4) {
                        Text(Copy.pictureDuoTitle).font(DuoFont.bodyBold)
                        Spacer(minLength: 8)
                        Toggle("", isOn: $duoOn).labelsHidden().toggleStyle(.switch)
                    }
                    Text(duoOn ? duoSentence : Copy.pictureOriginalBody)
                        .font(DuoFont.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if available {
                    Text(Copy.pictureOriginalTitle).font(DuoFont.bodyBold)
                    Text(Copy.pictureNotDuo)
                        .font(DuoFont.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .top, spacing: DuoSpace.s) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Copy.pictureOriginalTitle).font(DuoFont.bodyBold)
                            Text(platform == .ps2 ? Copy.pictureOriginalBody : Copy.pictureNoPack)
                                .font(DuoFont.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if platform != .ps2 {
                            Button(Copy.pictureAddPack, action: onAddPack)
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoPanel(DuoRadius.panel)
    }

    private var available: Bool { info.duo.state == "available" }

    private var duoSentence: String {
        Copy.pictureDuoBody(pack: info.duo.name ?? "",
                            author: info.duo.author ?? "an unknown author",
                            note: info.duo.note)
    }
}

// MARK: - What happens next (§5, §6.06)

struct NextStepsStrip: View {
    struct Step: Identifiable {
        var id = UUID()
        var title: String
        var detail: String?
    }
    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            SectionLabel(text: Copy.nextLabel)
            HStack(spacing: DuoSpace.s) {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(DuoFont.bodyBold)
                        if let detail = step.detail {
                            Text(detail).font(DuoFont.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                    .padding(12)
                    .overlay(RoundedRectangle.duo(DuoRadius.panel).strokeBorder(DuoColor.hairline))
                }
            }
        }
    }
}

// MARK: - Stage timeline (§5)

struct StageTimeline: View {
    let stages: [TimelineStage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        marker(stage.status)
                        if index < stages.count - 1 {
                            Rectangle()
                                .fill(connector(stage.status))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 22)
                    content(stage).padding(.bottom, isActive(stage) ? 16 : 10)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(stage))
            }
        }
    }

    /// §11: the timeline reads each stage with its status.
    private func spoken(_ stage: TimelineStage) -> String {
        let status: String
        switch stage.status {
        case .done(let elapsed): status = "done, \(Copy.stageElapsed(elapsed))"
        case .active: status = "in progress"
        case .pending: status = "not started"
        }
        return "\(stage.title), \(status)"
    }

    private func isActive(_ s: TimelineStage) -> Bool { if case .active = s.status { return true }; return false }

    @ViewBuilder private func marker(_ status: TimelineStage.Status) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.black, DuoColor.ready)
        case .active:
            Circle().strokeBorder(Color.accentColor, lineWidth: 3).frame(width: 20, height: 20)
        case .pending:
            Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 2)
                .frame(width: 12, height: 12)
                .padding(4)
        }
    }

    private func connector(_ status: TimelineStage.Status) -> Color {
        if case .done = status { return DuoColor.ready.opacity(0.9) }
        return Color.primary.opacity(0.14)
    }

    @ViewBuilder private func content(_ s: TimelineStage) -> some View {
        switch s.status {
        case .done(let elapsed):
            HStack {
                Text(s.title)
                Spacer(minLength: 8)
                Text(Copy.stageElapsed(elapsed))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(DuoFont.body)
        case .pending:
            HStack(spacing: 4) {
                Text(s.title)
                if let hint = s.hint { Text("· \(hint)").foregroundStyle(DuoColor.warnText) }
            }
            .font(DuoFont.body)
            .foregroundStyle(.secondary)
        case .active:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.title).font(DuoFont.stage)
                    Spacer(minLength: 8)
                    Text(s.eta.map { Copy.etaKnown($0) } ?? Copy.etaUnknown)
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let f = s.fraction, f > 0 {
                    LinearBar(fraction: f)
                }
                let line = [s.detail, s.hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !line.isEmpty {
                    Text(line)
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Details disclosure (§5)

struct DetailsDisclosure: View {
    let log: [String]
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(Copy.details).font(DuoFont.body)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Copy.details)

            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(log.isEmpty ? " " : log.joined(separator: "\n"))
                            .font(DuoFont.log)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .id("end")
                    }
                    .frame(height: 120)
                    .background(DuoColor.panel, in: .duo(10))
                    .overlay(RoundedRectangle.duo(10).strokeBorder(DuoColor.panelStroke))
                    .onChange(of: log.count) { _ in
                        proxy.scrollTo("end", anchor: .bottom)
                    }
                }
            }
        }
    }
}

/// A small square of game art: the cached banner when there is one, else the app's fallback gradient.
struct GameThumb: View {
    var image: Image?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        Group {
            if let image {
                image.resizable().interpolation(.high)
            } else {
                LinearGradient(colors: [.red.opacity(0.8), .pink.opacity(0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.duo(corner))
        .accessibilityHidden(true)
    }
}

// MARK: - Panels

struct RoomPanel: View {
    let title: String
    let needGB: String
    /// The phone's free space cannot be measured through devicectl; when it is unknown the panel shows the
    /// requirement alone, without a bar or a made-up number.
    var freeGB: String? = nil
    var usedBytes: Int64? = nil
    var thisGameBytes: Int64? = nil
    var freeBytes: Int64? = nil
    var short: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(DuoFont.bodyBold)
            if let freeGB {
                RoomBar(used: usedBytes, thisGame: thisGameBytes, free: freeBytes, short: short)
                Text(Copy.roomBody(need: needGB, free: freeGB)).font(DuoFont.body).foregroundStyle(.secondary)
            } else {
                Text(Copy.roomNeeds(needGB)).font(DuoFont.body).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoPanel(DuoRadius.panel)
    }
}

struct RoomBar: View {
    let used: Int64?
    let thisGame: Int64?
    let free: Int64?
    let short: Bool

    var body: some View {
        GeometryReader { geo in
            let total = Double(max((used ?? 0) + (thisGame ?? 0) + (free ?? 0), 1))
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: max(2, geo.size.width * Double(used ?? 0) / total))
                Rectangle()
                    .fill(short ? DuoColor.error : Color.accentColor)
                    .frame(width: max(thisGame == nil ? 0 : 4, geo.size.width * Double(thisGame ?? 0) / total))
                Rectangle().fill(Color.primary.opacity(0.08))
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Collected file chips row

struct FileChips: View {
    let info: GameInfo
    let platform: Platform
    let missing: Bool
    var biosPresent: Bool = false
    var biosRequired: Bool = false
    let onAddUpdate: () -> Void
    let onLocate: () -> Void
    var onChooseBIOS: () -> Void = {}

    var body: some View {
        if missing {
            HStack(spacing: DuoSpace.xs) {
                FileChip(kind: .add, text: Copy.locateChip, onTap: onLocate)
            }
        } else {
            HStack(spacing: DuoSpace.xs) {
                if let b = info.base {
                    FileChip(kind: .ok, text: platform == .ps2 ? Copy.chipDisc : Copy.chipGame(b.displayVersion ?? b.name ?? ""))
                }
                if let u = info.update {
                    FileChip(kind: .ok, text: Copy.chipUpdate(u.displayVersion ?? u.name ?? ""))
                } else if platform != .ps2 {
                    FileChip(kind: .add, text: Copy.chipAddUpdate, onTap: onAddUpdate)
                }
                if platform == .ps2 {
                    if biosPresent {
                        FileChip(kind: .ok, text: Copy.chipBios)
                    } else if biosRequired {
                        FileChip(kind: .fix, text: Copy.chipBiosMissing, onTap: onChooseBIOS)
                    }
                }
                if !info.dlc.isEmpty {
                    FileChip(kind: .ok, text: Copy.chipDLC(info.dlc.count))
                }
            }
        }
    }
}

// MARK: - Toast

struct Toast: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DuoFont.bodyBold)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(DuoColor.sheet, in: Capsule())
            .overlay(Capsule().strokeBorder(DuoColor.panelStroke))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .transition(.opacity)
    }
}

// MARK: - Drop overlay (§6.03, §8)

enum DropKinds {
    enum Kind { case game, gameOrUpdate, unsupported }

    static func kind(_ url: URL) -> Kind {
        switch url.pathExtension.lowercased() {
        case "xci": return .game
        case "nsp": return .gameOrUpdate
        case "iso": return .game
        default: return .unsupported
        }
    }

    static func label(_ kind: Kind) -> String {
        switch kind {
        case .game: return Copy.dropKindGame
        case .gameOrUpdate: return Copy.dropKindGameOrUpdate
        case .unsupported: return Copy.dropKindUnsupported
        }
    }

    static func supported(_ urls: [URL]) -> [URL] {
        urls.filter { if case .unsupported = kind($0) { return false }; return true }
    }
}

struct DropOverlay: View {
    let urls: [URL]
    let busyGame: String?

    private var supported: [URL] { DropKinds.supported(urls) }
    private var allUnsupported: Bool { supported.isEmpty }

    var body: some View {
        ZStack {
            RoundedRectangle.duo(22)
                .fill((busyGame != nil || allUnsupported ? DuoColor.warn : Color.accentColor).opacity(0.12))
            RoundedRectangle.duo(22)
                .strokeBorder(busyGame != nil || allUnsupported ? DuoColor.warn : Color.accentColor,
                              style: StrokeStyle(lineWidth: 2, dash: [9, 7]))

            if busyGame != nil || !urls.isEmpty {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle.duo(10)
                        .fill(busyGame != nil || allUnsupported ? DuoColor.warn : Color.accentColor)
                        .frame(width: 40, height: 40)
                    Image(systemName: busyGame != nil ? "hourglass" : (allUnsupported ? "xmark" : "arrow.down"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                if busyGame == nil, !allUnsupported {
                    Text(Copy.dropSubtitle).font(DuoFont.body).foregroundStyle(.secondary)
                }
                if busyGame == nil {
                    VStack(spacing: 6) {
                        ForEach(urls, id: \.absoluteString) { url in
                            row(url)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(18)
            .frame(width: 380)
            .background(DuoColor.sheet, in: .duo(18))
            .overlay(RoundedRectangle.duo(18).strokeBorder(DuoColor.panelStroke))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
            }
        }
        .padding(16)
    }

    private var title: String {
        if let busyGame { return Copy.dropBusy(busyGame) }
        if allUnsupported { return Copy.dropNoneTitle }
        return Copy.dropTitle(supported.count)
    }

    private func row(_ url: URL) -> some View {
        let kind = DropKinds.kind(url)
        let supported = kind != .unsupported
        return HStack(spacing: 8) {
            Image(systemName: supported ? "checkmark" : "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(supported ? DuoColor.readyText : DuoColor.warnText)
            Text(url.lastPathComponent)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(DropKinds.label(kind))
                .font(DuoFont.caption)
                .foregroundStyle(supported ? Color.secondary : DuoColor.warnText)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: .duo(8))
        .overlay(RoundedRectangle.duo(8).strokeBorder(
            supported ? Color.clear : DuoColor.warn.opacity(0.5),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
