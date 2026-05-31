It is **always** better to install packages with Distrobox rather than layer them with rpm-ostree~[More info](https://distrobox.it/)
Packages installed in Distrobox can be exported to appear like any other application~[View documentation](https://distrobox.it/usage/distrobox-export/)
*This isn't a distro*, this is a custom image built on Fedora Atomic Desktop technology~[Learn more](https://fedoraproject.org/atomic-desktops/)
**Razorfin** combines COSMIC desktop with FEX-Emu gaming on ARM/aarch64~[View on GitHub](https://github.com/RazorfinOS-org/Razorfin-ARM)
**COSMIC** is a new desktop environment from System76, built with Rust~[Learn more](https://system76.com/cosmic)
**FEX-Emu** translates x86/x86-64 games to run natively on your ARM hardware~[Learn more](https://fex-emu.com/)
Razorfin stages a Valve-style ARM64 Steam Runtime by default; run `razorfin-steam-arm64 status` to inspect it
Run `razorfin-proton-arm64-run --status` to see whether an ARM64 Proton tool is available
Run `razorfin-steam` to launch the legacy FEX-driven Steam path, or use `FEXBash` for any x86 application
Run `fastfetch` to see detailed system information with Razorfin branding
Use `distrobox create -n dev` to spin up a mutable container for development
