# Razorfin ARM

[![build](https://github.com/RazorfinOS-org/Razorfin-ARM/actions/workflows/build.yml/badge.svg)](https://github.com/RazorfinOS-org/Razorfin-ARM/actions/workflows/build.yml)

Razorfin ARM is an aarch64 port of [Razorfin](https://github.com/RazorfinOS-org/Razorfin), built on [Fedora COSMIC Atomic](https://fedoraproject.org/atomic-desktops/cosmic/) 43. It combines the [COSMIC](https://system76.com/cosmic) desktop environment with [FEX-Emu](https://fex-emu.com/) for x86/x86-64 game and application support on ARM hardware.

## Variants

| Variant | Description |
|---------|-------------|
| `razorfin-arm` | COSMIC desktop + FEX-Emu gaming stack |
| `razorfin-arm-dx` | COSMIC desktop + FEX-Emu gaming + developer tools |

## What's Included

- **COSMIC Desktop** — System76's modern, Rust-based desktop environment
- **FEX-Emu** — x86/x86-64 binary translator with Vulkan/OpenGL thunks for near-native GPU performance
- **Steam** — Runs via FEX-Emu with the `razorfin-steam` launcher
- **Mesa/Vulkan** — Native ARM64 GPU drivers
- **Gaming tools** — Gamescope, MangoHud, GameMode (where available for aarch64)
- **Razorfin branding** — Custom Plymouth theme, fastfetch, MOTD

## Hardware Requirements

- **Architecture**: Generic aarch64 (ARM64) with UEFI boot
- **Kernel page size**: 4K (required by FEX-Emu; Fedora aarch64 default)
- **GPU**: Any GPU with Mesa Vulkan drivers (AMD, Intel, Qualcomm Adreno)
- **Not supported**: Apple Silicon (requires Asahi kernel patches)

## Release Channels

Images are built once and promoted between channels by re-tagging, so each channel ships the exact same image digest that was validated in the tier below it.

| Channel | Cadence | Description |
|---------|---------|-------------|
| `testing` | Every push to `main` | Bleeding edge — latest changes, may have rough edges |
| `latest` | Daily | Previous day's `testing` build, suitable for general use |
| `stable` | Weekly (Tuesdays) | Previous week's `latest`, recommended for most users |

Each promotion also creates a date-stamped tag (e.g., `stable.20260208`) for pinning or rollback.

## Installation

### Switch from an existing Fedora Atomic system

```bash
# Base variant — stable channel (recommended)
sudo bootc switch --enforce-container-sigpolicy ghcr.io/razorfinos-org/razorfin-arm:stable

# DX variant
sudo bootc switch --enforce-container-sigpolicy ghcr.io/razorfinos-org/razorfin-arm-dx:stable
```

To track a different channel, replace `:stable` with `:latest` or `:testing`.

## Using FEX-Emu

FEX-Emu enables running x86/x86-64 applications on your ARM64 hardware:

```bash
# Run any x86 binary
FEXBash ./some-x86-binary

# Launch Steam
razorfin-steam

# Verify FEX is working
FEXBash uname -m  # Should output: x86_64
```

FEX-Emu thunks forward Vulkan and OpenGL calls to native ARM64 Mesa drivers, providing near-native GPU performance for games.

## Image Verification

All images are signed with [Cosign](https://docs.sigstore.dev/cosign/overview/). The public key is included in this repository as [`cosign.pub`](cosign.pub).

```bash
cosign verify --key cosign.pub ghcr.io/razorfinos-org/razorfin-arm:stable
```

## Changing Channels

```bash
# Move to the stable channel
sudo bootc switch --enforce-container-sigpolicy ghcr.io/razorfinos-org/razorfin-arm:stable

# Pin to a specific date-stamped image
sudo bootc switch --enforce-container-sigpolicy ghcr.io/razorfinos-org/razorfin-arm:stable.20260208

systemctl reboot
```

## Rollback

```bash
# Roll back to the previous deployment
sudo bootc rollback
systemctl reboot

# Or switch to a known-good date-stamped image
sudo bootc switch --enforce-container-sigpolicy ghcr.io/razorfinos-org/razorfin-arm:stable.20260201
systemctl reboot
```

## Building Locally

Razorfin ARM uses [Just](https://just.systems/) for build automation.

### Container Images

```bash
just build                  # Base variant (generic aarch64)
just build-dx               # DX variant (developer tools)
just build-rpi5             # Raspberry Pi 5 variant (experimental)
just build-rockchip         # Rockchip variant (experimental)
```

### QCOW2 VM Images

```bash
just build-qcow2            # Build QCOW2
just run-vm-qcow2           # Build and run in a VM
```

Run `just` with no arguments to see all available recipes.

## Differences from x86 Razorfin

| Feature | x86 Razorfin | Razorfin ARM |
|---------|-------------|--------------|
| Base image | Bazzite (Universal Blue) | Fedora COSMIC Atomic 43 |
| Architecture | x86_64 | aarch64 |
| Gaming | Native x86 + Proton | FEX-Emu x86 translation + Proton |
| NVIDIA variants | Yes | No (ARM NVIDIA is rare) |
| ISOs | Monthly | Planned (container-only for v1) |

## Contributing

See the [release runbook](docs/release-runbook.md) for details on the CI/CD pipeline, emergency hotfix procedures, and rollback operations.

## Community

- [Universal Blue Forums](https://universal-blue.discourse.group/)
- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [COSMIC Desktop](https://system76.com/cosmic)
- [FEX-Emu](https://fex-emu.com/)

## License

Apache-2.0
