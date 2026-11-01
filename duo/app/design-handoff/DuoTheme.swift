// DuoTheme.swift — design tokens and shared views for the "Shelf" redesign.
// See IMPLEMENTATION.md §4–§5. Pixel references: screens/18-system-tokens-components.png.
// Everything is appearance-aware; only the accent follows the user's system setting.

import SwiftUI
import AppKit

// MARK: - Colour roles

enum DuoColor {
    /// Picks a value per appearance.
    static func dynamic(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let window = dynamic(dark: NSColor(hex: 0x1E1E1E), light: NSColor(hex: 0xF6F6F8))
    static let statusStrip = dynamic(dark: NSColor(hex: 0x262628), light: NSColor(hex: 0xEDEDF0))
    static let panel = dynamic(dark: .white.withAlphaComponent(0.05), light: .white)
    static let panelStroke = dynamic(dark: .clear, light: .black.withAlphaComponent(0.05))
    static let hairline = dynamic(dark: .white.withAlphaComponent(0.08), light: .black.withAlphaComponent(0.08))
    static let sheet = dynamic(dark: NSColor(hex: 0x2A2A2D), light: .white)

    // State colours: fills use the system colour, text uses a darker value in light mode for 4.5:1 contrast.
    static let ready = Color.green
    static let readyText = dynamic(dark: NSColor(hex: 0x30D158), light: NSColor(hex: 0x248A3D))
    static let likely = dynamic(dark: NSColor(hex: 0xFFD60A), light: NSColor(hex: 0x8A6D00))
    static let warn = Color.orange
    static let warnText = dynamic(dark: NSColor(hex: 0xFFB340), light: NSColor(hex: 0xA33000))
    static let bringUp = dynamic(dark: NSColor(hex: 0xDA8FFF), light: NSColor(hex: 0x8944AB))
    static let error = Color.red
    static let errorText = dynamic(dark: NSColor(hex: 0xFF6961), light: NSColor(hex: 0xD70015))
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Type

enum DuoFont {
    static let title    = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 24, weight: .bold, design: .rounded)
    static let sheetTitle = Font.system(size: 20, weight: .bold, design: .rounded)
    static let stage    = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let section  = Font.system(size: 15, weight: .semibold)
    static let body     = Font.system(size: 13)
    static let bodyBold = Font.system(size: 13, weight: .semibold)
    static let caption  = Font.system(size: 12)
    static let label    = Font.system(size: 11, weight: .semibold)   // use with .tracking(0.6) and uppercase text
    static let log      = Font.system(size: 11, design: .monospaced)
}

// MARK: - Spacing and radii

enum DuoSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 22
    static let page: CGFloat = 28       // Home side padding
    static let pageWide: CGFloat = 32   // Card / Working / Failed side padding
    static let topBand: CGFloat = 52    // band that holds the traffic lights and top-bar controls
}

enum DuoRadius {
    static let control: CGFloat = 8
    static let button: CGFloat = 12
    static let panel: CGFloat = 14
    static let slotArt: CGFloat = 13
    static let tile: CGFloat = 18
    static let banner: CGFloat = 26
}

extension Shape where Self == RoundedRectangle {
    static func duo(_ r: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: r, style: .continuous) }
}

// MARK: - Support state (never merge these)

enum SupportState: Equatable {
    case tested
    case otherVersionTested(testedVersion: String)
    case bringUp
    case new

    var text: String {
        switch self {
        case .tested: return "Tested with nxnative"
        case .otherVersionTested(let v): return "Another version was tested (tested: \(v)) — likely works"
        case .bringUp: return "Still being brought up — may not start"
        case .new: return "New to nxnative — it may not start"
        }
    }

    var symbol: String {
        switch self {
        case .tested: return "checkmark.seal.fill"
        case .otherVersionTested: return "exclamationmark.circle"
        case .bringUp: return "clock"
        case .new: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .tested: return DuoColor.readyText
        case .otherVersionTested: return DuoColor.likely
        case .bringUp: return DuoColor.bringUp
        case .new: return DuoColor.warnText
        }
    }
}

struct SupportBadge: View {
    let state: SupportState
    var body: some View {
        Label(state.text, systemImage: state.symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(state.tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(state.tint.opacity(0.12), in: .duo(10))
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Primary button that explains itself when disabled

struct PrimaryActionButton: View {
    let title: String
    /// Non-nil disables the button and shows the reason under it.
    var reason: String? = nil
    var footnote: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: DuoSpace.xs) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .clipShape(.duo(DuoRadius.button))
            .disabled(reason != nil)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityHint(reason ?? "")

            if let reason {
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(DuoFont.caption)
                    .foregroundStyle(DuoColor.errorText)
            } else if let footnote {
                Text(footnote).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - File chip

struct FileChip: View {
    enum Kind { case ok, add, problem }
    let kind: Kind
    let text: String
    var onTap: (() -> Void)? = nil      // add: opens picker; problem: removes the file

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .ok: Image(systemName: "checkmark").foregroundStyle(DuoColor.readyText)
            case .add: Image(systemName: "plus")
            case .problem: EmptyView()
            }
            Text(text)
            if kind == .problem, let onTap {
                Button(action: onTap) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this file")
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(kind == .problem ? DuoColor.errorText : .primary)
        .padding(.horizontal, 12).frame(height: 28)
        .background(background, in: Capsule())
        .overlay(border)
        .contentShape(Capsule())
        .onTapGesture { if kind == .add { onTap?() } }
    }

    private var background: Color {
        switch kind {
        case .ok: return Color.primary.opacity(0.08)
        case .add: return .clear
        case .problem: return DuoColor.error.opacity(0.14)
        }
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .ok: EmptyView()
        case .add: Capsule().strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .problem: Capsule().strokeBorder(DuoColor.error.opacity(0.4))
        }
    }
}

// MARK: - Slot card (On this iPhone)

struct SlotCard: View {
    enum State { case healthy(daysLeft: Int), expiring(String), free }
    let title: String?
    let art: Image?
    let state: State
    var onRenew: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DuoSpace.s) {
            artView
            VStack(alignment: .leading, spacing: 5) {
                switch state {
                case .healthy(let days):
                    Text(title ?? "").font(DuoFont.bodyBold)
                    Text("\(days) days left").font(DuoFont.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(days), total: 7).tint(DuoColor.ready)
                case .expiring(let text):
                    Text(title ?? "").font(DuoFont.bodyBold)
                    Text(text).font(DuoFont.caption).foregroundStyle(DuoColor.warnText)
                    Button("Renew") { onRenew?() }.controlSize(.small).buttonStyle(.bordered).tint(.orange)
                case .free:
                    Text("Free slot").font(DuoFont.bodyBold).foregroundStyle(.secondary)
                    Text("Install a game to use it").font(DuoFont.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DuoSpace.s)
        .frame(height: 84)
        .background(fill, in: .duo(DuoRadius.panel))
        .overlay(stroke)
    }

    @ViewBuilder private var artView: some View {
        if let art {
            art.resizable().frame(width: 56, height: 56).clipShape(.duo(DuoRadius.slotArt))
        } else {
            Image(systemName: "plus").frame(width: 56, height: 56)
                .background(Color.primary.opacity(0.04), in: .duo(DuoRadius.slotArt))
                .foregroundStyle(.secondary)
        }
    }

    private var fill: Color {
        switch state {
        case .expiring: return Color.orange.opacity(0.1)
        case .free: return .clear
        case .healthy: return DuoColor.panel
        }
    }

    @ViewBuilder private var stroke: some View {
        switch state {
        case .expiring: RoundedRectangle.duo(DuoRadius.panel).strokeBorder(Color.orange.opacity(0.3))
        case .free: RoundedRectangle.duo(DuoRadius.panel)
                .strokeBorder(Color.primary.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        case .healthy: RoundedRectangle.duo(DuoRadius.panel).strokeBorder(DuoColor.panelStroke)
        }
    }
}

// MARK: - Stage timeline (Working)

struct TimelineStage: Identifiable {
    enum Status { case done(elapsed: String), active, pending }
    let id: String
    let title: String
    var status: Status
    var detail: String? = nil        // real count from the pipeline, e.g. "18,204 of 62,901"
    var fraction: Double? = nil      // stage progress, if the pipeline sends it
    var eta: String? = nil           // only when the pipeline sends one
    var hint: String? = nil          // e.g. "This is the long one, 10–40 minutes, and only the first time."
}

struct StageTimeline: View {
    let stages: [TimelineStage]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        marker(stage.status)
                        if index < stages.count - 1 {
                            Rectangle().fill(connector(stage.status)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 22)
                    content(stage).padding(.bottom, isActive(stage) ? 16 : 10)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isActive(_ s: TimelineStage) -> Bool { if case .active = s.status { return true }; return false }

    @ViewBuilder private func marker(_ status: TimelineStage.Status) -> some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.black, DuoColor.ready)
        case .active:
            Circle().strokeBorder(Color.accentColor, lineWidth: 3).frame(width: 20, height: 20)
        case .pending:
            Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 2).frame(width: 12, height: 12).padding(4)
        }
    }

    private func connector(_ status: TimelineStage.Status) -> Color {
        if case .done = status { return DuoColor.ready.opacity(0.9) }
        return Color.primary.opacity(0.14)
    }

    @ViewBuilder private func content(_ s: TimelineStage) -> some View {
        switch s.status {
        case .done(let elapsed):
            HStack { Text(s.title); Spacer(); Text(elapsed).foregroundStyle(.secondary).monospacedDigit() }
                .font(DuoFont.body)
        case .pending:
            HStack(spacing: 4) {
                Text(s.title)
                if let hint = s.hint { Text("· \(hint)").foregroundStyle(DuoColor.warnText) }
            }
            .font(DuoFont.body).foregroundStyle(.secondary)
        case .active:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.title).font(DuoFont.stage)
                    Spacer()
                    Text(s.eta.map { "about \($0) left" } ?? "time left: not known yet")
                        .font(DuoFont.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let f = s.fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                Text([s.detail, s.hint].compactMap { $0 }.joined(separator: " · "))
                    .font(DuoFont.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

// MARK: - Setup step row

struct SetupStep: Identifiable {
    enum Status { case done(value: String), running(fraction: Double?), needsYou(explanation: String), notChecked }
    let id: String
    let title: String
    var status: Status
    var action: (title: String, run: () -> Void)? = nil
}

struct SetupStepRow: View {
    let step: SetupStep
    @State private var expanded = false

    var body: some View {
        switch step.status {
        case .done(let value):
            DisclosureGroup(isExpanded: $expanded) {
                // Details: path, version, etc.
                EmptyView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.black, DuoColor.ready)
                    Text(step.title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(value).font(DuoFont.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 30)
            .padding(.horizontal, 24)

        case .running(let fraction):
            panel(tint: .accentColor) {
                HStack { Text(step.title).font(DuoFont.bodyBold); Spacer()
                    if let f = fraction { Text("Installing · \(Int(f * 100))%").font(DuoFont.caption)
                        .foregroundStyle(.secondary).monospacedDigit() } }
                if let f = fraction { ProgressView(value: f) } else { ProgressView().progressViewStyle(.linear) }
                Text("Duo Builder is doing this one. Nothing to click.").font(DuoFont.caption).foregroundStyle(.secondary)
            }

        case .needsYou(let explanation):
            panel(tint: .orange) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(DuoFont.bodyBold)
                        Text(explanation).font(DuoFont.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let action = step.action { Button(action.title, action: action.run).buttonStyle(.borderedProminent) }
                }
            }

        case .notChecked:
            HStack { Text(step.title).foregroundStyle(.secondary); Spacer(); ProgressView().controlSize(.small) }
                .padding(.horizontal, 24).frame(minHeight: 30)
        }
    }

    private func panel<C: View>(tint: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .background(tint.opacity(0.08), in: .duo(12))
            .overlay(RoundedRectangle.duo(12).strokeBorder(tint.opacity(0.3)))
            .padding(.horizontal, 12).padding(.vertical, 6)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(DuoFont.label).tracking(0.6).foregroundStyle(.secondary)
    }
}
