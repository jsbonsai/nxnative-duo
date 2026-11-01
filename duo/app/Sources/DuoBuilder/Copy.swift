import Foundation

/// Every user-facing string, from design-handoff/COPY.md (the designer's final copy), except the owner's later rule
/// that copy never names a console: those lines use the file formats instead. The complete delta (design text →
/// shipped text) is in DESIGN-QUESTIONS.md §B.
/// Views read sentences from here and nowhere else. `<placeholders>` are the functions' arguments.
///
/// The pack's register: second person, present tense, short sentences; no exclamation marks, no marketing
/// adjectives, no emoji in chrome, and never "provisioning profile", "entitlement", "NSP" or "shader".
enum Copy {

    // MARK: - Top bar and status strip

    static let deviceNone = "No iPhone yet"
    static func deviceDisconnected(_ phone: String) -> String { "\(phone) (not connected)" }
    static let deviceMenuOnThisPhone = "On This iPhone…"
    static let deviceMenuNewPhone = "Set Up a New iPhone…"
    static let backLibrary = "Library"

    static let statusReady = "This Mac is ready"
    static func statusFree(_ n: String) -> String { "· \(n) GB free" }
    static func statusTodo(_ n: Int) -> String {
        n == 1 ? "1 thing to set up" : "\(n) things to set up"
    }
    static let statusChecking = "Checking this Mac…"
    static let statusSetupLink = "Setup"
    static let statusNotAffiliated = "Not affiliated with Nintendo"

    // MARK: - Home

    static let homeSlotsTitle = "On this iPhone"
    static func homeSlotsCount(_ used: Int) -> String { "\(used) of 3 apps · free Apple ID" }
    static let homeSlotsFirstRun = "A free Apple ID gives you 3 slots, 7 days at a time"
    static func slotPlaceholder(_ n: Int) -> String { "Slot \(n)" }
    static func slotDaysLeft(_ n: Int) -> String { n == 1 ? "1 day left" : "\(n) days left" }
    static let slotOneDayLeft = "1 day left"
    static let slotExpiresTomorrow = "Expires tomorrow"
    static let slotExpired = "Expired — renew to open it again"
    static let slotRenew = "Renew"
    static let slotFreeTitle = "Free slot"
    static let slotFreeBody = "Install a game to use it"

    static let homeLibraryTitle = "Library"
    static func homeLibraryCount(games: Int, reinstall: Int) -> String {
        reinstall > 0 ? "\(games) games · \(reinstall) reinstall in about a minute" : "\(games) games"
    }
    static let tileAdd = "Add Game…"
    static let tileAddHint = "Or drop .xci / .nsp · .iso (ps2) anywhere"
    static let tileReady = "Ready · about 1 min"
    static let tileNotBuilt = "Not built yet"
    static func tileOnPhone(_ phone: String) -> String { "On \(phone)" }
    static let tileNew = "New to nxnative"
    static let tileBringUp = "May not start"
    static let tilePS2 = ".iso"

    static let firstRunTitle = "Your game, on your phone."
    static let firstRunBody = "Drop a game you dumped yourself. Duo Builder turns it into an app on your iPhone. Your files stay on this Mac."
    static let firstRunStep1 = "Set up this Mac — Duo Builder does most of it"
    static let firstRunStep2 = "Plug in your iPhone with a cable"
    static let firstRunStep3 = "Drop a game. The first one takes 10–40 minutes."
    static let firstRunCTA = "Set Up This Mac"
    static let firstRunDrop = "Drop a game"
    static let firstRunTypes = ".xci / .nsp · .iso (ps2)"

    // MARK: - Drag over

    static func dropTitle(_ n: Int) -> String { n == 1 ? "Drop to add 1 file" : "Drop to add \(n) files" }
    static let dropSubtitle = "Duo Builder reads them when you let go"
    static let dropKindGame = "game"
    static let dropKindGameOrUpdate = "game or update"
    static let dropKindUnsupported = "not a game file, left out"
    static let dropNoneTitle = "These aren't game files"
    static func dropBusy(_ game: String) -> String { "Wait for \(game) to finish" }
    static func dropQueued(_ n: Int) -> String { "\(n) more games added to your library" }

    // MARK: - Reading

    static let readingTitle = "Reading the game…"
    static func readingProgress(doneGB: String, totalGB: String, percent: Int) -> String {
        "\(doneGB) of ~\(totalGB) GB · \(percent)%"
    }
    static let readingFooter = "Finding the name, version and whether this build is known to work. Nothing leaves this Mac."
    static let commonCancel = "Cancel"

    // MARK: - Game card

    static func cardMeta(publisher: String, version: String, size: String) -> String {
        "\(publisher) · Version \(version) · \(size)"
    }
    static func cardMetaPS2(size: String) -> String { "Disc image · \(size)" }

    static let supportTested = "Tested with nxnative"
    static func supportOtherVersion(_ v: String) -> String { "Another version was tested (tested: \(v)) — likely works" }
    static let supportBringUp = "Still being brought up — may not start"
    static let supportNew = "New to nxnative — it may not start"

    static func chipGame(_ v: String) -> String { "Game \(v)" }
    static func chipUpdate(_ v: String) -> String { "Update \(v)" }
    static func chipDLC(_ n: Int) -> String { "DLC ×\(n)" }
    static let chipAddUpdate = "Add update"
    static func chipUpdateMismatch(_ v: String) -> String { "Update \(v) is for another game" }
    static let chipDisc = "Disc image"
    static let chipBios = "Your BIOS · from Setup"
    static let chipBiosMissing = "Needs your BIOS for .iso (ps2) · Add…"
    static let chipRemoveA11y = "Remove this file"

    static func cartLabel(_ n: Int) -> String { "This cartridge holds \(n) games:" }
    static let pictureDuoTitle = "Duo full screen (experimental)"
    static func pictureDuoBody(pack: String, author: String, note: String?) -> String {
        let tail = (note?.isEmpty == false) ? " \(note!)" : ""
        return "Uses the pack “\(pack)” by \(author).\(tail)"
    }
    static let pictureOriginalTitle = "Original shape"
    static let pictureOriginalBody = "Letterbox, crop or stretch can be changed while playing."
    static let pictureNoPack = "No Duo full-screen pack for this game yet. Letterbox, crop or stretch can be changed while playing."
    static let pictureNotDuo = "A Duo full-screen pack exists for this game; it applies when you install to an iPhone Duo. Letterbox, crop or stretch can be changed while playing."
    static let pictureAddPack = "Add a Pack…"

    static let nextLabel = "What happens next"
    static let nextPrepare = "1 · Prepare the graphics"
    static let nextPrepareTime = "10–40 minutes, first time only"
    static let nextPrepareCached = "Already prepared"
    static let nextBuild = "2 · Build the app"
    static func nextBuildTime(_ n: Int) -> String { "About \(n) minutes" }
    static func nextInstall(_ phone: String) -> String { "3 · Install on \(phone)" }
    static let nextInstallLastSlot = "Uses your last free slot (3 of 3)"
    static let nextInstallSlot = "Uses 1 of 3 free slots"
    static let nextCopy = "3 · Copy the game over"
    static func nextCopyBody(_ size: String) -> String { "\(size) by cable · keep it plugged in" }
    static let cardCached = "Already built on this Mac. Installing takes about a minute."
    static func roomTitle(_ phone: String) -> String { "Room on \(phone)" }
    static func roomBody(need: String, free: String) -> String { "Needs \(need) GB · \(free) GB free" }
    /// The first clause of `room.body`. The phone's free space cannot be measured through devicectl, so the card
    /// shows the requirement only (DESIGN-QUESTIONS Q5).
    static func roomNeeds(_ need: String) -> String { "Needs \(need) GB" }
    static func roomShort(phone: String, need: String, free: String) -> String {
        "\(phone) needs \(need) GB free. It has \(free) GB."
    }
    static func cardInstall(_ phone: String) -> String { "Install on \(phone)" }
    static let cardSetupAndInstall = "Set Up and Install"
    static let cardFooter = "Your files stay on this Mac. Cancel stops everything at any point."
    static func cardReasonMismatch(_ other: String) -> String {
        "Remove the update for another game to continue. It belongs to \(other)."
    }
    static let cardReasonMismatchUnknown = "Remove the update for another game to continue. It belongs to a different game."
    static let cardReasonNoPhone = "Plug in an iPhone to install."
    static let cardReasonNoKeys = "Add your prod.keys in Setup to install .xci / .nsp games."
    static let cardReasonNoBios = "Add your BIOS for .iso (ps2) in Setup to install .iso games."

    // MARK: - Setup sheet

    static let setupTitle = "Set up this Mac"
    static let setupTitleReady = "This Mac is ready"
    static func setupCount(done: Int, total: Int) -> String { "\(done) of \(total) ready" }
    static let setupSubAllAuto = "Duo Builder can do all of it for you."
    static func setupSubMixed(doing: Int, needYou: Int) -> String {
        "Duo Builder is doing \(doing) \(doing == 1 ? "step" : "steps") now. \(needYou) \(needYou == 1 ? "step needs" : "steps need") you."
    }
    static func setupSubNeeds(_ needYou: Int) -> String {
        "\(needYou) \(needYou == 1 ? "step needs" : "steps need") you."
    }
    static func setupDoneAbove(_ n: Int) -> String { "\(n) done above" }
    static let setupRunning = "Duo Builder is doing this one. Nothing to click."
    static func setupInstalling(_ percent: Int) -> String { "Installing · \(percent)%" }
    static let setupFixFailed = "That didn't work. Try again, or see what happened."
    static let setupShowWhat = "Show what happened"
    static let stepXcode = "Xcode"
    static let stepXcodeSetup = "Xcode first-time setup"
    static let stepCompiler = "Graphics compiler"
    static let stepCompilerNewer = "newer than the tested one"
    static let stepSDK = "iOS SDK"
    static let stepTools = "Build tools"
    static let stepDotnet = ".NET 10 SDK"
    static let stepPython = "Python environment"
    static let stepAppleID = "Apple ID in Xcode"
    static let stepAppleIDBody = "Sign in to your Apple ID in Xcode. A free one is enough."
    static let stepiPhone = "iPhone"
    static let stepiPhoneBody = "Plug it in with a cable. If the phone asks, tap Trust. This step finishes by itself."
    static let stepFiles = "Files from your own console"
    static let stepFilesRule = "· at least one"
    static let stepFilesBody = "Add the one for the games you have. You can add the other later."
    static let stepKeys = "Keys for .xci / .nsp"
    static let stepKeysBody = "prod.keys, for .xci / .nsp games"
    static let stepBios = "BIOS for .iso (ps2)"
    static let stepBiosBody = "your own BIOS, for .iso (ps2) games"
    static let stepSpace = "Free space"
    static func stepSpaceShort(_ n: String) -> String {
        "A build needs about 15 GB, mostly for Xcode's working files. This Mac has \(n) GB free."
    }
    static let actionFix = "Fix"
    static let actionFixPassword = "Fix…"
    static let actionAppStore = "App Store"
    static let actionOpenXcode = "Open Xcode"
    static let actionChoose = "Choose…"
    static let actionTryAgain = "Try Again"
    static let setupFooter = "You can close this. The install keeps going, and Duo Builder checks again next time."
    static let setupCheckAgain = "Check Again"
    static let setupDone = "Done"

    // MARK: - Working

    static func workMeta(picture: String, phone: String, elapsed: String) -> String {
        "\(picture) · to \(phone) · \(elapsed) so far"
    }
    static let workOverall = "overall"
    static let stageRead = "Read the game"
    static let stageReadActive = "Reading the game…"
    static let stageRewrite = "Rebuild the game's executable"
    static let stageGraphics = "Preparing the game's graphics"
    static let stageGraphicsPending = "Prepare the game's graphics"
    static let stageGraphicsHint = "the long one, 10–40 min"
    static let stageGraphicsNote = "This is the long one, 10–40 minutes, and only the first time."
    static let stageMemory = "Checking the game's memory layout"
    static let stageBuild = "Build the app for the phone"
    static let stagePack = "Pack the app"
    static func stageInstall(_ phone: String) -> String { "Install on \(phone)" }
    static let stageCopy = "Copying the game to the phone…"
    // The `.iso (ps2)` pipeline's nine stages (duo/ps2.md, docs/ARCHITECTURE.md §7.2).
    static let ps2StageDisc = "Reading the disc"
    static let ps2StageProgram = "Reading the game's program"
    static let ps2StageRebuild = "Rebuilding the game"
    static let ps2StageExplore = "Finding the code it uses"
    static let ps2StageGraphics = "Preparing its graphics code"
    static let ps2StageBuild = "Building the app"
    static let ps2StageCheck = "Checking the build"
    static func stageCopyDetail(done: String, total: String, rate: String) -> String {
        "\(done) of \(total) GB · \(rate) MB/s over the cable"
    }
    static func etaKnown(_ t: String) -> String { "about \(t) left" }
    static let etaUnknown = "time left: not known yet"
    static let workNext = "Next time this game installs in about a minute."
    static let workSafe = "Cancel stops everything. Nothing reaches the phone until the last step."
    static func copyKeep(_ phone: String) -> String { "Keep \(phone) plugged in and unlocked until this finishes." }
    static let copyAutolock = "If the screen locks, the copy pauses. Turn off auto-lock for now: Settings › Display & Brightness › Auto-Lock › Never. Set it back when you're done."
    static let copyRoomAfter = "Room left on the phone after this"
    static func copySlotsAfter(_ n: Int) -> String { "\(n) of 3 after this" }
    static let copyCancelNote = "Cancel removes the half-copied game from the phone."
    static let details = "Details"
    static let cancelConfirmTitle = "Stop preparing the graphics?"
    static let cancelConfirmBody = "You'll start from the beginning next time."

    // MARK: - Failed

    static let failTitle = "Install stopped"
    static func failSlotsFull(_ phone: String) -> String {
        "\(phone) already has 3 of your apps. A free Apple ID allows 3. The game is built and saved on this Mac, so nothing is lost."
    }
    static let failLadder = "What you can do"
    static let failMakeRoom = "Make room. Delete one of these from the iPhone's Home Screen, then Try Again."
    static let failEndsTomorrow = "ends tomorrow"
    static func failOtherPhone(_ phone: String) -> String { "Use another phone. \(phone) has free slots." }
    static let failOtherPhoneAction = "Choose Phone"
    static let failLater = "Keep it for later. It stays on your shelf and installs in about a minute."
    static let failPaidTip = "A paid Apple Developer account ($99 a year) removes the 3-app limit, and apps open for a year instead of 7 days."
    static let failPaidTipLink = "How to switch"
    static let failBack = "Back to Shelf"
    static let failRetry = "Try Again"
    static func failDeviceGone(_ phone: String) -> String { "\(phone) was unplugged. Plug it back in and Try Again." }
    static func failDeviceLocked(_ phone: String) -> String {
        "\(phone) locked while the game was copying. Unlock it, turn off auto-lock, and Try Again."
    }
    static func failDiskMac(_ n: String) -> String { "This Mac ran out of space. Free about \(n) GB, then Try Again." }
    static func failDiskPhone(_ phone: String, _ n: String) -> String { "\(phone) ran out of space. It needs \(n) GB more." }
    static func failAppIdLimit(_ date: String) -> String {
        "A free Apple ID allows 10 new apps a week. This one can install again on \(date)."
    }
    static func failUnknown(_ stage: String) -> String {
        "Something went wrong while \(stage). The details below say what happened."
    }
    static let failCopyDetails = "Copy Details"

    // MARK: - Done

    static func doneTitle(game: String, phone: String) -> String { "\(game) is on \(phone)" }
    static func doneRenewed(_ game: String) -> String { "\(game) is renewed" }
    static func doneFirst(_ t: String) -> String { "Took \(t). Next time: about a minute." }
    static func doneRenewLine(date: String, t: String) -> String { "It opens until \(date). Took \(t)." }
    static let doneTrustTitle = "One last step on the iPhone, this first time only"
    static let doneTrustBody = "Settings › General › VPN & Device Management › your Apple ID › Trust. Then open the game. The ⚙ button in the game has the picture and control settings."
    static let doneOpen = "Open it from the Home Screen. The ⚙ button in the game has the picture and control settings."
    static func doneSlots(phone: String, n: Int) -> String { "On \(phone) · \(n) of 3" }
    static let doneSlotsNote = "Each opens for 7 days. Renew from the shelf in about a minute."
    static func doneUntil(_ date: String) -> String { "Until \(date)" }
    static let doneReminder = "Remind me the day before a game stops opening"
    static let doneBack = "Back to Shelf"

    // MARK: - On this iPhone sheet

    static let phoneTitle = "On this iPhone"
    static func phoneSub(_ n: Int) -> String {
        "\(n) of 3 slots used. Renewing reuses the app already built, so the phone keeps your saves."
    }
    static func phoneRowDays(_ n: Int, date: String) -> String { "\(n) days · until \(date)" }
    static let phoneRowTomorrow = "Stops opening tomorrow"
    static let phoneReminder = "Remind me the day before a game stops opening"
    static let phoneAutoRenew = "Renew by itself when this iPhone is plugged in"
    static let phoneAutoRenewWhen = "· when 2 days or fewer are left"
    static func phoneWeekly(_ n: Int) -> String {
        "A free Apple ID also allows 10 new apps a week. Renewing does not use any. \(n) left this week."
    }
    static func phoneConnected(_ phone: String) -> String { "\(phone) is plugged in." }
    static let phoneClose = "Close"
    static func phoneRenewAll(_ n: Int) -> String { "Renew All · about \(n) min" }

    // MARK: - Notifications and menus

    static func notifExpiry(game: String, phone: String) -> String {
        "\(game) stops opening tomorrow. Plug in \(phone) and renew — it takes about a minute."
    }
    static let notifExpiryAction = "Renew"
    static func notifDone(game: String, phone: String) -> String { "\(game) is on \(phone)." }
    static let menuAddGame = "Add Game…"
    static func menuInstall(_ phone: String) -> String { "Install on \(phone)" }
    static let menuShowInFinder = "Show in Finder"
    static let menuRemoveFromLibrary = "Remove from Library"
    static let menuDeletePrepared = "Delete Prepared Graphics"
    static let menuOpenCard = "Open Card"
    static let menuRenewAll = "Renew All"
    static let menuSetup = "Setup…"
    static let menuHelpLimits = "About Free Apple ID Limits"

    // MARK: - Strings the spec states that COPY.md does not list

    /// §6.02: "if the file moved, show the card with a 'Locate…' chip instead of the file chips".
    static let locateChip = "Locate…"
    /// §7.3: the slot card's context menu item. The copy deck lists the library tile's "Show in Finder" but not this one.
    static let menuShowInLibrary = "Show in Library"
    /// §6.07: the pack picker's button text (same as picture.addPack, kept separate for the static panel).
    static let addPack = pictureAddPack

    // MARK: - Formatting

    /// "Sat, Nov 7" — the pack's short weekday form.
    static func date(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    /// Time left as the design counts it: "52s", "14m 32s".
    static func duration(_ seconds: Double) -> String { StageCopy.duration(seconds) }

    /// Per-stage elapsed as drawn in screens 12/13: "0m 42s", "1m 10s".
    static func stageElapsed(_ seconds: Double) -> String {
        let s = Int(max(seconds, 0).rounded())
        return String(format: "%dm %02ds", s / 60, s % 60)
    }

    /// Whole days left, rounded down, from an expiry date (§10).
    static func daysLeft(until expiry: Date, now: Date = Date()) -> Int {
        max(0, Int(floor(expiry.timeIntervalSince(now) / 86_400)))
    }
}
