# omarchy-wsl

Build and generate installable **`.wsl`** packages for [Omarchy](https://omarchy.org)
— in both a **basic** (CLI/TUI) and a **desktop** (full Hyprland) flavour — using
[`wslc`](https://learn.microsoft.com/windows/wsl/) (the Docker-compatible Windows
Subsystem for Linux Container CLI).

> [Omarchy](https://omarchy.org) is a beautiful, modern & opinionated Arch-based
> Linux setup by DHH. This repo packages it for WSL; the upstream sources are
> fetched into [`omarchy/`](#1-get-an-up-to-date-omarchy-checkout) by
> `setup-omarchy.ps1`.

---

## TL;DR

```powershell
# 1. Fetch an up-to-date Omarchy checkout into ./omarchy
./setup-omarchy.ps1

# 2. Build both images AND export installable .wsl files
./build-distros.ps1 -Export
#    -> Omarchy.wsl        (full desktop)
#    -> Omarchy-Basic.wsl  (CLI/TUI only)

# 3. Install one
wsl --install --from-file Omarchy.wsl
wsl -d Omarchy
```

You land in a login shell as the `omarchy` user with the Omarchy command suite
(`omarchy …`), shell aliases/functions, Tokyo Night theming, and the headline CLI
tools (`bat`, `eza`, `fzf`, `rg`, `lazygit`, `nvim`, `btop`, …). The desktop
flavour additionally bakes in the full Hyprland stack.

---

## The two distros

Both are produced from the **same** Dockerfile by
[`build-distros.ps1`](build-distros.ps1):

| Image / `.wsl`    | Build arg   | Contents                                         | Size    |
| ----------------- | ----------- | ------------------------------------------------ | ------- |
| `omarchy:desktop` → `Omarchy.wsl`       | `DESKTOP=1` | Full Omarchy graphical desktop (Hyprland + apps) | ~14 GB |
| `omarchy:basic` → `Omarchy-Basic.wsl`   | `DESKTOP=0` | Curated CLI/TUI-only Omarchy                     | ~4 GB   |

Both bake in identical WSL distribution assets, so they register under the same
name **Omarchy** with the same default user — see [Shared distro
identity](#shared-distro-identity).

---

## 1. Get an up-to-date Omarchy checkout

The upstream Omarchy sources are **not** vendored in this repo (they are large
and change fast). Fetch them with:

```powershell
./setup-omarchy.ps1            # clone, or fast-forward to the latest upstream
./setup-omarchy.ps1 -Ref v3.4.2   # pin to a tag/branch/commit
./setup-omarchy.ps1 -Force        # delete ./omarchy and re-clone
```

This clones `https://github.com/basecamp/omarchy.git` into [`omarchy/`](omarchy/)
(default branch) on first run and fast-forwards it afterwards. The full `.git`
directory is kept on purpose: the Dockerfile regenerates the working tree from
git blobs to fix Windows CRLF/exec-bit issues, and `omarchy update` uses it
inside the distro.

`omarchy/` is `.gitignore`d, so this repo stays small and never re-publishes
upstream's tree.

## 2. Build the images

```powershell
./build-distros.ps1            # build omarchy:desktop and omarchy:basic
./build-distros.ps1 -Export    # build + write Omarchy.wsl / Omarchy-Basic.wsl
./build-distros.ps1 -Only basic -Export
./build-distros.ps1 -NoCache
```

To build a single image with fine-grained desktop toggles, use
[`build.ps1`](build.ps1) directly — see [Desktop options](#desktop-options).

## 3. Generate `.wsl` packages

`-Export` on `build-distros.ps1` runs [`export-wsl.ps1`](export-wsl.ps1) for each
image. A `.wsl` file is just a gzip-tar of the distro's root filesystem; the
script creates a throwaway container, exports its rootfs, and removes the
container:

```powershell
# Export any already-built image on its own
./export-wsl.ps1 -Image omarchy:desktop -OutFile Omarchy.wsl
./export-wsl.ps1 -Image omarchy:basic   -OutFile Omarchy-Basic.wsl
```

Install the result by double-clicking it, or:

```powershell
wsl --install --from-file Omarchy.wsl
wsl -d Omarchy
```

> Installing **both** distros on one machine collides on the registered name
> `Omarchy` — pass `--name` to disambiguate the second one, e.g.
> `wsl --install --from-file Omarchy-Basic.wsl --name Omarchy-Basic`.

## 4. Verify (optional)

[`test.ps1`](test.ps1) runs a throwaway container and asserts the Omarchy CLI
dispatches, the bash environment loads, configs are present, the active theme is
`tokyo-night`, `/etc/wsl.conf` is correct, passwordless sudo works, and the
headline CLI tools are installed:

```powershell
./test.ps1 -Tag omarchy:desktop
# => ALL_CHECKS_PASSED / VERIFICATION PASSED
```

---

## Why not just run upstream `install.sh`?

Omarchy's `install.sh` is a **bare-metal Arch desktop** installer. Its preflight
guards (`omarchy/install/preflight/guard.sh`) hard-require:

- the **Limine** bootloader and a **Btrfs** root filesystem,
- Secure Boot disabled, an interactive TTY with `gum`, and a non-root user,

and it then installs a full **Hyprland** desktop, **SDDM**, **Plymouth**,
**snapper**, and hardware-specific drivers. None of that exists — or makes sense
— inside a WSL container, so running `install.sh` is neither possible nor
desirable here.

Instead, the build **reuses Omarchy's real assets** and skips only the
bare-metal/desktop machinery:

| Omarchy asset (reused as-is)                                  | Where it comes from                          |
| ------------------------------------------------------------- | -------------------------------------------- |
| Official `[omarchy]` pacman repo + `omarchy-keyring`          | `omarchy/install/preflight/pacman.sh`        |
| `omarchy-*` command suite                                     | `omarchy/bin/`                               |
| Default configs copied to `~/.config`                         | `omarchy/install/config/config.sh`           |
| Omarchy bash environment (`default/bash/*`) + `.bashrc`       | `omarchy/default/`                           |
| Theming system (Tokyo Night by default)                       | `omarchy/install/config/theme.sh`            |
| Branding, XDG user dirs, migration state markers              | `omarchy/install/config/*`                   |

This keeps the WSL experience faithful to upstream Omarchy on the terminal while
dropping the parts that require real hardware and a running compositor.

---

## How it works

The build is driven by [`Dockerfile`](Dockerfile) and the WSL-adapted installer
[`install/omarchy-wsl-install.sh`](install/omarchy-wsl-install.sh):

1. **Base** — `FROM archlinux:latest` (Omarchy is Arch-based). Initialise the
   pacman keyring and install `base-devel git sudo`.
2. **User** — create the default `omarchy` user (in `wheel`, passwordless sudo),
   mirroring Omarchy's user-level install model (it refuses to run as root).
3. **Sources** — copy the `omarchy/` checkout (including `.git`) into
   `~/.local/share/omarchy` — the path every script expects via `$OMARCHY_PATH`.
4. **Normalise for Linux** — the build context comes from Windows, where
   `core.autocrlf` rewrote tracked files to **CRLF** and dropped the **+x** bit.
   `git reset --hard` regenerates the working tree from the git blobs, restoring
   LF endings and executable bits exactly as upstream ships them. Keeping `.git`
   also lets `omarchy update` work inside the distro.
5. **Install** — run `omarchy-wsl-install.sh`, which wires up the `[omarchy]`
   repo, installs packages, copies configs, applies the theme, and runs
   `omarchy-nvim-setup`.
6. **WSL config** — drop in [`wsl.conf`](wsl.conf) (systemd on, default user
   `omarchy`) and the shared [distribution assets](#shared-distro-identity).

### Container adaptations (documented, minimal)

- **Pacman download sandbox** — Omarchy's `pacman.conf` sets `DownloadUser =
  alpm`, which drops pacman into a Landlock sandbox. That syscall is blocked in
  an unprivileged container build, so the installer disables the download
  sandbox (`DisableSandbox`). On real hardware the upstream sandbox still
  applies.
- **No running compositor** — `omarchy-theme-set` still generates the full
  themed config tree, but its "restart Waybar/Hyprland/mako" steps are no-ops in
  a container and are tolerated.

---

## Desktop options

The desktop image ships the **full Omarchy desktop**. The package set is
composed as:

```
packages/omarchy-wsl.packages   (curated CLI core — always installed)
  ∪ omarchy-base.packages       (full desktop — when DESKTOP=1)
  −  any desktop groups toggled off
```

Each desktop option is a build arg (default `1` = on). Set it to `0` to slim the
image. The master `DESKTOP` switch controls the whole Hyprland stack; the rest
are subtractive opt-outs that each map to a file under
[`packages/groups/`](packages/groups):

| Build arg  | Switch (`build.ps1`) | When `0`                                                             | Group file |
| ---------- | -------------------- | -------------------------------------------------------------------- | ---------- |
| `DESKTOP`  | `-NoDesktop`         | CLI-only image — installs just `omarchy-wsl.packages` (no Hyprland)  | —          |
| `APPS`     | `-NoApps`            | Skip large GUI apps (browser, office, media editors, chat, …)        | [`apps.packages`](packages/groups/apps.packages) |
| `LOGIN`    | `-NoLogin`           | Skip `sddm` + `plymouth` (login manager / boot splash)               | [`login.packages`](packages/groups/login.packages) |
| `PRINTING` | `-NoPrinting`        | Skip the CUPS printing stack + mDNS                                  | [`printing.packages`](packages/groups/printing.packages) |
| `INPUT`    | `-NoInput`           | Skip `fcitx5` input methods                                          | [`input.packages`](packages/groups/input.packages) |

```powershell
# Full desktop (default tag omarchy:latest)
./build.ps1

# Desktop, but without the heavy apps, login manager, or printing
./build.ps1 -NoApps -NoLogin -NoPrinting

# CLI-only image (no desktop at all)
./build.ps1 -NoDesktop -Tag omarchy:basic

# Equivalent raw wslc invocation
wslc build -t omarchy:latest --build-arg DESKTOP=1 --build-arg APPS=0 .
```

**Adding your own toggle group** is easy: drop a new
`packages/groups/<name>.packages` file, add a matching `ARG <NAME>=1` in the
`Dockerfile`, pass it through on the installer `RUN` line, and register it in the
`group_toggle` map in `install/omarchy-wsl-install.sh`.

---

## Shared distro identity

Both images bake in the **same** WSL distribution assets, so they register
identically:

- `/etc/wsl-distribution.conf` — `defaultName = Omarchy`, `defaultUid = 1000`,
  Start-menu shortcut icon, and Windows Terminal profile. Byte-for-byte
  identical in both images.
- `/etc/oobe.sh` — first-run script. The `omarchy` user is baked in at uid 1000
  (`= defaultUid`), so the OOBE confirms it and prints a welcome instead of
  prompting to create an account.
- `/usr/lib/wsl/omarchy.ico` — multi-resolution icon converted from Omarchy's
  `icon.png`.
- `/usr/lib/wsl/terminal-profile.json` — Tokyo Night colours matching the
  default theme.
- `/etc/wsl.conf` — `systemd=true`, default user `omarchy`.

### Boot hardening for WSL

A few systemd adjustments are baked in so the distro boots cleanly under WSL:

- **`systemd-firstboot` is masked.** It otherwise runs on first boot with
  `--prompt-locale`/`--prompt-root-password` and blocks waiting for console
  input that never arrives under WSL, wedging boot in the `initializing` state
  so `dbus`, `systemd-logind` and the user session never start.
- **Default target is `multi-user.target`** (not `graphical.target`): WSL has no
  boot-time display manager, so the graphical target would only try to start
  `sddm`. Hyprland is launched on demand via WSLg.
- **`en_US.UTF-8` locale** is generated and set as `LANG` (Omarchy's upstream
  default), avoiding "cannot change locale" warnings in interactive shells.
- **Networking/tmpfiles units are masked** (`systemd-resolved`,
  `systemd-networkd`, `NetworkManager`, the `systemd-tmpfiles-*` units and
  `tmp.mount`) since WSL manages networking and mounts itself, and no
  `/etc/resolv.conf` is shipped (WSL generates its own).

Verified end to end: importing the exported `.wsl` boots to
`systemctl is-system-running` = **running**, default user `omarchy` (uid 1000),
`dbus`/`logind` active, and the `omarchy` CLI on `PATH`.

---

## Files

| Path                                   | Purpose                                                  |
| -------------------------------------- | -------------------------------------------------------- |
| `setup-omarchy.ps1`                    | Fetch/update the upstream Omarchy checkout into `omarchy/` |
| `build.ps1`                            | Build a single image (with desktop toggle switches)      |
| `build-distros.ps1`                    | Build both `omarchy:desktop` and `omarchy:basic` (`-Export` writes `.wsl`) |
| `export-wsl.ps1`                       | Export a built image to an installable `.wsl` file       |
| `test.ps1`                             | Post-build verification                                  |
| `Dockerfile`                           | Build recipe + desktop toggle build args                 |
| `install/omarchy-wsl-install.sh`       | WSL-adapted Omarchy installer (runs in the build)        |
| `packages/omarchy-wsl.packages`        | Curated CLI/TUI core package list (always installed)     |
| `packages/groups/*.packages`           | Toggleable desktop option groups                         |
| `wsl.conf`                             | Per-distro WSL config baked into the image (systemd, default user) |
| `wsl/wsl-distribution.conf`            | Distro identity: name, default uid, shortcut icon, terminal profile |
| `wsl/oobe.sh`                          | First-run experience (confirms the baked-in `omarchy` user) |
| `wsl/terminal-profile.json`            | Windows Terminal profile (Tokyo Night, matches default theme) |
| `omarchy/`                             | Upstream Omarchy checkout (fetched by `setup-omarchy.ps1`; git-ignored) |

---

## Requirements

- Windows with **WSL** and the **`wslc`** container CLI (`wslc.exe` on `PATH`).
- **Git** (for `setup-omarchy.ps1`).
- PowerShell 5.1+ (the scripts are `pwsh`-compatible too).

## License

Tooling in this repository is released under the MIT License. Omarchy itself is
maintained upstream by Basecamp under the
[MIT License](https://github.com/basecamp/omarchy/blob/master/LICENSE).
