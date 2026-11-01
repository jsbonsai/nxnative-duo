// DuoTheme.swift — design tokens and shared views for the "Shelf" redesign.
// Transcribed from design-handoff/DuoTheme.swift (IMPLEMENTATION.md §4–§5); pixel references:
// design-handoff/screens/18-system-tokens-components.png. The reference is "written as reference code and not yet
// compiled"; the adjustments here are compile fixes and the component states the screens need, not new design.

import AppKit
import SwiftUI

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
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 24, weight: .bold, design: .rounded)
    static let sheetTitle = Font.system(size: 20, weight: .bold, design: .rounded)
    static let stage = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let section = Font.system(size: 15, weight: .semibold)
    static let body = Font.system(size: 13)
    static let bodyBold = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 12)
    static let label = Font.system(size: 11, weight: .semibold)   // use with .tracking(0.6) and uppercase text
    static let log = Font.system(size: 11, design: .monospaced)
}

// MARK: - Spacing and radii

enum DuoSpace {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 22
    static let page: CGFloat = 28        // Home side padding
    static let pageWide: CGFloat = 32    // Card / Working / Failed side padding
    static let topBand: CGFloat = 52     // band that holds the traffic lights and top-bar controls
    static let bandShort: CGFloat = 44   // Working / Failed / Done, which have no top-bar controls
    static let statusStrip: CGFloat = 40
    static let libraryArt: CGFloat = 120
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
        case .tested: return Copy.supportTested
        case .otherVersionTested(let v): return Copy.supportOtherVersion(v)
        case .bringUp: return Copy.supportBringUp
        case .new: return Copy.supportNew
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

// MARK: - Filled primary button (§18: default, hover, pressed, focus, disabled)

struct PrimaryButtonStyle: ButtonStyle {
    var tall: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, tall: tall)
    }
}

private struct PrimaryButtonBody: View {
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    let configuration: ButtonStyleConfiguration
    let tall: Bool

    var body: some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(enabled ? Color.white : Color.secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: tall ? 44 : 34)
            .background(
                RoundedRectangle.duo(DuoRadius.button)
                    .fill(fill)
            )
            .contentShape(RoundedRectangle.duo(DuoRadius.button))
            .onHover { hovering = $0 }
    }

    private var fill: Color {
        guard enabled else { return Color.primary.opacity(0.12) }
        let base = Color.accentColor
        if configuration.isPressed { return base.opacity(0.88) }
        if hovering { return base.opacity(0.92) }
        return base
    }
}

/// The small outlined buttons of the design (Renew on an expiring slot, Choose…, Add a Pack…).
struct OutlineButtonStyle: ButtonStyle {
    var tint: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint ?? Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(RoundedRectangle.duo(DuoRadius.control).fill(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear))
            .overlay(RoundedRectangle.duo(DuoRadius.control).strokeBorder((tint ?? Color.primary).opacity(0.45)))
            .contentShape(RoundedRectangle.duo(DuoRadius.control))
    }
}

// MARK: - Primary button that explains itself when disabled

struct PrimaryActionButton: View {
    let title: String
    /// Non-nil disables the button and shows the reason under it.
    var reason: String? = nil
    var footnote: String? = nil
    var shortcut: KeyboardShortcut = KeyboardShortcut(.return, modifiers: .command)
    let action: () -> Void

    var body: some View {
        VStack(spacing: DuoSpace.xs) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(reason != nil)
            .keyboardShortcut(shortcut)
            .accessibilityHint(reason ?? "")

            if let reason {
                Label(reason, systemImage: "exclamationmark.circle")
                    .font(DuoFont.caption)
                    .foregroundStyle(DuoColor.errorText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - File chip

struct FileChip: View {
    /// `fix`: a problem the chip itself can act on (the BIOS "Add…" chip); it opens an action instead of showing
    /// the remove ✕ that the per-file problem chip uses.
    enum Kind { case ok, add, problem, fix }
    let kind: Kind
    let text: String
    var onTap: (() -> Void)? = nil      // add: opens the picker; problem: removes the file

    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .ok: Image(systemName: "checkmark").foregroundStyle(DuoColor.readyText)
            case .add: Image(systemName: "plus")
            case .problem, .fix: EmptyView()
            }
            Text(text)
            if kind == .problem, let onTap {
                Button(action: onTap) { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(DuoColor.errorText)
                    .accessibilityLabel(Copy.chipRemoveA11y)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(kind == .problem || kind == .fix ? DuoColor.errorText : Color.primary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(background, in: Capsule())
        .overlay(border)
        .contentShape(Capsule())
        .onTapGesture { if kind == .add || kind == .fix { onTap?() } }
    }

    private var background: Color {
        switch kind {
        case .ok: return Color.primary.opacity(0.08)
        case .add: return .clear
        case .problem, .fix: return DuoColor.error.opacity(0.14)
        }
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .ok: EmptyView()
        case .add: Capsule().strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        case .problem, .fix: Capsule().strokeBorder(DuoColor.error.opacity(0.4))
        }
    }
}

// MARK: - Slot card (On this iPhone)

struct SlotCard: View {
    enum State: Equatable {
        case healthy(daysLeft: Int)
        case expiring(String)
        case placeholder(Int)
        case free
    }
    let title: String?
    let art: Image?
    let state: State
    var highlighted: Bool = false
    var accessibilityLabel: String = ""
    var onRenew: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DuoSpace.s) {
            artView
            VStack(alignment: .leading, spacing: 5) {
                switch state {
                case .healthy(let days):
                    Text(title ?? "").font(DuoFont.bodyBold).lineLimit(1)
                    Text(Copy.slotDaysLeft(days)).font(DuoFont.caption).foregroundStyle(.secondary)
                    DaysBar(fraction: Double(days) / 7, tint: DuoColor.ready)
                case .expiring(let text):
                    Text(title ?? "").font(DuoFont.bodyBold).lineLimit(1)
                    Text(text).font(DuoFont.caption).foregroundStyle(DuoColor.warnText)
                    Button(Copy.slotRenew) { onRenew?() }
                        .buttonStyle(OutlineButtonStyle(tint: DuoColor.warnText))
                case .placeholder(let index):
                    Spacer(minLength: 0)
                    Text(Copy.slotPlaceholder(index))
                        .font(DuoFont.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                case .free:
                    Text(Copy.slotFreeTitle).font(DuoFont.bodyBold).foregroundStyle(.secondary)
                    Text(Copy.slotFreeBody)
                        .font(DuoFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DuoSpace.s)
        .frame(height: 84)
        .background(fill, in: .duo(DuoRadius.panel))
        .overlay(stroke)
        .contentShape(RoundedRectangle.duo(DuoRadius.panel))
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel.isEmpty ? (title ?? "") : accessibilityLabel)
    }

    @ViewBuilder private var artView: some View {
        if let art {
            art.resizable().interpolation(.high).frame(width: 56, height: 56)
                .clipShape(.duo(DuoRadius.slotArt))
        } else if case .placeholder = state {
            Spacer().frame(width: 0)
        } else if case .free = state {
            Image(systemName: "plus").frame(width: 56, height: 56)
                .background(Color.primary.opacity(0.04), in: .duo(DuoRadius.slotArt))
                .foregroundStyle(.secondary)
        } else {
            LinearGradient(colors: [.red.opacity(0.8), .pink.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 56, height: 56)
                .clipShape(.duo(DuoRadius.slotArt))
        }
    }

    private var fill: Color {
        switch state {
        case .expiring: return Color.orange.opacity(0.1)
        case .free, .placeholder: return .clear
        case .healthy: return DuoColor.panel
        }
    }

    @ViewBuilder private var stroke: some View {
        switch state {
        case .expiring:
            RoundedRectangle.duo(DuoRadius.panel).strokeBorder(Color.orange.opacity(0.3))
        case .free:
            RoundedRectangle.duo(DuoRadius.panel)
                .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.16),
                              style: StrokeStyle(lineWidth: highlighted ? 2 : 1.5, dash: [6, 5]))
        case .placeholder:
            RoundedRectangle.duo(DuoRadius.panel)
                .strokeBorder(Color.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        case .healthy:
            RoundedRectangle.duo(DuoRadius.panel).strokeBorder(DuoColor.panelStroke)
        }
    }
}

/// The 8 pt stage bar, filled in the accent (never an indeterminate shimmer, §4.3/§5).
struct LinearBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint).frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The 4 pt bars of the design (slot days left, expiry, renew rows).
struct DaysBar: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint).frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DuoFont.label)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Panel

extension View {
    /// The filled panel of §4.1: 5% primary in dark, white plus a hairline in light.
    func duoPanel(_ radius: CGFloat = DuoRadius.panel) -> some View {
        background(DuoColor.panel, in: .duo(radius))
            .overlay(RoundedRectangle.duo(radius).strokeBorder(DuoColor.panelStroke))
    }
}
