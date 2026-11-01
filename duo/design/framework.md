# Duo porting framework — vision

Not a mandate to build. This records the shape we want so the per-game work we are
already doing (profiles, aspect stubs, settings) accumulates into something other
people can reuse instead of a pile of one-off patches.

## The problem this solves

Today a port is: a profile (`dm/games/<id>/`), an aspect site table (`duo/research/games.tsv`),
a handful of settings, and a build. That works, but every new game re-derives the same
questions — where is the camera aspect produced, which settings can change live, what
does the HUD do on a non-16:9 panel. The framework is the answer key, not new
machinery.

## Layers

```
┌─────────────────────────────────────────────┐
│ Duo shell        layout modes, overlays,    │  iOS front end (Swift/UIKit)
│                  plugins, input routing     │
├─────────────────────────────────────────────┤
│ Device profile   panel metrics, hinge,      │  duo/device/*.tsv
│                  safe areas, orientation    │
├─────────────────────────────────────────────┤
│ Game profile     constants, shaders,        │  dm/games/<id>/
│                  per-build cuts, aspect     │
├─────────────────────────────────────────────┤
│ Host             Horizon services, NVN,     │  dm/host, dm/gfx
│                  Metal present              │
└─────────────────────────────────────────────┘
```

Everything game-specific stays in the game profile; everything device-specific in the
device profile; the shell only knows geometry and policy.

## Porting baseline (the checklist we already follow)

1. **Survey** — `nx survey`: modules, SDK, engine, shader source, imports vs hooks.
2. **Provisional profile** — `nx mac`: does it boot on the Mac? (Scott Pilgrim: 2,400
   frames on the first try.)
3. **Promote** — copy the profile into the repo, rewrite the header with what was
   actually verified.
4. **Aspect sites** — find the `fdiv`/`ldr` that feeds the projection and the viewport
   division (`duo/DESIGN.md`), add a row to `duo/research/games.tsv`.
5. **Settings** — which are live (state page) and which need a restart
   (`duo/design/ingamemenu.md`).
6. **Controls** — pad layout, touch ownership, controller mapping.
7. **Test matrix** — device modes × orientation × controller attached.

A port is "supported" when 1–7 are done and a device run is recorded in `duo/games/`.

## Device modes

| Mode | Picture | Controls | Notes |
|---|---|---|---|
| **Full** | whole panel, camera takes its aspect | overlay pad | what `DM_ASPECT=fill` + aspect stubs do now |
| **Dual** | top half | bottom half | hinge-aware; numbers in `duo/design/dualscreen.md` (669×951 pt panel → 669×475.5 halves) |
| **Outer / cover** | small panel | compact pad or controller | 1398×2034 px cover display |
| **Partial fold** | top half | bottom half, 24 pt gap | `UIHinge.status` / `angle` (iOS 27), bounds-change fallback |
| **Docked** | external display | controller | present to an external scene |

The shell picks the mode from hinge state + orientation + whether a controller is
connected, and the player can pin one in settings.

## Overlays and plugins

The game view is a `CAMetalLayer`; anything above it is ordinary UIKit. That is the
whole opening: a plugin is a view plus an audio policy, hosted by the shell.

### Sketch

```swift
protocol DuoPlugin {
    var id: String { get }
    var preferredSize: CGSize { get }          // points, shell clamps
    var audioPolicy: AudioPolicy { get }       // mix / duck / exclusive
    func makeView() -> UIView
    func activate() / deactivate()
}
```

Built-in plugins: settings (the in-game menu), FPS/HUD, and a media player.

### Media while playing — what iOS actually allows

- **Apple Music** — `MusicKit`/`MPMusicPlayerController` can play and expose controls;
  artwork and metadata are available. This is the cleanest integration.
- **Spotify** — the Spotify iOS SDK (or Web API + remote control) gives playback
  control, not an embeddable UI. Needs the user's account and app registration.
- **YouTube** — only through the official iframe player in a `WKWebView` (ToS requires
  the official player and its ads). Not a raw video URL.
- **Arbitrary apps** — impossible. iOS has no window embedding; you cannot host
  Spotify's or YouTube's app UI inside ours. Only system PiP of *our own* video, or the
  services' SDKs.
- **Audio** — the game owns an audio session. A media plugin must either mix (both play,
  `AVAudioSessionCategoryPlayback` + `.mixWithOthers`) or duck the game (lower the
  host's audio volume while the player speaks). Exclusive playback would silence the
  game; the shell should refuse that combination.
- **Layout** — the "controls to the sides, player in the middle" idea is a shell layout:
  game picture top, pad split left/right edges, player card centre-bottom. All of it is
  geometry the shell already owns; the game never knows.

### Why not ship this first

Every plugin adds an audio session interaction and an input-routing edge case. The
in-game settings overlay (`duo/design/ingamemenu.md`) is the necessary first plugin —
it proves the overlay host, input gating and live settings path. Media plugins come
after that is stable on a device.

## Roadmap

1. **Overlay host + settings plugin** — from `ingamemenu.md`; live fps/render-scale/aspect.
2. **Dual-screen mode** — from `dualscreen.md`; hinge-aware, portrait enabled.
3. **Device profile table** — panel/hinge/safe-area numbers per device, so a second
   foldable is data, not code.
4. **Media plugin API** — Apple Music first (least friction), then Spotify; YouTube last
   (ToS and DRM).
5. **Porting template** — `duo/PORTING.md` generated from the checklist above, with the
   survey/verification commands.

## Non-goals

- Embedding other apps' UIs (not possible on iOS).
- DRM video from Netflix/Disney+ inside the shell.
- A plugin store, sandboxing, or third-party code loading in v1.
- Changing game behaviour from the shell beyond the documented state-page switches.
