#!/bin/bash
# Omarchy WSL installer — runs INSIDE the container build (not on bare metal).
#
# This is the WSL-adapted counterpart to upstream Omarchy's install.sh. Upstream
# install.sh targets bare-metal Arch (Limine bootloader, Btrfs root, SDDM,
# Plymouth, Hyprland, hardware drivers) and its preflight guards refuse to run
# anywhere else. Inside a WSL container none of that applies, so instead of
# sourcing install.sh we reuse Omarchy's real assets directly:
#
#   * the official [omarchy] pacman repo + omarchy-keyring (install/preflight/pacman.sh)
#   * the bin/ command suite (omarchy-*, theming, helpers)
#   * the config/ defaults and default/bash shell environment (install/config/config.sh)
#   * the theming system (install/config/theme.sh)
#
# It is meant to be run as the unprivileged `omarchy` user with passwordless
# sudo, mirroring Omarchy's user-level install model.

set -eEo pipefail

# --- Desktop feature toggles (env, all default to enabled "1") ---------------
# DESKTOP  master switch: 1 = full Omarchy desktop, 0 = curated CLI set only.
# When DESKTOP=1, these optional groups can each be turned off independently:
#   APPS     large GUI apps (browser, office, media editors, chat, …)
#   LOGIN    display/login manager + boot splash (sddm, plymouth)
#   PRINTING CUPS printing stack + mDNS
#   INPUT    fcitx5 input methods
# Each group maps to packages/groups/<group>.packages.
DESKTOP="${DESKTOP:-1}"
APPS="${APPS:-1}"
LOGIN="${LOGIN:-1}"
PRINTING="${PRINTING:-1}"
INPUT="${INPUT:-1}"

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_MIRROR="stable"
export PATH="$OMARCHY_PATH/bin:$PATH:$HOME/.local/bin"

# Docker `RUN` doesn't set $USER/$LOGNAME the way a login shell does; several
# Omarchy scripts (e.g. omarchy-nvim-setup) reference $USER, so define them.
export USER="${USER:-$(id -un)}"
export LOGNAME="${LOGNAME:-$USER}"

# Skip background/wallpaper work that needs a running compositor.
export OMARCHY_THEME_SKIP_BACKGROUND=1

WSL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\e[32m[omarchy-wsl]\e[0m $*"; }

# --- 1. Configure the Omarchy pacman repo + keyring -------------------------
# Mirrors install/preflight/pacman.sh (the OMARCHY_ONLINE_INSTALL branch).
log "Configuring Omarchy pacman repository and keyring"

sudo cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR}.conf" /etc/pacman.conf
sudo cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR}" /etc/pacman.d/mirrorlist

# Container adaptation: Omarchy's pacman.conf sets `DownloadUser = alpm`, which
# makes pacman drop privileges into a Landlock sandbox. That syscall is blocked
# inside an unprivileged container build ("Landlock ruleset could not be
# applied"), so disable the download sandbox here. On real hardware the upstream
# sandboxed download still applies.
sudo sed -i 's/^DownloadUser/#DownloadUser/' /etc/pacman.conf
sudo grep -q '^DisableSandbox' /etc/pacman.conf || \
  sudo sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org
sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

sudo pacman -Sy --noconfirm
sudo pacman -S --noconfirm --needed --overwrite '*' omarchy-keyring

# Full sync/upgrade against the Omarchy mirror so versions match upstream.
sudo pacman -Syyuu --noconfirm

# --- 2. Install packages ----------------------------------------------------
# The package set is composed from:
#   * packages/omarchy-wsl.packages  — curated CLI core (always installed)
#   * omarchy-base.packages          — the full desktop set (when DESKTOP=1)
# minus any optional desktop groups that have been toggled off.
read_list() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

declare -A want
while read -r p; do [[ -n $p ]] && want[$p]=1; done \
  < <(read_list "$WSL_DIR/../packages/omarchy-wsl.packages")

if [[ $DESKTOP == 1 ]]; then
  log "Composing FULL Omarchy desktop package set"
  while read -r p; do [[ -n $p ]] && want[$p]=1; done \
    < <(read_list "$OMARCHY_INSTALL/omarchy-base.packages")

  GROUPS_DIR="$WSL_DIR/../packages/groups"
  declare -A group_toggle=([apps]="$APPS" [login]="$LOGIN" [printing]="$PRINTING" [input]="$INPUT")
  for g in "${!group_toggle[@]}"; do
    if [[ ${group_toggle[$g]} == 0 ]]; then
      log "Desktop group '$g' disabled — excluding its packages"
      while read -r p; do [[ -n $p ]] && unset "want[$p]"; done \
        < <(read_list "$GROUPS_DIR/$g.packages")
    fi
  done
else
  log "DESKTOP=0 — installing curated CLI package set only"
fi

mapfile -t packages < <(printf '%s\n' "${!want[@]}" | sort)
log "Installing ${#packages[@]} packages: ${packages[*]}"
omarchy-pkg-add "${packages[@]}"

# --- 3. Copy Omarchy configs + shell environment ----------------------------
# Mirrors install/config/config.sh.
log "Installing Omarchy configs and bashrc"
mkdir -p ~/.config
cp -R "$OMARCHY_PATH/config/"* ~/.config/
cp "$OMARCHY_PATH/default/bashrc" ~/.bashrc

# --- 4. Branding (install/config/branding.sh) -------------------------------
log "Installing branding"
mkdir -p ~/.config/omarchy/branding
cp "$OMARCHY_PATH/icon.txt" ~/.config/omarchy/branding/about.txt
cp "$OMARCHY_PATH/logo.txt" ~/.config/omarchy/branding/screensaver.txt

# --- 5. XDG user dirs (install/config/user-dirs.sh, GUI bits skipped) --------
log "Creating user directories"
mkdir -p ~/Downloads ~/Pictures ~/Videos ~/Projects
if omarchy-cmd-present xdg-user-dirs-update; then
  xdg-user-dirs-update --set TEMPLATES "$HOME" || true
  xdg-user-dirs-update --set PUBLICSHARE "$HOME" || true
  xdg-user-dirs-update --set DESKTOP "$HOME" || true
fi

# --- 6. Theme (install/config/theme.sh) -------------------------------------
log "Setting default theme: Tokyo Night"
mkdir -p ~/.config/omarchy/themes ~/.config/btop/themes
# Restart hooks for compositor apps are no-ops here (nothing is running), so
# tolerate their absence while still producing the themed config tree.
omarchy-theme-set "Tokyo Night" || true
if [[ -f ~/.config/omarchy/current/theme/btop.theme ]]; then
  ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme
fi

# --- 7. Neovim (install/packaging/nvim.sh) ----------------------------------
if omarchy-cmd-present omarchy-nvim-setup; then
  log "Running omarchy-nvim-setup"
  omarchy-nvim-setup || true
fi

# --- 8. Mark migrations as already applied ----------------------------------
# Mirrors install/preflight/migrations.sh so future `omarchy update` runs don't
# replay historical migrations against a fresh install.
log "Marking existing migrations as applied"
OMARCHY_MIGRATIONS_STATE_PATH=~/.local/state/omarchy/migrations
mkdir -p "$OMARCHY_MIGRATIONS_STATE_PATH"
for file in "$OMARCHY_PATH"/migrations/*.sh; do
  [[ -e $file ]] || continue
  touch "$OMARCHY_MIGRATIONS_STATE_PATH/$(basename "$file")"
done

# --- 9. Clean caches to keep the image small --------------------------------
log "Cleaning package cache"
sudo pacman -Scc --noconfirm || true

log "Omarchy WSL install complete (DESKTOP=$DESKTOP APPS=$APPS LOGIN=$LOGIN PRINTING=$PRINTING INPUT=$INPUT)"
