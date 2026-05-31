# Proton ARM64 Placeholder

This directory is reserved for a user-installed Valve-style ARM64 Proton tool.

Razorfin's ARM64 runtime harness looks for a working `proton` launcher here first:

`/usr/lib/razorfin/steam-arm/compatibilitytools.d/Proton-11.0-arm64`

If the tool is not present here, Razorfin will also check common Steam-managed locations such as:

- `~/.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)`
- `~/.steam/root/steamapps/common/Proton 11.0 (ARM64)`
- local `compatibilitytools.d` directories containing `toolmanifest_arm64.vdf`

Expected Steam app:

- `4628740` — `Proton 11.0 (ARM64)`
