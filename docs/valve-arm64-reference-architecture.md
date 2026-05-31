# Valve-Style ARM64 Proton Reference Architecture

## 1. Purpose

This document defines the tracer-bullet architecture for moving Razorfin ARM away from its current "run Steam under FEX" model and toward the architecture implied by Valve's public ARM64 Proton work.

The goal is not to wait for every upstream edge to be polished. The goal is to build a coherent reference implementation now, learn from it quickly, and carry the operational burden while the stack matures.

## 2. Product Bet

Razorfin ARM will treat the following as the desired end-state, even while upstream pieces are still beta:

- **ARM-native host OS**
- **ARM-native Steam runtime stack**
- **ARM-native Proton launcher and Wine host binaries**
- **FEX embedded inside Proton/Wine for WOW64 and ARM64EC execution**
- **Native ARM64 Vulkan/OpenGL host libraries**
- **Containerized game execution via Valve-style Steam Linux Runtime**

In short:

```text
ARM Linux
  -> ARM Steam / launch orchestration
  -> Steam Linux Runtime 4 (ARM64)
  -> Proton 11 ARM64
  -> ARM64 Wine host binaries
  -> FEX WOW64 / ARM64EC backend
  -> Windows game
```

This is the architecture Razorfin will optimize for, document, and test first.

## 3. Current vs Target

### 3.1 Current Razorfin ARM

Today Razorfin primarily works like this:

```text
ARM Linux
  -> FEX usermode Linux emulation
  -> x86/x86_64 Steam client
  -> Proton
  -> Windows game
```

Characteristics of the current model:

- Steam itself is launched through `razorfin-steam`
- FEX rootfs and Linux-side thunks are configured system-wide
- FEX AppConfig profiles are installed globally
- The game path depends on the same general-purpose FEX stack that also runs other x86 Linux applications

### 3.2 Target Razorfin ARM

The target model separates the Steam client problem from the Windows game execution problem and optimizes the latter around Valve's current upstream direction:

```text
ARM Linux
  -> ARM launch/runtime layer
  -> Steam Linux Runtime 4 (ARM64)
  -> Proton 11 ARM64
  -> Wine aarch64 host binaries
  -> FEX ARM64EC / WOW64 backend
  -> Windows game
```

Characteristics of the target model:

- Proton is an ARM64 compatibility tool, not an x86 tool running under Linux FEX
- FEX is used as a Wine backend for Windows code execution, not as the outermost Linux process wrapper
- Native ARM64 host graphics libraries are preferred over Linux-side x86 thunking
- Runtime/container behavior should look as close as possible to Valve's public Steam Runtime layout

## 4. Architecture Principles

### 4.1 Valve First

If Valve has a public ARM64 runtime or Proton artifact, Razorfin should consume or emulate that model before inventing a different abstraction.

### 4.2 Games First

The primary success metric is "Windows games launch and run through the Valve-style ARM64 path." Running the Steam desktop client natively is desirable but not required for the first tracer bullet.

### 4.3 Keep FEX, Change Where It Lives

FEX remains strategic. What changes is its role:

- **Current role:** outer Linux application emulator
- **Target role:** inner Wine execution backend for x86/x86_64 Windows code

### 4.4 Reference Architecture Over Convenience

If a shortcut keeps us on the old architecture, it is not part of the tracer bullet. The tracer bullet exists to validate the target design, not to preserve compatibility with the incumbent stack.

## 5. Scope

### 5.1 In Scope

- Establishing a canonical Valve-style ARM64 Proton execution path
- Staging or packaging the required ARM64 Proton and runtime assets
- Defining the host requirements for Fedora COSMIC Atomic
- Wiring launch orchestration around ARM64 Proton, ARM64 runtime, and compatdata
- Choosing the filesystem layout and ownership boundaries for those assets
- Building a validation matrix for representative Windows games

### 5.2 Out of Scope for the First Tracer Bullet

- Full replacement of all x86 Linux application support
- Removal of all existing FEX packages from the image
- Perfect migration of every current per-game FEX AppConfig quirk
- Broad support for non-Steam launchers
- Guaranteed support on every 16K/64K page-size board

## 6. Host Assumptions

The reference architecture assumes:

- Generic `aarch64` Fedora COSMIC Atomic host
- 4K page size preferred
- Mesa Vulkan available natively on ARM64
- Bubblewrap/container runtime assumptions compatible with Steam Linux Runtime
- Ability to stage Valve runtime artifacts under a stable local filesystem path

Known caveat:

- Some ARM boards with 16K or 64K pages may require degraded behavior or may fail entirely in the early tracer bullet.

## 7. Component Model

### 7.1 Host Layer

Responsibilities:

- ARM64 kernel and userspace
- Native GPU drivers and Vulkan loader
- Input, audio, Wayland/X11, controller stack
- Basic sysctl and limits tuning already used for gaming

Razorfin ownership:

- Keep the existing host tuning unless it directly conflicts with the new runtime model
- Prefer native ARM64 graphics/audio libraries over Linux x86 emulation paths

### 7.2 Runtime Layer

Responsibilities:

- Provide the ARM64 Steam Linux Runtime environment used to launch Proton
- Provide container entry points and runtime filesystem expectations

Reference source:

- Steam Linux Runtime 4 ARM64 public artifacts

Razorfin ownership:

- Decide whether to vendor, stage, or fetch runtime artifacts
- Normalize their install path on an immutable host
- Expose runtime diagnostics and log collection

### 7.3 Compatibility Tool Layer

Responsibilities:

- Provide Proton 11 ARM64 or newer ARM64 Proton builds
- Carry ARM64 Wine host binaries
- Carry FEX WOW64 and ARM64EC components within the Proton tool layout

Reference source:

- Valve's Proton ARM64 public tool structure

Razorfin ownership:

- Stage tool files in a layout compatible with Steam-style compatibility tools
- Control version pinning
- Expose tool metadata and channel policy

### 7.4 Launch Orchestration Layer

Responsibilities:

- Set `STEAM_COMPAT_*` paths correctly
- Select the runtime and Proton tool
- Create/manage compatdata
- Capture logs
- Be debuggable outside the Steam GUI if needed

Razorfin ownership:

- Provide a thin launcher or glue layer that models Steam's launch contract closely
- Minimize custom behavior beyond path selection, logging, and diagnostics

### 7.5 Game Prefix Layer

Responsibilities:

- Hold compatdata and prefixes per title
- Preserve prefix upgrades and versioning
- Store any per-title FEX/Proton config files if Proton expects them

Razorfin ownership:

- Define stable compatdata storage paths
- Make upgrades and cleanup observable
- Avoid bespoke state spread across unrelated directories

## 8. Proposed Filesystem Layout

The tracer bullet should standardize on a layout similar to:

```text
/usr/lib/razorfin/steam-arm/
  runtime/
    SteamLinuxRuntime_4-arm64/
  compatibilitytools.d/
    Proton-11.0-arm64/
  launchers/
    razorfin-steam-arm64
    razorfin-proton-arm64-run
```

User state should standardize on:

```text
~/.local/share/Steam/
~/.local/share/Steam/steamapps/compatdata/<appid>/
~/.local/share/Steam/compatibilitytools.d/   # if user overrides are allowed
```

Notes:

- The system image should own the default runtime/tool copies
- User-space overrides may still exist, but they should not be required for the reference path
- We should avoid scattering runtime pieces across both `/usr/share/fex-emu` and ad-hoc bootstrap directories when the target model no longer depends on Linux-side FEX rootfs execution

## 9. Packaging Strategy

### 9.1 Recommended Tracer-Bullet Strategy

Use a **staged artifact** model first:

- Ship a pinned ARM64 Steam Linux Runtime
- Ship a pinned ARM64 Proton tool
- Add Razorfin launch wrappers that bind the pieces together

Why:

- Fastest way to prove the architecture
- Keeps the design close to Valve's published artifact model
- Lets us validate behavior before deciding whether to repackage or rebuild components from source

### 9.2 Deferred Strategy

After the tracer bullet works, evaluate whether to:

- package Valve artifacts directly in Fedora/RPM form
- mirror them into a Razorfin content channel
- build selected components from source for provenance and tighter integration

## 10. Tracer-Bullet Phases

### Phase 0: Freeze the Target

Deliverables:

- This architecture doc
- Explicit agreement that the target path is ARM64 Proton-centric
- No new feature work that deepens dependence on `razorfin-steam` as the long-term architecture

Exit criteria:

- Team is aligned on "Valve-style ARM64 Proton is the primary design center"

### Phase 1: Artifact Staging

Deliverables:

- Deterministic install location for Steam Linux Runtime 4 ARM64
- Deterministic install location for Proton 11 ARM64
- Version manifest recording what is staged in the image

Exit criteria:

- Runtime and Proton tool are present on disk in a predictable layout
- We can inspect versions without launching a game

### Phase 2: Launch Harness

Deliverables:

- A Razorfin launcher that models Steam's expected environment for Proton
- Per-title compatdata creation
- Log collection path for runtime + Proton + launcher output

Exit criteria:

- We can launch at least one Windows title through the ARM64 Proton path reproducibly

### Phase 3: Steam Integration

Deliverables:

- Hook the tracer-bullet launcher into Steam-oriented workflows
- Make ARM64 Proton the default reference compatibility tool in Razorfin documentation
- Preserve debuggability from shell and desktop entry points

Exit criteria:

- A user can launch a target game through the new path without manual shell surgery

### Phase 4: Hardening

Deliverables:

- Validation matrix across representative games
- Known-issues list
- Performance comparison versus the current `razorfin-steam` path
- Decision on whether existing global FEX rootfs/thunk config remains necessary

Exit criteria:

- We know where the new path is better, worse, or incomplete
- We can decide whether to promote it from tracer bullet to default

## 11. First Implementation Slice

The first implementation slice should be intentionally narrow:

1. Stage one ARM64 runtime.
2. Stage one ARM64 Proton build.
3. Add one launcher that runs a Windows executable with Steam-style compat env.
4. Validate one known-good 64-bit title.
5. Capture logs and document the exact command contract.

This is enough to prove the architecture without prematurely solving every Steam UX detail.

## 12. Validation Matrix

The first validation matrix should include:

| Class | Why it matters |
|------|----------------|
| 64-bit DX11/DX12 game | Mainline ARM64EC path |
| 32-bit game | Exercises WOW64 path |
| Launcher-heavy title | Stress test for mixed native/emulated userland |
| Controller-dependent game | Verifies input routing through runtime/container |
| Video-heavy title | Exposes media and codec/runtime issues |

For each title record:

- launch success
- time to first frame
- controller/input behavior
- graphics correctness
- shader/stutter behavior
- runtime/proton log outcome
- regressions compared with today's FEX-driven path

## 13. Risks We Are Accepting

This plan deliberately accepts the following risks:

- Upstream ARM64 Proton behavior may change quickly
- Steam client-side integration may lag behind Proton readiness
- Some boards will fail due to page-size or runtime/container assumptions
- Existing global FEX AppConfig tuning may not map cleanly into Proton-embedded FEX behavior
- We may need temporary Razorfin glue that is later deleted once upstream settles

These are acceptable tracer-bullet risks.

## 14. Open Questions

These questions should be answered during implementation, not before it starts:

1. Can the staged ARM64 Proton tool be driven cleanly from our host without a fully native ARM Steam client?
2. Which Steam launch environment variables are the minimum required for a faithful ARM64 Proton invocation?
3. Does Proton's per-title `proton-fex-config.json` flow replace part of our current global FEX AppConfig strategy?
4. Do we still need systemwide Linux-side FEX thunks for the primary Windows game path?
5. What is the cleanest immutable-host packaging model for Valve's runtime artifacts?

## 15. Near-Term Repo Impact

The next implementation work should likely concentrate in:

- `build_files/01-gaming.sh`
- `README.md`
- new launcher scripts under `build_files/`
- new docs describing staged runtime/tool versions and validation commands

The likely long-term outcome is:

- `razorfin-steam` becomes legacy or fallback
- ARM64 Proton staging becomes first-class
- systemwide FEX Linux emulation remains available, but not as the primary Windows game architecture

## 16. Success Criteria

The tracer bullet is successful when all of the following are true:

- Razorfin can stage a Valve-style ARM64 runtime and Proton tool reproducibly
- at least one representative Windows game launches through that path
- the path is documented clearly enough for repeated testing and iteration
- the architecture reduces dependence on "Steam itself runs under FEX" as the main compatibility model

## 17. Sources

Primary sources used to derive this architecture:

- Valve Proton 11.0-beta1 release notes: <https://github.com/ValveSoftware/Proton/releases/tag/proton-11.0-1-beta1>
- Valve Proton ARM64 branch and tool manifests: <https://github.com/ValveSoftware/Proton/tree/proton_11.0>
- Public Steam Linux Runtime 4 ARM64 artifacts: <https://repo.steampowered.com/steamrt4/images/latest-container-runtime-public-beta/>
- Public Proton 11.0 (ARM64) tool listing: <https://store.steampowered.com/app/4628740/>
- FEX ARM64EC/WOW64 integration notes: <https://wiki.fex-emu.com/index.php/Development:ARM64EC>
- FEX 2501 notes on Wine WoW64/Arm64ec package support: <https://fex-emu.com/FEX-2501/>
