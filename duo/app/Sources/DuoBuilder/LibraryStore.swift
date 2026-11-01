import AppKit
import Foundation
import SwiftUI

/// Whether a game's prepared build is on this Mac. `IMPLEMENTATION.md` §3 allows a path convention until
/// `bin/duo cache list --json` exists; this checks the folder the pipeline builds into (see DESIGN-QUESTIONS Q3).
enum CacheProbe {
    static func key(for info: GameInfo) -> String? {
        guard let baseFile = info.base?.file, let title = info.game?.title, !title.isEmpty else { return nil }
        let folder = (baseFile as NSString).deletingLastPathComponent
        let upper = title.uppercased()
        let baseTitle = info.infoBaseTitle(fallback: title)
        let p1: String = folder + "/" + upper + "_build"
        let p2: String = folder + "/.duo/" + baseTitle + "/" + upper + "_build"
        let p3: String = folder + "/.duo/" + baseTitle.lowercased() + "/" + upper + "_build"
        let candidates: [String] = [p1, p2, p3]
        for path in candidates {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                if !contents.isEmpty { return path }
            }
        }
        return nil
    }

    /// The .app the pipeline leaves in the build folder, when the whole build (not only the graphics) is there.
    /// Not used for the shelf's status line; kept as the honest check for "already built".
    static func appProduct(in key: String?) -> URL? {
        guard let key else { return nil }
        let app = key + "/xcode-derived-data/Build/Products/Release-iphoneos/DmIOS.app"
        return FileManager.default.fileExists(atPath: app) ? URL(fileURLWithPath: app) : nil
    }
}

/// Every game the app has read, with the card it was read as, its bookmarks and its banner — so the shelf draws
/// without touching a game file (IMPLEMENTATION.md §9).
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var entries: [LibraryEntry] = []

    private let fileURL: URL?
    private let persistent: Bool

    init(persistent: Bool = true) {
        self.persistent = persistent
        self.fileURL = persistent ? LibraryStore.supportDirectory()?.appendingPathComponent("library.json") : nil
        if persistent { load() }
    }

    static func supportDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Duo Builder", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: Reading and writing

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([LibraryEntry].self, from: data)) ?? []
    }

    func save() {
        guard persistent, let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Entries

    /// Adds or refreshes the game that was just read. The banner and the card are stored now so the shelf never
    /// re-reads a game file.
    @discardableResult
    func remember(info: GameInfo, urls: [URL], platform: Platform, now: Date = Date()) -> LibraryEntry? {
        guard let game = info.game else { return nil }
        let title = info.titleId ?? game.title
        guard !title.isEmpty else { return nil }
        let byPath = Dictionary(urls.map { ($0.standardizedFileURL.path, $0) }, uniquingKeysWith: { a, _ in a })
        func ref(_ package: GameInfo.Package?, role: String) -> FileRef? {
            guard let package else { return nil }
            let fileURL = URL(fileURLWithPath: (package.file as NSString).expandingTildeInPath).standardizedFileURL
            let url = byPath[fileURL.path] ?? fileURL
            return FileRef.make(url: url, role: role, version: package.displayVersion ?? package.name, name: package.name)
        }
        var files: [FileRef] = []
        if let base = ref(info.base, role: platform == .ps2 ? "disc" : "application") { files.append(base) }
        for u in info.updates { if let r = ref(u, role: "patch") { files.append(r) } }
        for d in info.dlc { if let r = ref(d, role: "addon") { files.append(r) } }
        if files.isEmpty {
            // Nothing recognized yet (an update without its base): keep the dropped URLs so the card can still be
            // shown and Locate… can fix the set.
            files = urls.map { FileRef.make(url: $0, role: "other", version: nil, name: $0.lastPathComponent) }
        }
        let entry = LibraryEntry(id: title, title: game.name ?? title, publisher: game.publisher, platform: platform,
                                 files: files, bannerPNG: LibraryStore.bannerPNG(from: game.icon),
                                 support: SupportStateDTO(info.support), lastUsed: now,
                                 cacheKey: CacheProbe.key(for: info), info: info, version: game.version,
                                 bytes: game.bytes, buildID: game.buildId)
        if let i = entries.firstIndex(where: { $0.id == title }) {
            // Keep the first-seen date out of it (there is none) but refresh everything the new read knows.
            var merged = entry
            merged.bannerPNG = entry.bannerPNG ?? entries[i].bannerPNG
            entries[i] = merged
        } else {
            entries.append(entry)
        }
        save()
        return entries.first(where: { $0.id == title })
    }

    func touch(_ id: String, now: Date = Date()) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].lastUsed = now
        save()
    }

    func remove(_ id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    func setCache(_ id: String, key: String?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].cacheKey = key
        save()
    }

    func replace(_ entry: LibraryEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry } else { entries.append(entry) }
        save()
    }

    // MARK: Sorting (§6.02)

    /// Most recently used first; games currently on the selected phone after the others.
    func sorted(onPhoneTitles: Set<String>) -> [LibraryEntry] {
        entries.sorted { a, b in
            let ao = onPhoneTitles.contains(a.title), bo = onPhoneTitles.contains(b.title)
            if ao != bo { return !ao }
            return a.lastUsed > b.lastUsed
        }
    }

    var reinstallCount: Int { entries.filter(\.isPrepared).count }

    // MARK: Banner cache (256 px, §9)

    static func bannerPNG(from path: String?) -> Data? {
        guard let path, let image = NSImage(contentsOfFile: path) else { return nil }
        return pngData(from: image, side: 256)
    }

    static func pngData(from image: NSImage, side: Int) -> Data? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Snapshot fixtures

    func use(_ entries: [LibraryEntry]) {
        self.entries = entries
    }
}

private extension GameInfo {
    /// The 16-hex title of the base package. The CLI reports it on `base`, but the app's `Package` only decodes
    /// file/kind/name/display_version, so the game's title id is the same value for a single game.
    func infoBaseTitle(fallback: String) -> String { titleId ?? game?.title ?? fallback }
}

extension LibraryEntry {
    /// The image the shelf and the card draw for this entry: the cached NACP icon, else Banner's fallback.
    var banner: Image? {
        guard let bannerPNG, let image = NSImage(data: bannerPNG) else { return nil }
        return Image(nsImage: image)
    }
}
