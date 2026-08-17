# Omarchy-wsl

Build an installable **`.wsl`** package for the basic (CLI/TUI) flavour of
[Omarchy](https://omarchy.org) using [`wslc`](https://learn.microsoft.com/windows/wsl/).

This is a community project.

## Build

```powershell
./build-omarchy.ps1
```

This fetches the upstream Omarchy sources into `omarchy/` (pinned to `v4.0.0` —
see "Upstream version" below), builds the curated CLI image for your host's
CPU architecture, and exports `Omarchy-Basic.wsl`.

## Install

```powershell
wsl --install --from-file Omarchy-Basic.wsl
wsl -d Omarchy
```

You land in a login shell as the `omarchy` user with the Omarchy command suite,
Tokyo Night theming, and the headline CLI tools (`bat`, `eza`, `fzf`, `rg`,
`lazygit`, `nvim`, `btop`, …).

## Architecture support (amd64 / arm64)

Both x86_64 (`amd64`) and ARM64 (`arm64`) are supported. `build.ps1` (and
`build-omarchy.ps1`) auto-detect the host architecture; override with
`-Arch amd64` / `-Arch arm64` if needed. wslc can't cross-build, so build on
the target architecture.

Upstream Arch's Docker image and Omarchy's `[omarchy]` pacman repo are both
x86_64-only, so the arm64 build boots from the official
[Arch Linux ARM](https://archlinuxarm.org) rootfs instead, and builds the few
packages missing from its repos (`omarchy-nvim`, `yay`, `mise`) from source.
See `install/omarchy-wsl-install.sh` for details.

## Upstream version

`setup-omarchy.ps1` pins the Omarchy checkout to **`v4.0.0`** ("Quattro") by
default. Pass `-Ref` to override, but re-verify the installer against that
layout first — upstream has restructured `install/` before between releases.

## Requirements

- Windows with **WSL** and the **`wslc`** CLI (`wslc.exe` on `PATH`)
- **Git** and **PowerShell 5.1+**

## License

MIT. Omarchy itself is maintained upstream by Basecamp under the
[MIT License](https://github.com/basecamp/omarchy/blob/master/LICENSE).
