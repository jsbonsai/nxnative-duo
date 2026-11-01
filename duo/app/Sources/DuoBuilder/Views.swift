import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

struct RootView: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var setup: SetupStore
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Group {
                    switch m.phase {
                    case .home: HomeView()
                    case .reading(let progress): ReadingView(progress: progress)
                    case .card: CardView()
                    case .working: WorkingView()
                    case .failed(let failure): FailedView(failure: failure)
                    case .done(let info): DoneView(info: info)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(phaseKind)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
                .opacity(m.dropTargeted ? 0.25 : 1)
                .overlay {
                    if m.dropTargeted {
                        DropOverlay(urls: m.hoverURLs,
                                    busyGame: isWorking ? (m.run?.gameName ?? m.title) : nil)
                            .padding(.top, isHome || m.phase == .card || m.isReadingPhase ? 52 : 44)
                    }
                }

                if isHome { StatusStrip() }
            }
            .background(DuoColor.window)
            .onDrop(of: [.fileURL], isTargeted: $m.dropTargeted) { providers in
                Drop.urls(providers) { m.acceptDrop($0) }
                return true
            }
            .task(id: m.dropTargeted) {
                guard m.dropTargeted else { m.hoverURLs = []; return }
                // The drag pasteboard is readable while files are over the window; §6.03 names them during hover.
                while !Task.isCancelled && m.dropTargeted {
                    m.readDragPasteboard()
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
                m.hoverURLs = []
            }
            if let toast = m.toast {
                Toast(text: toast)
                    .padding(.bottom, isHome ? 54 : 20)
            }
        }
        .frame(width: 720, height: 560)
        .animation(reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.18), value: phaseKind)
        .animation(.easeOut(duration: 0.15), value: m.dropTargeted)
        .sheet(isPresented: $m.showSetup, onDismiss: { m.afterSetupIfPending() }) {
            SetupSheet().environmentObject(m).environmentObject(setup).environmentObject(phones)
                .environmentObject(installs).environmentObject(library).environmentObject(settings)
        }
        .sheet(isPresented: $m.showRenew) {
            RenewSheet().environmentObject(m).environmentObject(setup).environmentObject(phones)
                .environmentObject(installs).environmentObject(library).environmentObject(settings)
        }
        .alert(isPresented: Binding(get: { m.cancelPrompt }, set: { if !$0 { m.dismissCancelPrompt() } })) {
            Alert(title: Text(Copy.cancelConfirmTitle),
                  message: Text(Copy.cancelConfirmBody),
                  primaryButton: .destructive(Text("Stop")) { m.cancel() },
                  secondaryButton: .cancel(Text(Copy.commonCancel)) { m.dismissCancelPrompt() })
        }
    }

    private var isHome: Bool { if case .home = m.phase { return true }; return false }
    private var isWorking: Bool { if case .working = m.phase { return true }; return false }

    private var phaseKind: Int {
        switch m.phase {
        case .home: return 0
        case .reading: return 1
        case .card: return 2
        case .working: return 3
        case .failed: return 4
        case .done: return 5
        }
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

// MARK: - Home (01, 02, 05)

struct HomeView: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var setup: SetupStore
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            if isFirstRun {
                firstRunView
            } else {
                shelf
            }
            if let notice = m.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(DuoFont.caption)
                    .foregroundStyle(DuoColor.warnText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DuoSpace.page)
                    .padding(.bottom, DuoSpace.xs)
            }
        }
    }

    /// "Library empty and no installs" (§6.01). Without installs data the library is the only signal there is.
    private var isFirstRun: Bool {
        guard library.entries.isEmpty else { return false }
        guard installs.available else { return true }
        return (m.selectedInstalls?.apps.isEmpty ?? true)
    }

    // MARK: First run

    private var firstRunView: some View {
        VStack(alignment: .leading, spacing: 0) {
            slotsPlaceholder
                .padding(.horizontal, DuoSpace.page)
                .padding(.top, 2)
                .padding(.bottom, 44)
            HStack(alignment: .top, spacing: 24) {
                Spacer().frame(width: 2)
                dropArea
                welcome
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DuoSpace.page)
            .padding(.top, DuoSpace.xs)
            Spacer(minLength: 0)
        }
    }

    private var slotsPlaceholder: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.homeSlotsTitle).font(DuoFont.section)
                Spacer()
                Text(Copy.homeSlotsFirstRun)
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: DuoSpace.s) {
                ForEach(1...3, id: \.self) { i in
                    SlotCard(title: nil, art: nil, state: .placeholder(i), accessibilityLabel: Copy.slotPlaceholder(i))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle.duo(DuoRadius.banner)
                .fill(Color.accentColor.opacity(m.dropTargeted ? 0.14 : 0.06))
            RoundedRectangle.duo(DuoRadius.banner)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
            VStack(spacing: 8) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(Copy.firstRunDrop)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                Text(Copy.firstRunTypes)
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 230, height: 230)
        .contentShape(RoundedRectangle.duo(DuoRadius.banner))
        .onTapGesture { m.choosePackages() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.firstRunTitle)
                .font(DuoFont.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(Copy.firstRunBody)
                .font(DuoFont.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                stepBadge(ready: m.ready, readyIcon: true, number: 1)
                stepBadge(ready: false, readyIcon: false, number: 2)
                stepBadge(ready: false, readyIcon: false, number: 3)
            }
            .padding(.top, 4)
            if !m.ready {
                Button {
                    m.openSetup()
                } label: {
                    Text(Copy.firstRunCTA)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle(tall: true))
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: 370, alignment: .leading)
    }

    /// Step 1 reads "Set up this Mac — Duo Builder does most of it": the second half is the quiet half in the design.
    private func stepBadge(ready: Bool, readyIcon: Bool, number: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                if ready && readyIcon {
                    Circle().fill(DuoColor.ready)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else if number == 1 {
                    Circle().fill(DuoColor.warn)
                    Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().fill(Color.primary.opacity(0.06))
                    Circle().strokeBorder(Color.primary.opacity(0.18))
                    Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            switch number {
            case 1:
                HStack(spacing: 4) {
                    Text("Set up this Mac").font(DuoFont.body)
                    Text("— Duo Builder does most of it").font(DuoFont.body).foregroundStyle(.secondary)
                }
            case 2:
                Text(Copy.firstRunStep2).font(DuoFont.body)
            default:
                Text(Copy.firstRunStep3).font(DuoFont.body)
            }
        }
    }

    // MARK: Normal shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let phone = m.selectedInstalls, installs.available {
                slots(phone)
            }
            librarySection
        }
        .padding(.horizontal, DuoSpace.page)
        .padding(.top, 2)
    }

    private func slots(_ phone: PhoneInstalls) -> some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.homeSlotsTitle).font(DuoFont.section)
                Spacer()
                Text(Copy.homeSlotsCount(phone.used))
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: DuoSpace.s) {
                ForEach(phone.apps) { app in
                    slotCard(app, phone: phone)
                }
                if phone.freeSlots > 0 {
                    SlotCard(title: nil, art: nil, state: .free,
                             highlighted: m.dropTargeted,
                             accessibilityLabel: Copy.slotFreeTitle)
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<max(0, phone.freeSlots - 1), id: \.self) { i in
                    SlotCard(title: nil, art: nil, state: .free,
                             accessibilityLabel: "\(Copy.slotFreeTitle) \(i + 2)")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func slotCard(_ app: InstalledApp, phone: PhoneInstalls) -> some View {
        let art = library.entries.first(where: { $0.title == app.title })?.banner
        let state: SlotCard.State
        let status: String
        if app.isExpired {
            state = .expiring(Copy.slotExpired)
            status = Copy.slotExpired
        } else if app.isExpiring {
            state = .expiring(Copy.slotExpiresTomorrow)
            status = Copy.slotExpiresTomorrow
        } else {
            let days = app.daysLeft ?? 7
            state = .healthy(daysLeft: days)
            status = Copy.slotDaysLeft(days)
        }
        return SlotCard(title: app.title, art: art, state: state,
                        accessibilityLabel: "\(app.title), \(Copy.tileOnPhone(phone.deviceName)), \(status), \(Copy.slotRenew) button",
                        onRenew: { m.renew(app) },
                        onOpen: { m.showRenew = true })
            .frame(maxWidth: .infinity)
            .contextMenu {
                Button(Copy.slotRenew) { m.renew(app) }
                Button(Copy.menuShowInLibrary) { m.showInLibrary(title: app.title) }
            }
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.homeLibraryTitle).font(DuoFont.section)
                Spacer()
                Text(Copy.homeLibraryCount(games: library.entries.count, reinstall: library.reinstallCount))
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 80), spacing: 16), count: 5),
                          alignment: .leading, spacing: 18) {
                    AddGameTile { m.choosePackages() }
                    ForEach(library.sorted(onPhoneTitles: m.onPhoneTitles)) { entry in
                        LibraryTile(entry: entry)
                    }
                }
                .padding(.bottom, DuoSpace.xs)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Reading (04)

struct ReadingView: View {
    @EnvironmentObject private var m: AppModel
    let progress: ReadingProgress

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showsBack: true, showsGear: false, showsDevicePill: false)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    ZStack {
                        RoundedRectangle.duo(DuoRadius.banner).fill(Color.primary.opacity(0.06))
                        ProgressView().controlSize(.large)
                    }
                    .frame(width: 176, height: 176)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Copy.readingTitle).font(DuoFont.title)
                        Text(progress.fileName)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                        // No bar or count: `duo info` sends no progress stream, and the design forbids inventing one.
                        HStack(spacing: DuoSpace.xs) {
                            RoundedRectangle.duo(14).fill(Color.primary.opacity(0.06)).frame(width: 100, height: 28)
                            RoundedRectangle.duo(14).fill(Color.primary.opacity(0.06)).frame(width: 100, height: 28)
                        }
                    }
                    Spacer(minLength: 0)
                }
                RoundedRectangle.duo(DuoRadius.panel).fill(Color.primary.opacity(0.04)).frame(height: 64)
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle.duo(DuoRadius.panel)
                            .strokeBorder(DuoColor.hairline)
                            .frame(height: 58)
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .center) {
                    Text(Copy.readingFooter)
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 16)
                    Button(Copy.commonCancel) { m.cancel() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, DuoSpace.pageWide)
            .padding(.top, 10)
            .padding(.bottom, DuoSpace.pageWide)
        }
    }
}

// MARK: - Game card (06–09)

struct CardView: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var setup: SetupStore
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            TopBar(showsBack: true, showsGear: false)
            if let info = m.info {
                content(info)
            }
            if let notice = m.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(DuoFont.caption)
                    .foregroundStyle(DuoColor.warnText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DuoSpace.pageWide)
            }
        }
    }

    private func content(_ info: GameInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: DuoSpace.l) {
                Banner(path: info.game?.icon, size: 176,
                       tag: m.platform == .ps2 ? Copy.tilePS2 : nil)
                VStack(alignment: .leading, spacing: 7) {
                    Text(info.game?.name ?? "Unknown game")
                        .font(DuoFont.title)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(meta(info))
                        .font(DuoFont.body)
                        .foregroundStyle(.secondary)
                    SupportBadge(state: SupportStateDTO(info.support).display)
                        .padding(.top, 2)
                    FileChips(info: info, platform: m.platform, missing: m.filesMissing,
                              biosPresent: biosPresent, biosRequired: biosRequired,
                              onAddUpdate: { m.choosePackages() }, onLocate: { m.locate() },
                              onChooseBIOS: { m.openSetup(target: "ps2-bios") })
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }

            if let games = info.cartridge, games.count > 1 {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.fill").foregroundStyle(.secondary)
                    Text(Copy.cartLabel(games.count)).font(DuoFont.body)
                    Spacer(minLength: 8)
                    Picker("Game", selection: Binding(get: { info.titleId ?? games[0].title },
                                                     set: { m.pickCartridgeGame($0) })) {
                        ForEach(games) { Text($0.name ?? $0.title).tag($0.title) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .duoPanel(DuoRadius.panel)
            }

            if let room = roomData(info) {
                HStack(alignment: .top, spacing: DuoSpace.s) {
                    RoomPanel(title: Copy.roomTitle(m.phoneName), needGB: room.need)
                    PictureRow(info: info, platform: m.platform, duoAvailable: m.duoAvailable,
                               duoOn: $m.duoOn, onAddPack: { m.choosePack() })
                }
            } else {
                PictureRow(info: info, platform: m.platform, duoAvailable: m.duoAvailable,
                           duoOn: $m.duoOn, onAddPack: { m.choosePack() })
            }

            if cached(info) != nil {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill").foregroundStyle(DuoColor.readyText)
                    Text(Copy.cardCached).font(DuoFont.body)
                    Spacer(minLength: 8)
                    if let slot = slotUseText {
                        Text(slot).font(DuoFont.body).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .duoPanel(DuoRadius.panel)
            } else if info.problems.isEmpty {
                NextStepsStrip(steps: nextSteps(info))
            }

            Spacer(minLength: 0)

            PrimaryActionButton(title: primaryTitle, reason: primaryReason(info),
                                footnote: Copy.cardFooter) {
                m.install()
            }
        }
        .padding(.horizontal, DuoSpace.pageWide)
        .padding(.top, 10)
        .padding(.bottom, DuoSpace.pageWide)
    }

    private func meta(_ info: GameInfo) -> String {
        let size = info.game?.bytes.map { StageCopy.bytes(Double($0)) }
        if m.platform == .ps2 {
            return size.map { Copy.cardMetaPS2(size: $0) } ?? Copy.chipDisc
        }
        var parts: [String] = []
        if let p = info.game?.publisher, !p.isEmpty { parts.append(p) }
        if let v = info.game?.version, !v.isEmpty { parts.append("Version \(v)") }
        if let size { parts.append(size) }
        return parts.joined(separator: " · ")
    }

    private struct RoomData {
        var need: String
    }

    /// §6.08's room panel: `ps2.size_bytes` plus the copy's headroom (`PS2_COPY_HEADROOM`, 512 MB). The phone's
    /// free space is not measurable through devicectl, so the panel states the requirement and draws no bar.
    private func roomData(_ info: GameInfo) -> RoomData? {
        guard m.platform == .ps2, let bytes = info.ps2?.sizeBytes ?? info.game?.bytes, bytes > 0 else { return nil }
        let need = bytes + 512 * 1_048_576
        return RoomData(need: gigabytes(need))
    }

    private var biosPresent: Bool { !(settings.ps2BIOS ?? "").isEmpty }
    private var biosRequired: Bool { m.info?.ps2?.bios == "required" }

    private func gigabytes(_ bytes: Int64) -> String {
        bytes >= 1_073_741_824 ? String(format: "%.1f", Double(bytes) / 1_073_741_824)
                               : String(format: "%.0f", Double(bytes) / 1_048_576)
    }

    private func cached(_ info: GameInfo) -> String? {
        if let entry = library.entries.first(where: { $0.id == m.activeEntryID }), let key = entry.cacheKey { return key }
        return CacheProbe.key(for: info)
    }

    private var slotUseText: String? {
        guard let phone = m.selectedInstalls else { return nil }
        return phone.freeSlots <= 1 ? Copy.nextInstallLastSlot : Copy.nextInstallSlot
    }

    private func nextSteps(_ info: GameInfo) -> [NextStepsStrip.Step] {
        let install = NextStepsStrip.Step(title: Copy.nextInstall(m.phoneName), detail: slotUseText)
        if m.platform == .ps2 {
            let size = info.game?.bytes.map { StageCopy.bytes(Double($0)) }
            return [
                NextStepsStrip.Step(title: renumber(Copy.nextBuild, 1), detail: nil),
                NextStepsStrip.Step(title: renumber(Copy.nextInstall(m.phoneName), 2), detail: slotUseText),
                NextStepsStrip.Step(title: renumber(Copy.nextCopy, 3), detail: size.map { Copy.nextCopyBody($0) }),
            ]
        }
        return [
            NextStepsStrip.Step(title: Copy.nextPrepare,
                                detail: cached(info) != nil ? Copy.nextPrepareCached : Copy.nextPrepareTime),
            NextStepsStrip.Step(title: Copy.nextBuild, detail: nil),
            install,
        ]
    }

    /// A step number is the only part that changes when a PS2 game swaps the first two steps; the sentence is the
    /// deck's own (§6.08's order is the PS2 one; see DESIGN-QUESTIONS Q5).
    private func renumber(_ text: String, _ n: Int) -> String {
        guard let range = text.range(of: " · ") else { return text }
        return "\(n)\(text[range.lowerBound...])"
    }

    private var primaryTitle: String {
        m.ready ? Copy.cardInstall(m.phoneName) : Copy.cardSetupAndInstall
    }

    private func primaryReason(_ info: GameInfo) -> String? {
        if !info.problems.isEmpty {
            return info.problems.joined(separator: " ")
        }
            if m.ready && phones.device == nil {
            return Copy.cardReasonNoPhone
        }
        return nil
    }
}

// MARK: - Working (11–13)

struct WorkingView: View {
    @EnvironmentObject private var m: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let run = m.run {
                header(run)
                StageTimeline(stages: run.stages)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let copy = run.copy {
                    copyPanel(run, copy)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: DuoSpace.xs) {
                    if m.detailsExpanded {
                        DetailsDisclosure(log: run.log, expanded: $m.detailsExpanded)
                            .frame(maxWidth: .infinity)
                    }
                    HStack(alignment: .bottom) {
                        if !m.detailsExpanded {
                            DetailsDisclosure(log: run.log, expanded: $m.detailsExpanded)
                                .fixedSize()
                        }
                        Text(footerSentence(run))
                            .font(DuoFont.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 16)
                        Button(Copy.commonCancel) { m.requestCancel() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
        .padding(.horizontal, DuoSpace.pageWide)
        .padding(.top, DuoSpace.bandShort)
        .padding(.bottom, DuoSpace.pageWide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ run: BuildRun) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Banner(path: m.info?.game?.icon, size: 64, tag: m.platform == .ps2 ? Copy.tilePS2 : nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.gameName).font(DuoFont.stage)
                Text(Copy.workMeta(picture: run.picture, phone: run.phone, elapsed: Copy.duration(run.elapsed)))
                    .font(DuoFont.body)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(run.overallPercent)%")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(Copy.workOverall)
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func copyPanel(_ run: BuildRun, _ copy: CopyProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "powerplug.fill").foregroundStyle(DuoColor.warnText)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.copyKeep(run.phone)).font(DuoFont.bodyBold)
                    Text(Copy.copyAutolock)
                        .font(DuoFont.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: .duo(DuoRadius.panel))
            .overlay(RoundedRectangle.duo(DuoRadius.panel).strokeBorder(Color.orange.opacity(0.25)))

            HStack(spacing: DuoSpace.s) {
                if let room = run.roomAfterBytes {
                    infoCell(Copy.copyRoomAfter, StageCopy.bytes(Double(room)))
                }
                if let slots = run.slotsAfter {
                    infoCell("Slots on \(run.phone)", Copy.copySlotsAfter(slots))
                }
            }
        }
    }

    private func infoCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DuoFont.caption).foregroundStyle(.secondary)
            Text(value).font(DuoFont.bodyBold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(RoundedRectangle.duo(DuoRadius.panel).strokeBorder(DuoColor.hairline))
    }

    private func footerSentence(_ run: BuildRun) -> String {
        if run.copy != nil { return Copy.copyCancelNote }
        if run.stages.count > 1 { return Copy.workNext }
        return Copy.workSafe
    }
}

// MARK: - Failed (14)

struct FailedView: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore
    @EnvironmentObject private var library: LibraryStore
    let failure: Failure
    @State private var detailsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let run = m.run {
                header(run)
                redPanel(run)
                SectionLabel(text: Copy.failLadder)
                ladder(run)
                if failure.code.isLimit {
                    tip
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: DuoSpace.xs) {
                    if detailsOpen {
                        DetailsDisclosure(log: run.log, expanded: $detailsOpen)
                            .frame(maxWidth: .infinity)
                    }
                    HStack(alignment: .bottom) {
                        if !detailsOpen {
                            DetailsDisclosure(log: run.log, expanded: $detailsOpen)
                                .fixedSize()
                        }
                        Spacer(minLength: 16)
                        Button(Copy.failBack) { m.backToShelf() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        Button(Copy.failRetry) { m.retry() }
                            .buttonStyle(PrimaryButtonStyle(tall: true))
                    }
                }
            }
        }
        .padding(.horizontal, DuoSpace.pageWide)
        .padding(.top, DuoSpace.bandShort)
        .padding(.bottom, DuoSpace.pageWide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func header(_ run: BuildRun) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Banner(path: m.info?.game?.icon, size: 64, tag: m.platform == .ps2 ? Copy.tilePS2 : nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.gameName).font(DuoFont.stage)
                Text("\(run.picture) · to \(run.phone)")
                    .font(DuoFont.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
    }

    private func redPanel(_ run: BuildRun) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 18))
                .foregroundStyle(DuoColor.errorText)
            VStack(alignment: .leading, spacing: 5) {
                Text(Copy.failTitle).font(DuoFont.bodyBold).foregroundStyle(DuoColor.errorText)
                Text(failure.shownSentence(phone: run.phone))
                    .font(DuoFont.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DuoColor.error.opacity(0.1), in: .duo(DuoRadius.panel))
        .overlay(RoundedRectangle.duo(DuoRadius.panel).strokeBorder(DuoColor.error.opacity(0.35)))
    }

    @ViewBuilder private func ladder(_ run: BuildRun) -> some View {
        let other = phones.devices.first(where: { $0.connected && $0.udid != phones.device?.udid })
        let steps = FailureLadder.steps(for: failure, otherPhone: other?.name)
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle().fill(step.recommended ? Color.accentColor : Color.primary.opacity(0.08))
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(step.recommended ? .white : Color.secondary)
                    }
                    .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.text).font(DuoFont.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if step.showsInstalled {
                            HStack(spacing: 4) {
                                ForEach(installs.phone(id: phones.knownDevice?.udid)?.apps ?? []) { app in
                                    installedChip(app)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if step.action == .choosePhone, other != nil {
                        Menu(Copy.failOtherPhoneAction) {
                            ForEach(phones.devices.filter { $0.connected && $0.udid != phones.device?.udid }) { d in
                                Button(d.name) { phones.choose(d) }
                            }
                        }
                        .fixedSize()
                    } else if step.action == .showDetails {
                        Button(Copy.details) { detailsOpen = true }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else if step.action == .copyDetails {
                        Button(Copy.failCopyDetails) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(run.log.joined(separator: "\n"), forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(step.recommended ? 12 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(step.recommended ? DuoColor.panel : Color.clear, in: .duo(DuoRadius.panel))
                .overlay(RoundedRectangle.duo(DuoRadius.panel)
                    .strokeBorder(step.recommended ? Color.clear : DuoColor.hairline))
            }
        }
    }

    private func installedChip(_ app: InstalledApp) -> some View {
        HStack(spacing: 6) {
            GameThumb(image: library.entries.first(where: { $0.title == app.title })?.banner, size: 18, corner: 4)
            Text(app.title).font(.system(size: 11))
            Text("·").foregroundStyle(.secondary)
            Text(app.isExpiring ? Copy.failEndsTomorrow : Copy.slotDaysLeft(app.daysLeft ?? 0))
                .font(.system(size: 11))
                .foregroundStyle(app.isExpiring ? DuoColor.warnText : .secondary)
        }
        .padding(.horizontal, 7)
        .frame(height: 26)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(DuoColor.panelStroke))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
            Text(Copy.failPaidTip)
                .font(DuoFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // "How to switch" has no page in the app yet (DESIGN-QUESTIONS Q8); the tip is shown without a dead link.
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Done (15, 16)

struct DoneView: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    let info: DoneInfo

    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Banner(path: m.info?.game?.icon, size: 112, shadow: true)
                ZStack {
                    Circle().fill(DuoColor.window).frame(width: 46, height: 46)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.white, DuoColor.ready)
                }
                .offset(x: 10, y: 10)
            }
            .padding(.bottom, 4)

            Text(info.renewed ? Copy.doneRenewed(info.gameName) : Copy.doneTitle(game: info.gameName, phone: info.phone))
                .font(DuoFont.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(line)
                .font(DuoFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if info.needsTrust {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill").foregroundStyle(DuoColor.warnText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Copy.doneTrustTitle).font(DuoFont.bodyBold)
                        Text(Copy.doneTrustBody)
                            .font(DuoFont.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: 640, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: .duo(DuoRadius.panel))
                .overlay(RoundedRectangle.duo(DuoRadius.panel).strokeBorder(Color.orange.opacity(0.25)))
            } else {
                Text(Copy.doneOpen)
                    .font(DuoFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560)
            }

            if !info.slots.isEmpty {
                slotRow
            }

            Toggle(isOn: Binding(get: { settings.reminder }, set: { value in
                settings.reminder = value
                if value { Reminders.requestAccess() }
                Reminders.reschedule(installs: m.selectedInstalls, settings: settings)
            })) {
                Text(Copy.doneReminder).font(DuoFont.body)
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: 0)

            Button(Copy.doneBack) { m.backToShelf() }
                .buttonStyle(PrimaryButtonStyle(tall: true))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, DuoSpace.pageWide)
        .padding(.top, DuoSpace.bandShort + 4)
        .padding(.bottom, DuoSpace.pageWide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var line: String {
        if info.renewed, let expiry = info.expiry {
            return Copy.doneRenewLine(date: Copy.date(expiry), t: Copy.duration(info.took))
        }
        return Copy.doneFirst(Copy.duration(info.took))
    }

    private var slotRow: some View {
        VStack(alignment: .leading, spacing: DuoSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.doneSlots(phone: info.phone, n: info.slots.count)).font(DuoFont.section)
                Spacer(minLength: 8)
                Text(Copy.doneSlotsNote).font(DuoFont.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: DuoSpace.s) {
                ForEach(info.slots) { app in
                    doneSlot(app)
                }
            }
        }
        .frame(maxWidth: 680)
    }

    private func doneSlot(_ app: InstalledApp) -> some View {
        let isNew = app.title == info.gameName
        let days = app.daysLeft ?? 0
        return HStack(spacing: 8) {
            GameThumb(image: library.entries.first(where: { $0.title == app.title })?.banner, size: 34, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.title).font(DuoFont.bodyBold).lineLimit(1)
                Text(app.isExpired ? Copy.slotExpired
                     : (app.expiresAt.map { Copy.doneUntil(Copy.date($0)) } ?? Copy.slotDaysLeft(days)))
                    .font(DuoFont.caption)
                    .foregroundStyle(app.isExpiring ? DuoColor.warnText : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .duoPanel(DuoRadius.panel)
        .overlay(RoundedRectangle.duo(DuoRadius.panel).strokeBorder(isNew ? DuoColor.ready : Color.clear, lineWidth: 1.5))
    }
}

// MARK: - Setup sheet (10)

struct SetupSheet: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var setup: SetupStore
    @Environment(\.dismiss) private var dismiss
    @State private var scrolledPastTop = false
    @State private var showDoneAbove = false

    private struct OffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    var body: some View {
        let steps = setup.steps
        let done = steps.filter(\.isDone).count
        let running = steps.filter { $0.status == .running }.count
        let needs = steps.filter { $0.status == .needsYou }.count
        let firstPending = steps.firstIndex { !$0.isDone }

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(steps.isEmpty || done < steps.count ? Copy.setupTitle : Copy.setupTitleReady)
                        .font(DuoFont.sheetTitle)
                    Spacer(minLength: 12)
                    if !steps.isEmpty {
                        Text(Copy.setupCount(done: done, total: steps.count))
                            .font(DuoFont.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if !steps.isEmpty && done < steps.count {
                    Text(subtitle(running: running, needs: needs))
                        .font(DuoFont.body)
                        .foregroundStyle(.secondary)
                }
                if !steps.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(steps) { step in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(colour(step.status))
                                .frame(height: 4)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: DuoSpace.xs) {
                        Color.clear.frame(height: 0)
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: OffsetKey.self,
                                                       value: geo.frame(in: .named("setupScroll")).minY)
                            })
                            .id("top")
                        ForEach(steps) { step in
                            SetupStepRow(step: step).id(step.id)
                        }
                        Color.clear.frame(height: 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .coordinateSpace(name: "setupScroll")
                .onPreferenceChange(OffsetKey.self) { value in
                    scrolledPastTop = value < -6
                }
                .overlay(alignment: .top) {
                    if scrolledPastTop || showDoneAbove, let firstPending, firstPending > 0 {
                        Button {
                            showDoneAbove = false
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("top", anchor: .top) }
                        } label: {
                            Label(Copy.setupDoneAbove(firstPending), systemImage: "chevron.up")
                                .font(DuoFont.caption)
                                .padding(.horizontal, 12)
                                .frame(height: 26)
                                .background(DuoColor.sheet, in: Capsule())
                                .overlay(Capsule().strokeBorder(DuoColor.panelStroke))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        let target = m.setupTarget == "ps2-bios" ? "files" : m.setupTarget
                        if let target, steps.contains(where: { $0.id == target }) {
                            proxy.scrollTo(target, anchor: .top)
                        } else if let firstPending {
                            proxy.scrollTo(steps[firstPending].id, anchor: .top)
                            showDoneAbove = firstPending > 0
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            HStack(alignment: .center, spacing: 12) {
                Text(Copy.setupFooter)
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if setup.checking {
                    ProgressView().controlSize(.small)
                }
                Button(Copy.setupCheckAgain) {
                    setup.refresh()
                    m.phones.refresh()
                }
                .buttonStyle(.bordered)
                Button(Copy.setupDone) {
                    dismiss()
                    m.afterSetupIfPending()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 520)
        .background(DuoColor.sheet)
    }

    private func subtitle(running: Int, needs: Int) -> String {
        if doneAll() { return "" }
        if needs == 0 { return Copy.setupSubAllAuto }
        if running > 0 { return Copy.setupSubMixed(doing: running, needYou: needs) }
        return Copy.setupSubNeeds(needs)
    }

    private func doneAll() -> Bool {
        let steps = setup.steps
        return !steps.isEmpty && steps.allSatisfy(\.isDone)
    }

    private func colour(_ status: SetupStep.Status) -> Color {
        switch status {
        case .done: return DuoColor.ready
        case .running: return Color.accentColor
        case .needsYou: return DuoColor.warn
        }
    }
}

struct SetupStepRow: View {
    @EnvironmentObject private var setup: SetupStore
    let step: SetupStep
    @State private var expanded = false
    @State private var showOutput = false

    var body: some View {
        switch step.status {
        case .done(let value):
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.black, DuoColor.ready)
                        Text(step.title).font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 8)
                        Text(value).font(DuoFont.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !step.substeps.isEmpty {
                    substeps
                        .padding(.leading, 30)
                        .padding(.top, 2)
                } else if expanded, !step.details.isEmpty {
                    Text(step.details.joined(separator: "\n"))
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 30)
                }
            }
            .padding(.horizontal, 4)

        case .running:
            panel(tint: .accentColor) {
                HStack(spacing: 10) {
                    Text(step.title).font(DuoFont.bodyBold)
                    Spacer(minLength: 8)
                    ProgressView().controlSize(.small)
                }
                if !setup.fixLine.isEmpty {
                    Text(setup.fixLine)
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(Copy.setupRunning)
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
            }

        case .needsYou:
            panel(tint: DuoColor.warn) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(step.title).font(.system(size: 13, weight: .bold))
                            if let rule = step.rule {
                                Text(rule).font(DuoFont.bodyBold).foregroundStyle(DuoColor.warnText)
                            }
                        }
                        Text(step.explanation)
                            .font(DuoFont.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    actionButton
                }
                if !step.substeps.isEmpty { substeps }
                if setup.fixFailedID == step.id, setup.fixing == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Copy.setupFixFailed)
                            .font(DuoFont.caption)
                            .foregroundStyle(DuoColor.errorText)
                        Button(Copy.setupShowWhat) { showOutput.toggle() }
                            .buttonStyle(.link)
                            .font(DuoFont.caption)
                        if showOutput {
                            ScrollView {
                                Text(setup.fixOutput.joined(separator: "\n"))
                                    .font(DuoFont.log)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 104)
                            .background(Color.primary.opacity(0.05), in: .duo(8))
                        }
                    }
                }
            }
        }
    }

    private var substeps: some View {
        VStack(spacing: 0) {
            ForEach(step.substeps) { sub in
                HStack(spacing: 10) {
                    Image(systemName: sub.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(sub.done ? DuoColor.readyText : Color.secondary)
                    HStack(spacing: 4) {
                        Text(sub.title).font(.system(size: 12, weight: .semibold))
                        Text("· \(sub.body)").font(DuoFont.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if !sub.done, let action = sub.action {
                        Button(actionTitle(action)) { setup.run(action) }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(height: 38)
            }
        }
        .padding(.horizontal, 10)
        .background(Color.primary.opacity(0.05), in: .duo(10))
    }

    @ViewBuilder private var actionButton: some View {
        if setup.fixFailedID == step.id, setup.fixing == nil {
            if let action = step.action {
                Button(Copy.actionTryAgain) { setup.run(action) }
                    .buttonStyle(OutlineButtonStyle(tint: DuoColor.warnText))
            }
        } else if let action = step.action {
            Button(actionTitle(action)) { setup.run(action) }
                .buttonStyle(.bordered)
                .disabled(setup.fixing != nil)
        }
    }

    private func actionTitle(_ action: SetupAction) -> String {
        switch action {
        case .appStore: return Copy.actionAppStore
        case .openXcode: return Copy.actionOpenXcode
        case .chooseKeys, .chooseBIOS: return Copy.actionChoose
        case .fix(let id):
            let item = setup.doctor?.items.first(where: { $0.id == id })
            return item?.fix == "admin" ? Copy.actionFixPassword : Copy.actionFix
        }
    }

    private func panel<C: View>(tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            content()
        }
        .padding(12)
        .background(tint.opacity(0.08), in: .duo(12))
        .overlay(RoundedRectangle.duo(12).strokeBorder(tint.opacity(0.3)))
    }
}

// MARK: - On this iPhone (17)

struct RenewSheet: View {
    @EnvironmentObject private var m: AppModel
    @EnvironmentObject private var phones: DeviceStore
    @EnvironmentObject private var installs: InstallsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?

    private var knownPhones: [PhoneInstalls] {
        if let doc = installs.document { return doc.devices }
        return phones.devices.map { PhoneInstalls(deviceID: $0.udid, deviceName: $0.name) }
    }

    private var phone: PhoneInstalls? {
        knownPhones.first(where: { $0.deviceID == selectedID }) ?? knownPhones.first
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Text(Copy.phoneTitle).font(DuoFont.sheetTitle)
                    Spacer(minLength: 12)
                    Picker("", selection: Binding(get: { phone?.deviceID ?? "" }, set: { selectedID = $0 })) {
                        ForEach(knownPhones) { p in
                            Text(p.deviceName).tag(p.deviceID)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Text(Copy.phoneSub(phone?.used ?? 0))
                    .font(DuoFont.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(phone?.apps ?? []) { app in
                        row(app)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { settings.reminder }, set: { value in
                    settings.reminder = value
                    if value { Reminders.requestAccess() }
                    Reminders.reschedule(installs: phone, settings: settings)
                })) {
                    Text(Copy.phoneReminder).font(DuoFont.body)
                }
                .toggleStyle(.checkbox)

                HStack(spacing: 4) {
                    Toggle(isOn: $settings.autoRenew) {
                        Text(Copy.phoneAutoRenew).font(DuoFont.body)
                    }
                    .toggleStyle(.checkbox)
                    Text(Copy.phoneAutoRenewWhen).font(DuoFont.caption).foregroundStyle(.secondary)
                }

                if let left = phone?.weeklyAppIDsLeft {
                    Text(Copy.phoneWeekly(left))
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = m.renewError {
                    Text(error).font(DuoFont.caption).foregroundStyle(DuoColor.errorText)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            Divider()
            HStack(spacing: 12) {
                Text(connectionText)
                    .font(DuoFont.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(Copy.phoneClose) { dismiss() }
                    .buttonStyle(.bordered)
                Button(Copy.menuRenewAll) { m.renewAll() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled((phone?.apps.isEmpty ?? true) || !installs.renewing.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 560, height: 490)
        .background(DuoColor.sheet)
        .onAppear {
            if selectedID == nil { selectedID = m.device?.udid ?? knownPhones.first?.deviceID }
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        let expiring = app.isExpiring
        return HStack(spacing: 12) {
            GameThumb(image: library.entries.first(where: { $0.title == app.title })?.banner, size: 44, corner: 10)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(app.title).font(DuoFont.bodyBold)
                    Spacer(minLength: 8)
                    Text(daysText(app))
                        .font(DuoFont.caption)
                        .foregroundStyle(expiring ? DuoColor.warnText : .secondary)
                }
                DaysBar(fraction: Double(max(app.daysLeft ?? 0, 0)) / 7,
                        tint: expiring ? DuoColor.warn : DuoColor.ready)
            }
            Button {
                m.renew(app)
            } label: {
                if installs.renewing.contains(app.bundleID) {
                    ProgressView().controlSize(.small)
                } else {
                    Text(Copy.slotRenew)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!installs.renewing.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(expiring ? Color.orange.opacity(0.1) : Color.clear)
    }

    private func daysText(_ app: InstalledApp) -> String {
        if app.isExpired { return Copy.slotExpired }
        if app.isExpiring { return Copy.phoneRowTomorrow }
        let days = app.daysLeft ?? 0
        guard let expiry = app.expiresAt else { return Copy.slotDaysLeft(days) }
        return Copy.phoneRowDays(days, date: Copy.date(expiry))
    }

    private var connectionText: String {
        guard let phone else { return "" }
        let connected = phones.devices.first(where: { $0.udid == phone.deviceID })?.connected ?? false
        return connected ? Copy.phoneConnected(phone.deviceName) : Copy.deviceDisconnected(phone.deviceName)
    }
}
