# Duo Builder — copy deck (Shelf redesign)

Register (DESIGN.md §9): second person, present tense, short sentences. Say the number when there is one; "about"
only for estimates. Never blame the user or the phone; name the next action. No exclamation marks, no marketing
adjectives, no emoji in chrome. Never "provisioning profile", "entitlement", "NSP", "shader".

`<game>`, `<phone>`, `<n>`, `<date>` etc. are placeholders. Dates use the short weekday form: "Sat, Nov 7".

## Top bar and status strip

| Key | String |
|---|---|
| device.none | No iPhone yet |
| device.disconnected | `<phone>` (not connected) |
| device.menu.onThisPhone | On This iPhone… |
| device.menu.newPhone | Set Up a New iPhone… |
| back.library | Library |
| status.ready | This Mac is ready |
| status.free | · `<n>` GB free |
| status.todo.one | 1 thing to set up |
| status.todo.many | `<n>` things to set up |
| status.checking | Checking this Mac… |
| status.setupLink | Setup |
| status.notAffiliated | Not affiliated with Nintendo |

## Home

| Key | String |
|---|---|
| home.slots.title | On this iPhone |
| home.slots.count | `<used>` of 3 apps · free Apple ID |
| home.slots.firstRun | A free Apple ID gives you 3 slots, 7 days at a time |
| slot.placeholder | Slot `<n>` |
| slot.daysLeft | `<n>` days left |
| slot.oneDayLeft | 1 day left |
| slot.expiresTomorrow | Expires tomorrow |
| slot.expired | Expired — renew to open it again |
| slot.renew | Renew |
| slot.free.title | Free slot |
| slot.free.body | Install a game to use it |
| home.library.title | Library |
| home.library.count | `<n>` games · `<k>` reinstall in about a minute |
| tile.add | Add Game… |
| tile.add.hint | Or drop .nsp, .xci or .iso anywhere |
| tile.ready | Ready · about 1 min |
| tile.notBuilt | Not built yet |
| tile.onPhone | On `<phone>` |
| tile.new | New to nxnative |
| tile.bringUp | May not start |
| tile.ps2 | PS2 |
| firstRun.title | Your game, on your phone. |
| firstRun.body | Drop a game you dumped yourself. Duo Builder turns it into an app on your iPhone. Your files stay on this Mac. |
| firstRun.step1 | Set up this Mac — Duo Builder does most of it |
| firstRun.step2 | Plug in your iPhone with a cable |
| firstRun.step3 | Drop a game. The first one takes 10–40 minutes. |
| firstRun.cta | Set Up This Mac |
| firstRun.drop | Drop a game |
| firstRun.types | .nsp · .xci · .iso |

## Drag over

| Key | String |
|---|---|
| drop.title.one | Drop to add 1 file |
| drop.title.many | Drop to add `<n>` files |
| drop.subtitle | Duo Builder reads them when you let go |
| drop.kind.game | game |
| drop.kind.gameOrUpdate | game or update |
| drop.kind.unsupported | not a game file, left out |
| drop.none.title | These aren't game files |
| drop.busy | Wait for `<game>` to finish |
| drop.queued | `<n>` more games added to your library |

## Reading

| Key | String |
|---|---|
| reading.title | Reading the game… |
| reading.progress | `<done>` of ~`<total>` GB · `<pct>`% |
| reading.footer | Finding the name, version and whether this build is known to work. Nothing leaves this Mac. |
| common.cancel | Cancel |

## Game card

| Key | String |
|---|---|
| card.meta | `<publisher>` · Version `<v>` · `<size>` |
| card.meta.ps2 | Disc image · `<size>` |
| support.tested | Tested with nxnative |
| support.otherVersion | Another version was tested (tested: `<v>`) — likely works |
| support.bringUp | Still being brought up — may not start |
| support.new | New to nxnative — it may not start |
| chip.game | Game `<v>` |
| chip.update | Update `<v>` |
| chip.dlc | DLC ×`<n>` |
| chip.addUpdate | Add update |
| chip.updateMismatch | Update `<v>` is for another game |
| chip.disc | Disc image |
| chip.bios | Your BIOS · from Setup |
| chip.biosMissing | Needs your PS2 BIOS · Add… |
| chip.remove.a11y | Remove this file |
| cart.label | This cartridge holds 2 games: |
| picture.duo.title | Duo full screen (experimental) |
| picture.duo.body | Uses the pack "`<pack>`" by `<author>`. `<pack note>` |
| picture.original.title | Original shape |
| picture.original.body | Letterbox, crop or stretch can be changed while playing. |
| picture.noPack | No Duo full-screen pack for this game yet. Letterbox, crop or stretch can be changed while playing. |
| picture.notDuo | A Duo full-screen pack exists for this game; it applies when you install to an iPhone Duo. Letterbox, crop or stretch can be changed while playing. |
| picture.addPack | Add a Pack… |
| next.label | What happens next |
| next.prepare | 1 · Prepare the graphics |
| next.prepare.time | 10–40 minutes, first time only |
| next.prepare.cached | Already prepared |
| next.build | 2 · Build the app |
| next.build.time | About `<n>` minutes |
| next.install | 3 · Install on `<phone>` |
| next.install.lastSlot | Uses your last free slot (3 of 3) |
| next.install.slot | Uses 1 of 3 free slots |
| next.copy | 3 · Copy the game over |
| next.copy.body | `<size>` by cable · keep it plugged in |
| card.cached | Already built on this Mac. Installing takes about a minute. |
| room.title | Room on `<phone>` |
| room.body | Needs `<need>` GB · `<free>` GB free |
| room.short | `<phone>` needs `<need>` GB free. It has `<free>` GB. |
| card.install | Install on `<phone>` |
| card.setupAndInstall | Set Up and Install |
| card.footer | Your files stay on this Mac. Cancel stops everything at any point. |
| card.reason.mismatch | Remove the update for another game to continue. It belongs to `<other game>`. |
| card.reason.mismatchUnknown | Remove the update for another game to continue. It belongs to a different game. |
| card.reason.noPhone | Plug in an iPhone to install. |
| card.reason.noKeys | Add your Switch keys in Setup to install Switch games. |
| card.reason.noBios | Add your PS2 BIOS in Setup to install PS2 games. |

## Setup sheet

| Key | String |
|---|---|
| setup.title | Set up this Mac |
| setup.title.ready | This Mac is ready |
| setup.count | `<done>` of `<total>` ready |
| setup.sub.allAuto | Duo Builder can do all of it for you. |
| setup.sub.mixed | Duo Builder is doing `<a>` step now. `<b>` steps need you. |
| setup.sub.needs | `<b>` steps need you. |
| setup.doneAbove | `<n>` done above |
| setup.running | Duo Builder is doing this one. Nothing to click. |
| setup.installing | Installing · `<pct>`% |
| setup.fixFailed | That didn't work. Try again, or see what happened. |
| setup.showWhat | Show what happened |
| step.xcode | Xcode |
| step.xcodeSetup | Xcode first-time setup |
| step.compiler | Graphics compiler |
| step.compiler.newer | newer than the tested one |
| step.sdk | iOS SDK |
| step.tools | Build tools |
| step.dotnet | .NET 10 SDK |
| step.python | Python environment |
| step.appleId | Apple ID in Xcode |
| step.appleId.body | Sign in to your Apple ID in Xcode. A free one is enough. |
| step.iphone | iPhone |
| step.iphone.body | Plug it in with a cable. If the phone asks, tap Trust. This step finishes by itself. |
| step.files | Files from your own console |
| step.files.rule | · at least one |
| step.files.body | Add the one for the games you have. You can add the other later. |
| step.keys | Switch keys |
| step.keys.body | prod.keys, for .nsp and .xci games |
| step.bios | PS2 BIOS |
| step.bios.body | your own BIOS, for .iso games |
| step.space | Free space |
| step.space.short | A build needs about 15 GB, mostly for Xcode's working files. This Mac has `<n>` GB free. |
| action.fix | Fix |
| action.fixPassword | Fix… |
| action.appStore | App Store |
| action.openXcode | Open Xcode |
| action.choose | Choose… |
| action.tryAgain | Try Again |
| setup.footer | You can close this. The install keeps going, and Duo Builder checks again next time. |
| setup.checkAgain | Check Again |
| setup.done | Done |

## Working

| Key | String |
|---|---|
| work.meta | `<picture>` · to `<phone>` · `<elapsed>` so far |
| work.overall | overall |
| stage.read | Read the game |
| stage.read.active | Reading the game… |
| stage.rewrite | Rebuild the game's executable |
| stage.graphics | Preparing the game's graphics |
| stage.graphics.pending | Prepare the game's graphics |
| stage.graphics.hint | the long one, 10–40 min |
| stage.graphics.note | This is the long one, 10–40 minutes, and only the first time. |
| stage.memory | Checking the game's memory layout |
| stage.build | Build the app for the phone |
| stage.pack | Pack the app |
| stage.install | Install on `<phone>` |
| stage.copy | Copying the game to the phone… |
| stage.copy.detail | `<done>` of `<total>` GB · `<rate>` MB/s over the cable |
| eta.known | about `<t>` left |
| eta.unknown | time left: not known yet |
| work.next | Next time this game installs in about a minute. |
| work.safe | Cancel stops everything. Nothing reaches the phone until the last step. |
| copy.keep | Keep `<phone>` plugged in and unlocked until this finishes. |
| copy.autolock | If the screen locks, the copy pauses. Turn off auto-lock for now: Settings › Display & Brightness › Auto-Lock › Never. Set it back when you're done. |
| copy.roomAfter | Room left on the phone after this |
| copy.slotsAfter | `<n>` of 3 after this |
| copy.cancelNote | Cancel removes the half-copied game from the phone. |
| details | Details |
| cancel.confirm.title | Stop preparing the graphics? |
| cancel.confirm.body | You'll start from the beginning next time. |

## Failed

| Key | String |
|---|---|
| fail.title | Install stopped |
| fail.slotsFull | `<phone>` already has 3 of your apps. A free Apple ID allows 3. The game is built and saved on this Mac, so nothing is lost. |
| fail.ladder | What you can do |
| fail.makeRoom | Make room. Delete one of these from the iPhone's Home Screen, then Try Again. |
| fail.endsTomorrow | ends tomorrow |
| fail.otherPhone | Use another phone. `<phone>` has free slots. |
| fail.otherPhone.action | Choose Phone |
| fail.later | Keep it for later. It stays on your shelf and installs in about a minute. |
| fail.paidTip | A paid Apple Developer account ($99 a year) removes the 3-app limit, and apps open for a year instead of 7 days. |
| fail.paidTip.link | How to switch |
| fail.back | Back to Shelf |
| fail.retry | Try Again |
| fail.deviceGone | `<phone>` was unplugged. Plug it back in and Try Again. |
| fail.deviceLocked | `<phone>` locked while the game was copying. Unlock it, turn off auto-lock, and Try Again. |
| fail.diskMac | This Mac ran out of space. Free about `<n>` GB, then Try Again. |
| fail.diskPhone | `<phone>` ran out of space. It needs `<n>` GB more. |
| fail.appIdLimit | A free Apple ID allows 10 new apps a week. This one can install again on `<date>`. |
| fail.unknown | Something went wrong while `<stage>`. The details below say what happened. |
| fail.copyDetails | Copy Details |

## Done

| Key | String |
|---|---|
| done.title | `<game>` is on `<phone>` |
| done.renewed | `<game>` is renewed |
| done.first | Took `<t>`. Next time: about a minute. |
| done.renewLine | It opens until `<date>`. Took `<t>`. |
| done.trust.title | One last step on the iPhone, this first time only |
| done.trust.body | Settings › General › VPN & Device Management › your Apple ID › Trust. Then open the game. The ⚙ button in the game has the picture and control settings. |
| done.open | Open it from the Home Screen. The ⚙ button in the game has the picture and control settings. |
| done.slots | On `<phone>` · `<n>` of 3 |
| done.slots.note | Each opens for 7 days. Renew from the shelf in about a minute. |
| done.until | Until `<date>` |
| done.reminder | Remind me the day before a game stops opening |
| done.back | Back to Shelf |

## On this iPhone sheet

| Key | String |
|---|---|
| phone.title | On this iPhone |
| phone.sub | `<n>` of 3 slots used. Renewing reuses the app already built, so the phone keeps your saves. |
| phone.row.days | `<n>` days · until `<date>` |
| phone.row.tomorrow | Stops opening tomorrow |
| phone.reminder | Remind me the day before a game stops opening |
| phone.autoRenew | Renew by itself when this iPhone is plugged in |
| phone.autoRenew.when | · when 2 days or fewer are left |
| phone.weekly | A free Apple ID also allows 10 new apps a week. Renewing does not use any. `<n>` left this week. |
| phone.connected | `<phone>` is plugged in. |
| phone.close | Close |
| phone.renewAll | Renew All · about `<n>` min |

## Notifications and menus

| Key | String |
|---|---|
| notif.expiry | `<game>` stops opening tomorrow. Plug in `<phone>` and renew — it takes about a minute. |
| notif.expiry.action | Renew |
| notif.done | `<game>` is on `<phone>`. |
| menu.addGame | Add Game… |
| menu.install | Install on `<phone>` |
| menu.showInFinder | Show in Finder |
| menu.removeFromLibrary | Remove from Library |
| menu.deletePrepared | Delete Prepared Graphics |
| menu.openCard | Open Card |
| menu.renewAll | Renew All |
| menu.setup | Setup… |
| menu.help.limits | About Free Apple ID Limits |
