import Foundation

/// `duo info --json`: the dropped packages as one game (bin/duo `describe`).
struct GameInfo: Codable, Equatable {
    struct Game: Codable, Equatable {
        var title: String
        var name: String?
        var publisher: String?
        var version: String?
        var icon: String?
        var buildId: String?
        var bytes: Int64?
    }
    struct Package: Codable, Equatable {
        var file: String
        var kind: String
        var displayVersion: String?
        var name: String?
    }
    struct Duo: Codable, Equatable {
        /// `available` (a Duo patch pack names this exact build), `none`
        var state: String
        var name: String?
        var author: String?
        var source: String?
        var note: String?
    }

    struct Support: Codable, Equatable {
        /// `tested` (nxnative brought up this exact build), `other-version`, `provisional`, `unknown` (no profile);
        /// an `.iso (ps2)` game uses `verified`, `provisional`, `new`.
        var state: String
        var versions: [String]
        /// The pipeline's one plain line about this game ("plays", "boots, still being brought up", …).
        var note: String? = nil
    }

    /// `duo info`'s `ps2` object, passed through from `tools/ps2info`. Only the fields the card needs are decoded;
    /// the rest of the document is ignored.
    struct PS2: Codable, Equatable {
        var serial: String?
        var region: String?
        var layers: Int?
        var sizeBytes: Int64?
        /// `required`: the title wants a BIOS dump (the runtime cannot use one yet); `optional`; nil: not mentioned.
        var bios: String?
        var boot: String?
        var bootCrc: String?
        var bootSha256: String?
    }

    struct CartridgeGame: Codable, Equatable, Identifiable {
        var title: String
        var name: String?
        var id: String { title }
    }

    var game: Game?
    /// every game on a cartridge that holds several (empty otherwise), and the one this info is about
    var cartridge: [CartridgeGame]?
    var titleId: String?
    var base: Package?
    var update: Package?
    var updates: [Package]
    var dlc: [Package]
    var duo: Duo
    var support: Support?
    var problems: [String]
    var keys: String?
    /// Present only for an `.iso (ps2)` game.
    var ps2: PS2? = nil

    var files: [String] { ([base] + updates.map(Optional.some) + dlc.map(Optional.some)).compactMap { $0?.file } }
}

/// `duo doctor --json`: what this Mac still needs.
struct Doctor: Decodable, Equatable {
    struct Item: Decodable, Equatable, Identifiable {
        var id: String
        var title: String
        var ok: Bool
        var detail: String
        /// `auto` (the app fixes it), `admin` (fixes it after one password prompt), `manual` (the player does it), `none`
        var fix: String
        var action: String
    }
    var items: [Item]
    var ready: Bool

    var missing: [Item] { items.filter { !$0.ok } }
}

/// `duo devices --json`: real iPhones and iPads, the most usable first.
struct Device: Decodable, Equatable, Identifiable {
    var udid: String
    var name: String
    var model: String?
    var os: String?
    var connected: Bool
    var wired: Bool
    var devmode: Bool
    var duo: Bool
    var id: String { udid }
}

struct DeviceList: Decodable { var devices: [Device] }
