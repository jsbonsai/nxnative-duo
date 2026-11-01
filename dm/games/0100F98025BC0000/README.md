# Toy Story: Retro Roundup! (`0100F98025BC0000`)

Update 1.0.4 (v262144, `main` `c41be91d…`), SDK **21.4.4**. The second application on the Toy Story double-pack cartridge (`01001DC025BC4000`, beside Toy Story 3 Complete Edition): the NSP script picks it with `--title-id 0100F98025BC0000` (`NX_TITLE` for the tools), and the update NSP is `0100F98025BC0800`. Extracting needs `prod.keys` with `master_key_15`.

A Digital Eclipse collection of Toy Story games emulated in an engine of its own: Genesis, SNES and Game Boy ROMs and replays under `assets/`, four PlayStation discs under `pancake/`, played by the `pancake` libretro core (`nro/pancake_libretro_nx.nro`) with an AOT-compiled MIPS module per disc (`nro/libmipsaot-SLUS*.nro`). It renders with **OpenGL**, not NVN: `main` imports the EGL functions and takes every GL function from `eglGetProcAddress` (a 4.5 core context), which the host's GL layer answers on Metal. Modules `main`, `subsdk1` (`NintendoSDK_movie`), `subsdk2` (GLSLC) and `sdk`; `subsdk0` (NVIDIA's GL driver) is never loaded.

On the Mac: the Digital Eclipse logo, the title, the EULA, the main menu (Woody, Bullseye and the attract replay on the TV), the game list and the Genesis **Toy Story** (save slot, Traveller's Tales logo, the first level, played) at 60 fps, with no `[RED]` line. The PlayStation games abort when their core starts (see [Open](#open)).

## What it needs

| Setting | Where | Why |
|---|---|---|
| SDK 21.4.4's AddressRegionManager node area 1 GB → 62 MB | `dm/tools/sdk_patches.py` SDK-wide rule, `sdk` build `14839413…` (the constructor at `sdk+0x14fbe0`, cuts at `+0x14fbf0` / `+0x14fc5c`) | without it `StandardAllocator::Initialize` aborts in `nninitStartup`; see [Memory](#memory) |
| `sys_resource 0x200000`; 5 GB block: `mem_reserve 0x140000000`, `mem_alias 0x118000000`, `mem_stack 0x10000000`, `app_pool 0xCD500000` | [`game.tsv`](game.tsv) | the NPDM's 2 MB of system resource: virtual address memory, no heap; Engage's block (256 MB in front + 4.375 GB alias region + 256 MB stack region + 128 MB heap region) |
| No `stdalloc_cap` | `game.tsv` | the host's default gives malloc's 7.91 GB request 4.06 GB, which holds everything the game maps (0.5 GB) |
| `modules main subsdk1 subsdk2 sdk` | `game.tsv` | the GL layer answers `main`'s EGL imports, so `subsdk0` stays unloaded |
| `shader_groups …`, empty NVN tables | `game.tsv`, the tables | no NVN shaders: the GL library comes from `gl_shaders.py` (the RomFS's `.shader` files and `main`'s strings) |

## Memory

- The NPDM declares 2 MB of system resource, so `IsVirtualAddressMemoryEnabled` is true, and `main` never sets a heap. `nninitStartup`'s malloc setup (`main+0x7e70`) calls `StandardAllocator::Initialize(nullptr, 0x1fa000000)` through `main+0x2c8b00`: a fixed **7.91 GB** of address space, sized for the Switch's 64 GB alias region.
- **Resolved: `nn::diag` abort with Result 0 at `sdk+0x141b9c`** (backtrace `sdk+0x141b9c main+0x2c8b3c main+0x7e88`; the abort right after `CentralHeap::Init(nullptr, size)` fails in `StandardAllocator::Initialize`, `sdk+0x141ac0`). The host's gate lowered the request to 4.06 GB, the alias region less the 62 MB node area and 256 MB for later regions, but no SDK-wide implementation of the node-area cut matched this `sdk` build, so the AddressRegionManager kept its 1 GB node area and the 4.06 GB region did not fit after it. The constructor is SDK 22.2.0's form (the same 276 bytes and cut offsets, another fingerprint), now a fingerprint of the SDK-wide rule's sixth implementation ([The SDK's address-region node area](../../../docs/reference/memory.md#the-sdks-address-region-node-area)). `VammManager::AllocateAddressRegion` (`sdk+0x14fd00`) aligns to 64 KB or 2 MB only, so there is no alignment cut. The region is now at alias +0.06 GB.
- The game does not need the 7.91 GB: booted with a Switch-sized alias region (`DM_ALIAS_SIZE=0x1000000000`) it gets all of it at the same place and, 40 s in (the title), has mapped 0.30 GB against 0.29 GB with the 4.06 GB region (2,304 against 2,307 draws in the 300 frames to frame 2,400). It maps the region's last pages at boot (the alias high-water mark at the region's end right after `nnMain`: +4.12 GB, or +7.97 GB with the full size), 0.29 GB by the title and 0.50 GB through the menus and the Genesis game. On the Mac about 0.65 GB is resident and 0.2 GB is Metal allocations.
- **iPhone:** the game fits Engage's 5 GB block, the total proven on phones without the extended virtual addressing entitlement, so the app needs no entitlement change. Giving it the Switch's 7.91 GB would take a guest block over the 6 GB single reservation iOS allows without that entitlement, and Apple's capability table lists Extended Virtual Addressing for the paid programs only (Apple Developer Program, Enterprise), not for a free Apple ID's Personal Team ([Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)).

## Rendering (OpenGL)

- **Uniform buffers:** every constant buffer is a named uniform block the game fills with `glBufferSubData` and binds with `glBindBufferRange`; varyings are placed by location; a texture read with `textureSize` has a second combined sampler at its binding. Before the layer had them, all draws were dropped: [GL uniform buffers and HLSL-made GLSL](../../../docs/reference/rendering.md#gl-uniform-buffers-and-hlsl-made-glsl).
- **`eglQuerySurface`** for the window's width and height right after `eglCreateWindowSurface`; without it the game jumped to address 0 (`lr=main+0x6ca84`, `UNIMPL eglQuerySurface`).
- **Stencil per face:** `glStencilFuncSeparate` / `glStencilOpSeparate` with `GL_FRONT` (the layer keeps one state for both faces).

## Shaders

- 33 RIFF `SHDR` files in `assets/shaders` (each a vertex and a fragment shader in its `gl  ` chunk, HLSL through SPIRV-Cross) and 3 strings in `main`: 56 shaders. A `DM_GL_CAPTURE` run over the title, the menus and the Genesis game compiled 41 sources, all among them.
- The `pancake` core puts its PlayStation renderer's shaders together at run time (`#define CONFIG_… %d` headers in `nro2`); none is in the library yet.

## Open

- **The PlayStation games abort when the core starts** (A Bug's Life checked; the other three discs, Buzz Lightyear of Star Command, Toy Story 2 and Toy Story Racer, go through the same core): `ProgramPipelineGL.h(48): ABORT: Failed to link shader program` from `nro2+0x1c5880`, after `[RED] glCreateShaderProgramv`, `glCreateProgramPipelines`, `glCreateBuffers`, `glNamedBufferStorage` and `glMapNamedBufferRange` (stubs). The core's hardware renderer uses separable program pipelines, direct-state-access buffers, compute shaders with `imageStore`, a geometry shader for lines and `GL_ARB_fragment_shader_interlock`; the GL layer has none of them.
- **The SNES game:** started from PLAY! once, its TV was still black 12 s later, with no `[RED]` line and no crash; not followed further. The Game Boy game, the museum, the music player, the settings and the save flow are unverified; only the Genesis game was played.
- **iPhone Duo (iPhone19,4, iOS 27.2), 2026-10-31:** built with Duo Builder (`duo build`, the cartridge with the 1.0.4 update, `--title-id` picked from the update) and played by the owner: "plays perfectly, no issues, vids and gameplay audio 10/10". The PlayStation games were not tried on the phone.
