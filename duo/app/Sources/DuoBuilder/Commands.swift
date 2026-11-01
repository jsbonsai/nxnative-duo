import SwiftUI

/// The menu bar of IMPLEMENTATION.md §7.1. Two Help items ("Duo Builder Help", "About free Apple ID limits") are
/// not built: the app has no help content to open (DESIGN-QUESTIONS Q8), and inventing a page would break the rule.
struct DuoCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(Copy.menuAddGame) { model.choosePackages() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isWorkingPhase)
            Button(Copy.cardInstall(model.phoneName)) { model.install() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canInstallNow)
            Button(Copy.menuShowInFinder) { model.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.isCardPhase)
            Button(Copy.menuRemoveFromLibrary) { model.removeActiveFromLibrary() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.activeEntryID == nil || model.isWorkingPhase)
            Divider()
            Button(Copy.commonCancel) { model.requestCancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isWorkingPhase && !model.isReadingPhase)
        }

        CommandMenu("Phone") {
            ForEach(Array(model.phones.devices.prefix(9).enumerated()), id: \.element.id) { index, device in
                Button(device.connected ? device.name : Copy.deviceDisconnected(device.name)) {
                    model.phones.choose(device)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .disabled(!device.connected)
            }
            if !model.phones.devices.isEmpty { Divider() }
            Button(Copy.deviceMenuOnThisPhone) {
                model.showRenew = true
                model.installs.refresh(root: model.root)
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!model.installs.available || model.phones.knownDevice == nil)
            Button(Copy.menuRenewAll) { model.renewAll() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.phones.device == nil || (model.selectedInstalls?.apps.isEmpty ?? true))
        }

        CommandGroup(after: .windowList) {
            Button(Copy.menuSetup) { model.openSetup(target: "device") }
                .keyboardShortcut(",", modifiers: .command)
        }
    }
}
