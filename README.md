# Omarchy-wsl

Build an installable **`.wsl`** package for the basic (CLI/TUI) flavour of
[Omarchy](https://omarchy.org) using [`wslc`](https://learn.microsoft.com/windows/wsl/).

This is a community project.

## Build

```powershell
./build-omarchy.ps1
```

This fetches the upstream Omarchy sources into `omarchy/`, builds the curated CLI
image, and exports `Omarchy-Basic.wsl`.

## Install

```powershell
wsl --install --from-file Omarchy-Basic.wsl
wsl -d Omarchy
```

You land in a login shell as the `omarchy` user with the Omarchy command suite,
Tokyo Night theming, and the headline CLI tools (`bat`, `eza`, `fzf`, `rg`,
`lazygit`, `nvim`, `btop`, …).

## Requirements

- Windows with **WSL** and the **`wslc`** CLI (`wslc.exe` on `PATH`)
- **Git** and **PowerShell 5.1+**

## License

MIT. Omarchy itself is maintained upstream by Basecamp under the
[MIT License](https://github.com/basecamp/omarchy/blob/master/LICENSE).
